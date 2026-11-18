"""The hand-written Makefile recipes keep the gate honest.

The suite's image has no `make`, so these read the Makefile's text and pin each recipe's shape and
each refusal's condition. A green run here says the text is in place, not that make behaves.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import re
from pathlib import Path

MAKEFILE = (Path(__file__).resolve().parent.parent / "Makefile").read_text()


def recipe(target):
    """The logical recipe lines of a target, backslash continuations joined."""
    lines = MAKEFILE.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(f"{target}:"))
    logical, current = [], ""
    for line in lines[start + 1 :]:
        if not line.startswith("\t") and not current:
            break
        current += line.lstrip("\t")
        if current.endswith("\\"):
            current = current[:-1]
            continue
        logical.append(current)
        current = ""
    return logical


def definition(name):
    """The one line that defines a make variable, refusing a name defined more than once.

    make keeps the last of several definitions, so a test reading only the first would pass while
    make uses another. Every form counts: any assignment operator, `override`, `export`, a
    target-specific setting and `define`.
    """
    assignment = re.compile(
        rf"^(?:[^\t#][^=]*:\s*)?(?:override\s+)?(?:export\s+)?(?:define\s+)?{re.escape(name)}\s*(?:[:+?!]|::|:::)?=?(?:\s|$)"
    )
    found = [
        line
        for line in logical_lines()
        if assignment.match(line) and not line.startswith(("\t", "#"))
    ]
    assert len(found) == 1, f"{name} is defined {len(found)} times: {found}"
    assert found[0].startswith(f"override {name} ="), found[0]
    return found[0]


def logical_lines():
    """The Makefile's lines as make reads them: backslash continuations joined, blanks folded."""
    logical, current = [], ""
    for line in MAKEFILE.splitlines():
        if current:
            line = " " + line.lstrip()
        current += line
        if current.endswith("\\"):
            current = current[:-1].rstrip()
            continue
        logical.append(current)
        current = ""
    return logical


def container_command(target):
    """A target's `docker run` up to its image, whitespace folded: what the container is given."""
    text = "\n".join(recipe(target))
    return " ".join(text.split("docker run", 1)[1].split("$(TAIL_IMAGE)", 1)[0].split())


def container_steps_of(text):
    """The `&&` steps of the `sh -c` script the TAIL_IMAGE container runs, whitespace folded."""
    script = text.split("$(TAIL_IMAGE) ", 1)[1].split("sh -c '", 1)[1].split("'", 1)[0]
    return [" ".join(step.split()) for step in script.split("&&")]


def container_steps(target):
    """The container script's steps in a target's recipe."""
    return container_steps_of("\n".join(recipe(target)))


def test_recipes_mount_the_checkout_through_the_quoted_definition():
    assert definition("CHECKOUT") == "override CHECKOUT = '$(subst ','\\'',$(CURDIR))'"
    for target in ("audit-lock", "format", "test"):
        text = "\n".join(recipe(target))
        assert '"$(CURDIR)"' not in text, target
        assert "$(CHECKOUT):/repo" in text, target
    assert recipe("build") == ["$(call BUILD_ARTIFACTS,$(CHECKOUT))"]
    assert "-v $(1):/repo" in definition("BUILD_ARTIFACTS")
    # pip needs a home it can write as a user the image does not know.
    assert "--user $(REPO_UID):$(REPO_GID) -e HOME=/tmp" in definition(
        "BUILD_ARTIFACTS"
    )


def test_artifacts_are_built_by_the_hash_pinned_tools_of_the_commit():
    assert definition("PIN_BUILD_TOOLS") == (
        "override PIN_BUILD_TOOLS = pip install -q --root-user-action=ignore --no-deps"
        " --require-hashes -r requirements/build.txt >/dev/null"
    )
    assert container_steps_of(definition("BUILD_ARTIFACTS")) == [
        "$(PIN_BUILD_TOOLS)",
        "python -m build --no-isolation --outdir dist",
    ]


