"""The hand-written Makefile recipes keep the gate honest.

The suite's image has no `make`, so these read the Makefile's text and pin each recipe's shape and
each refusal's condition. A green run here says the text is in place, not that make behaves.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

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
    """The one line that defines a make variable."""
    return next(
        line for line in MAKEFILE.splitlines() if line.startswith(f"override {name} =")
    )


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
    assert (
        'git tag -a v$(RELEASE_VERSION) -m "v$(RELEASE_VERSION)" $(RELEASE_HEAD)'
        in text
    )
    assert (
        "git -c push.followTags=false push --atomic origin $(RELEASE_HEAD):refs/heads/main"
        in text
    )


def test_the_gate_runs_in_a_fresh_clone_of_the_judged_commit():
    gate = next(
        line for line in recipe("release") if "scripts/release-clone.sh" in line
    )
    clone = gate.index('/bin/sh scripts/release-clone.sh $(RELEASE_HEAD) "$$D"')
    # The verdict is the shell's last word, and set -e stops a clone that failed from reaching it.
    assert "set -e; D=$$(mktemp -d)" in gate
    assert gate.endswith('cd "$$D"; $(MAKE) --no-print-directory check')
    assert clone < gate.rindex("$(MAKE)")
    assert "PATH=/usr/bin:/bin" in gate[:clone]
    # Only a dry run judges where it stands, and it leaves before the clone.
    assert gate.startswith(
        "@case '$(filter-out -%,$(firstword $(MAKEFLAGS)))' in *n*) exec $(MAKE) --no-print-directory check;; esac;"
    )


def test_the_artifacts_come_from_an_export_of_the_judged_commit():
    text = "\n".join(recipe("release"))
    assert '/bin/sh scripts/release-export.sh $(RELEASE_HEAD) "$$D"' in text
    assert "git archive" not in text
    assert '$(call BUILD_ARTIFACTS,"$$D")' in text
    assert "dist/brother_ql-$(RELEASE_VERSION).tar.gz" in text
    assert text.index("BUILD_ARTIFACTS") < text.index("git tag -a")


def test_the_preflight_is_asked_again_before_the_tag():
    text = "\n".join(recipe("release"))
    again = 'scripts/release-preflight.sh /proc/$$PPID)" = ok ]'
    assert again in text
    assert text.index(again) < text.index("git tag -a")


def test_the_release_object_needs_the_tag_on_this_repository():
    text = "\n".join(recipe("release"))
    assert (
        "gh release create v$(RELEASE_VERSION) --repo $(RELEASE_REPO) --verify-tag"
        in text
    )


def test_a_failed_push_reads_origin_before_saying_what_happened():
    text = "\n".join(recipe("release"))
    read = "git ls-remote --tags origin refs/tags/v$(RELEASE_VERSION)"
    assert text.index(read) < text.index("nothing was published")
    # A tag on origin is only ours if it names the judged commit.
    assert '[ "$$P" = "$(RELEASE_HEAD)" ]' in text


def test_gh_is_checked_before_the_gate_so_a_release_cannot_stop_half_way():
    text = "\n".join(recipe("release"))
    gate = text.index("--no-print-directory check")
    assert text.index("command -v gh") < gate
    assert text.index("gh auth status") < gate


def test_an_interrupt_stops_the_recipe_shell():
    text = "\n".join(recipe("release"))
    assert "trap 'rm -f \"$$N\"; exit 130' INT TERM" in text
    assert "trap 'rm -rf \"$$D\"; exit 130' INT TERM" in text
    assert "EXIT INT TERM" not in text
    # From the tag on, the notes stay for the command that finishes the Release.
    assert text.index("trap - EXIT;") < text.index("git tag -a")


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
