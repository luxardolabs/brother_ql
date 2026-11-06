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
    for target in ("audit-lock", "format", "test", "build"):
        text = "\n".join(recipe(target))
        assert '"$(CURDIR)"' not in text, target
        assert "$(CHECKOUT):/repo" in text, target


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


def test_release_takes_no_flags_and_no_command_line_variables():
    text = definition("REFUSE_ARGUMENTS")
    assert "$(if $(strip $(MAKEFLAGS)),$(error REFUSING" in text
    assert "$(foreach v,$(.VARIABLES),$(if $(filter command,$(origin $(v)))" in text
    # A caller's MAKEOVERRIDES hid --eval from a filtered reading of the flags.
    assert "$(MAKEOVERRIDES)" not in text


def test_release_refuses_how_it_runs_being_chosen_from_the_environment():
    text = definition("REFUSE_ARGUMENTS")
    assert "$(strip $(MAKEFILES))" in text
    start = text.index("$(foreach v,MAKE ")
    names = text[start + len("$(foreach v,") : text.index(",", start)].split()
    # The image the artifacts are built on, and where the guards that judge them come from.
    for name in ("MAKE", "SHELL", "LUX_REGISTRY", "LUXLINT_IMAGE", "TAIL_IMAGE"):
        assert name in names
    assert "$(filter environment%,$(origin $(v)))" in text


def test_release_runs_every_refusal_on_its_first_line():
    assert recipe("release")[0] == "+@$(REFUSE_IGNORED)$(REFUSE_ARGUMENTS)true"


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
    phony = next(line for line in MAKEFILE.splitlines() if line.startswith(".PHONY:"))
    assert "gitleaks-commit-msg" in phony.split()