def test_the_suite_tests_a_wheel_the_pinned_tools_built_in_a_clean_image():
    # The container is given nothing that could put the tree ahead of the wheel (a PYTHONPATH).
    assert container_command("test") == (
        '--rm $(guard_caps) -v $(CHECKOUT):/repo:ro -w /repo -v "$$D":/out'
        " -e PYTHONDONTWRITEBYTECODE=1"
    )
    # pip skips the hash of a requirement already installed at its pinned version, so the pinned
    # set goes in first; nothing installs the tree itself, so the suite tests that wheel alone.
    assert container_steps("test") == [
        "$(PIN_BUILD_TOOLS)",
        "python -m build -q --no-isolation --wheel --outdir /tmp/wheel . >/dev/null",
        "pip install -q --root-user-action=ignore pytest pytest-asyncio coverage >/dev/null",
        "pip install -q --root-user-action=ignore /tmp/wheel/*.whl >/dev/null",
        "export COVERAGE_CORE=sysmon COVERAGE_FILE=/out/.coverage",
        "python -m coverage run --branch --source=brother_ql -m pytest -c /out/pytest.ini"
        " --rootdir=/repo -p no:cacheprovider",
        "python -m coverage report --precision=2 > /out/coverage.txt",
    ]


def test_the_pinned_build_set_hashes_every_requirement():
    text = (
        Path(__file__).resolve().parent.parent / "requirements" / "build.txt"
    ).read_text()
    requirements = [line for line in text.splitlines() if line[:1].isalpha()]
    names = {line.split("==")[0] for line in requirements}
    assert {"build", "hatchling"} <= names
    for line in requirements:
        assert "==" in line and line.endswith("\\"), line


def test_the_test_and_build_image_is_pinned_by_digest():
    # One `override` definition: a later one, a target-specific one or Makefile.local cannot move
    # the build to another image than the suite's.
    image = definition("TAIL_IMAGE").split(" = ", 1)[1]
    assert re.fullmatch(r"python:3\.14-slim@sha256:[0-9a-f]{64}", image), image


def test_the_suite_holds_its_slot_in_the_recipe_shell_and_runs_capped():
    first = recipe("test")[0]
    assert "$(SKIP_NO_REGISTRY); $(guard_slot); D=" in first
    assert "docker run --rm $(guard_caps)" in first


def test_the_suite_names_a_kill_at_its_cap():
    assert "exit 137" in "\n".join(recipe("test"))


def test_the_gate_and_release_refuse_a_registry_their_legs_would_skip_on():
    line = next(
        line
        for line in MAKEFILE.splitlines()
        if line.startswith("$(if $(and $(filter check release,$(MAKECMDGOALS))")
    )
    assert "$(if $(strip $(LUX_REGISTRY)),,$(error REFUSING" in line
    assert "$(if $(filter command,$(origin LUX_REGISTRY)),$(error REFUSING" in line
    assert "$(if $(guard_dry),,1)" in line


def test_the_refusal_macros_read_the_flags_that_would_discard_a_red():
    text = definition("REFUSE_IGNORED")
    for flag in ("i", "t", "e"):
        assert (
            f"$(findstring {flag},$(filter-out -%,$(firstword $(MAKEFLAGS))))" in text
        )
    assert "$(error REFUSING" in text


def test_flags_hidden_from_makeflags_are_refused_before_makeflags_is_read():
    text = definition("REFUSE_IGNORED")
    hidden = "$(filter command override,$(origin MAKEFLAGS))"
    assert hidden in text
    assert "$(filter command,$(origin GNUMAKEFLAGS))" in text
    assert text.index(hidden) < text.index("$(firstword $(MAKEFLAGS))")


def test_release_asks_the_preflight_for_a_positive_answer_in_an_expansion():
    first = recipe("release")[0]
    assert first.startswith("+@$(if $(filter-out /bin/sh -c,$(SHELL) $(.SHELLFLAGS))")
    assert "$(if $(filter ok,$(shell /usr/bin/env -i " in first
    assert "PATH=/usr/bin:/bin" in first
    assert '/bin/sh scripts/release-preflight.sh "$$1"' in first
    assert "preflight /proc/$$PPID)" in first
    # Only a first argument of exactly -n is a dry run: an option's value could spell it elsewhere.
    assert 'sed -n 2p)" = -n ]; then echo ok;' in first
    assert first.endswith("true")
    # Each of these can be rewritten by target-specific text from --eval.
    for variable in ("MAKEFLAGS", "guard_dry", "REFUSE_"):
        assert f"$({variable}" not in first


def test_the_release_tags_the_commit_it_judged_from_what_head_holds():
    assert "RELEASE_VERSION := $(shell git show HEAD:VERSION 2>/dev/null)" in MAKEFILE
    text = "\n".join(recipe("release"))
    assert text.index("--no-print-directory check") < text.index("HEAD moved")
    # A signature would carry the signer's address past the tagger check.
    assert (
        'git tag --no-sign --cleanup=verbatim -a v$(RELEASE_VERSION) -m "v$(RELEASE_VERSION)" $(RELEASE_HEAD)'
        in text
    )
    # The tag by its full name: a branch of the same name would make the short one ambiguous.
    assert (
        "-c push.followTags=false push --atomic origin $(RELEASE_HEAD):refs/heads/main "
        "refs/tags/v$(RELEASE_VERSION) ||" in text
    )


def test_the_tag_is_read_back_before_anything_is_pushed():
    text = "\n".join(recipe("release"))
    check = '[ "$$(git rev-parse \'refs/tags/v$(RELEASE_VERSION)^{commit}\')" = "$(RELEASE_HEAD)" ]'
    assert text.index("git tag --no-sign") < text.index(check)
    assert text.index(check) < text.index("-c push.followTags=false push")


def test_the_gate_runs_in_a_fresh_clone_of_the_judged_commit():
    gate = next(
        line for line in recipe("release") if "scripts/release-clone.sh" in line
    )
    clone = gate.index('/bin/sh scripts/release-clone.sh $(RELEASE_HEAD) "$$D"')
    # The verdict is the shell's last word, and set -e stops a clone that failed from reaching it.
    assert "set -e; D=$$(mktemp -d)" in gate
    # The guards read these words as make's arguments, so a closing bracket here hollows their rules.
    assert gate.endswith('cd "$$D"; $(MAKE) --no-print-directory check')
    assert clone < gate.rindex("$(MAKE)")
    assert "PATH=/usr/bin:/bin" in gate[:clone]
    # Only a dry run judges where it stands, and it leaves before the clone.
    assert gate.startswith(
        "@case '$(filter-out -%,$(firstword $(MAKEFLAGS)))' in *n*) exec $(MAKE) --no-print-directory check;; esac;"
    )


def test_every_line_that_talks_to_github_or_tags_runs_under_the_allowance():
    assert definition("RELEASE_RUN") == (
        "override RELEASE_RUN = /bin/sh scripts/release-run.sh"
    )
    text = "\n".join(recipe("release"))
    assert "$(RELEASE_RUN) git tag --no-sign" in text
    # gh runs through scripts/release-gh.sh, which runs it under the same allowance.
    assert (
        definition("RELEASE_GH")
        == "override RELEASE_GH = /bin/sh scripts/release-gh.sh"
    )
    assert "gh release create" not in text
    # A helper in any config would be handed the token: the empty value clears them all first.
    assert definition("RELEASE_GIT") == (
        "override RELEASE_GIT = $(RELEASE_RUN) git --no-pager -c credential.helper= "
        "-c 'credential.helper=!gh auth git-credential'"
    )
    assert "$(RELEASE_GIT) fetch -q origin" in text
    assert "$(RELEASE_GIT) -c push.followTags=false push" in text
    assert text.count("$(RELEASE_GIT) ls-remote --tags origin refs/") == 2
    # A person pasting these gets the same environment.
    assert text.count("Check with: $(RELEASE_RUN) git ls-remote") == 2
    for bare in ("Check with: git ", 'FINISH="gh '):
        assert bare not in text


def test_the_artifacts_come_from_an_export_of_the_judged_commit():
    text = "\n".join(recipe("release"))
    assert '/bin/sh scripts/release-export.sh $(RELEASE_HEAD) "$$D"' in text
    assert "git archive" not in text
    assert '$(call BUILD_ARTIFACTS,"$$D")' in text
    assert "dist/brother_ql-$(RELEASE_VERSION).tar.gz" in text
    assert text.index("BUILD_ARTIFACTS") < text.index("git tag --no-sign")


def test_the_preflight_is_asked_again_before_the_tag():
    text = "\n".join(recipe("release"))
    again = 'scripts/release-preflight.sh /proc/$$PPID)" = ok ]'
    assert again in text
    assert text.index(again) < text.index("git tag --no-sign")


def test_the_release_object_needs_the_tag_on_this_repository():
    text = "\n".join(recipe("release"))
    assert (
        '$(RELEASE_GH) publish $(RELEASE_REPO) $(RELEASE_VERSION) "$$N" "$$U" ||'
        in text
    )
    script = (
        Path(__file__).resolve().parent.parent / "scripts" / "release-gh.sh"
    ).read_text()
    assert 'run gh release create "v$version" --repo "$repo" --verify-tag' in script


def test_a_failed_push_reads_origin_before_saying_what_happened():
    text = "\n".join(recipe("release"))
    read = "$(RELEASE_GIT) ls-remote --tags origin refs/tags/v$(RELEASE_VERSION)"
    assert text.index(read) < text.index("nothing was published")
    # A tag on origin is only ours if it names the judged commit.
    assert '[ "$$P" = "$(RELEASE_HEAD)" ]' in text


def test_gh_is_checked_before_the_gate_again_before_the_tag_and_at_the_upload():
    text = "\n".join(recipe("release"))
    gate = text.index("--no-print-directory check")
    assert text.index("command -v gh") < gate
    assert text.index("$(RELEASE_GH) ready") < gate
    # The gate takes minutes, so it is asked again before the tag.
    assert text.count("$(RELEASE_GH) ready") == 2
    assert text.rindex("$(RELEASE_GH) ready") < text.index("git tag --no-sign")
    # The command printed for a person to finish by hand goes through the same checks.
    assert (
        "FINISH=\"$(RELEASE_GH) publish $(RELEASE_REPO) $(RELEASE_VERSION) '$$N' '$$U'\""
        in text
    )


def test_what_is_uploaded_is_a_checked_private_copy_of_the_build():
    text = "\n".join(recipe("release"))
    # Replaced, not rewritten, since a release run as another user leaves the file its own.
    record = '( S=$(RELEASE_SUMS); rm -f "$$S"; cd dist && sha256sum brother_ql-$(RELEASE_VERSION)* >"$$S" )'
    assert record in text
    copy = text.index('cp dist/brother_ql-$(RELEASE_VERSION)* "$$U"/')
    check = text.index('cd "$$U" && sha256sum --check --quiet --strict "$$S"')
    assert text.index(record) < copy < check < text.index("git tag --no-sign")
    assert "U=$$(mktemp -d)" in text
    # The upload and the command printed for a person both take the checked copy, never dist/.
    assert 'publish $(RELEASE_REPO) $(RELEASE_VERSION) "$$N" "$$U" ||' in text
    assert "publish $(RELEASE_REPO) $(RELEASE_VERSION) '$$N' '$$U'\"" in text
    assert "dist/*" not in text
    # Every path that prints no way to finish removes them, and one that says to delete the tag says
    # to remove them too.
    assert (
        text.count('If not: git tag -d v$(RELEASE_VERSION); rm -rf \\"$$N\\" \\"$$U\\"')
        == 2
    )
    assert (
        'else rm -rf "$$N" "$$U"; echo "release: v$(RELEASE_VERSION) on origin names'
        in text
    )
    # From the tag on, the copy stays for the command that finishes the Release.
    assert text.index("trap - EXIT;") < text.index("git tag --no-sign")


def test_an_interrupt_stops_the_recipe_shell():
    text = "\n".join(recipe("release"))
    # A dropped session or a `timeout -s` must not leave a clone holding Makefile.local's registry host.
    signals = definition("RELEASE_SIGNALS").split(" = ")[1].split()
    for signal in ("INT", "TERM", "HUP", "QUIT", "USR1", "ALRM", "PIPE", "XCPU"):
        assert signal in signals
    assert 'trap \'rm -rf "$$N" "$$U"; exit 130\' $(RELEASE_SIGNALS)' in text
    assert text.count("trap 'rm -rf \"$$D\"; exit 130' $(RELEASE_SIGNALS)") == 2
    assert "EXIT INT TERM" not in text
    # From the tag on, the notes stay for the command that finishes the Release.
    assert text.index("trap - EXIT;") < text.index("git tag --no-sign")


def test_every_guard_target_run_alone_skips_without_a_registry():
    for target in (
        "lint",
        "mypy",
        "test",
        "arch",
        "audit",
        "format",
        "status",
        "honest",
        "guard-version-check",
        "onboard-check",
        "onboard-guards",
    ):
        assert "$(SKIP_NO_REGISTRY)" in "\n".join(recipe(target)), target


def test_an_interrupt_ends_the_guard_test_and_status_recipes():
    # A trap that only cleans up lets the shell run every later docker call after Ctrl-C.
    for target in ("onboard-guards", "test", "status"):
        text = "\n".join(recipe(target))
        assert "EXIT INT TERM" not in text, target
        assert "trap 'exit 130' INT TERM HUP;" in text, target


def test_the_other_tree_refusal_cannot_be_overridden_and_spares_this_tree():
    text = definition("REFUSE_OTHER_TREE")
    assert "$(filter command,$(origin CURDIR))" in text
    assert "$(call guard_same,$(CURDIR),$(GUARD_PWD))" in text
    assert "$(REFUSE_OTHER_TREE)" in recipe("status")[0]


def test_onboard_check_refuses_ignored_errors_and_runs_every_verdict():
    lines = recipe("onboard-check")
    assert lines[0] == "+@$(REFUSE_IGNORED)true"
    assert "$(MAKE) --no-print-directory onboard-guards || fail=1;" in lines[1]
    assert "$(MAKE) -s gitleaks >/dev/null 2>&1 || {" in lines[1]
    assert "$(GUARD_RUN)" not in lines[1]


def test_onboard_guards_judges_the_audit_exit_status_and_reports_it():
    text = "\n".join(recipe("onboard-guards"))
    assert "|| a=$$?" in text
    branch = text[text.index('[ "$$a" -le 1 ] || {') :]
    assert "fail=1;" in branch[: branch.index("}")]
    assert text.rstrip().endswith("exit $$fail")


def test_the_version_check_fails_when_it_cannot_pull_or_read_latest():
    text = "\n".join(recipe("guard-version-check"))
    assert "docker pull -q $$img:latest >/dev/null 2>&1 || {" in text
    assert "rc=1; continue; }" in text
    assert "|| true" not in text
    branch = text[text.index('if [ -z "$$latest" ]') :]
    assert "rc=1" in branch[: branch.index("elif")]


def test_the_commit_message_scan_is_phony():
    declared = [
        word
        for line in MAKEFILE.splitlines()
        if line.startswith(".PHONY:")
        for word in line.split()
    ]
    assert "gitleaks-commit-msg" in declared
