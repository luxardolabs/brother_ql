"""The hand-written Makefile recipes keep the gate honest.

The suite's image has no `make`, so these read the recipe text. They pin the shape of each
recipe, not make's behaviour.

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


def test_recipes_mount_the_checkout_quoted():
    for target in ("audit-lock", "format", "test", "build"):
        text = "\n".join(recipe(target))
        assert '"$(CURDIR)"' not in text, target
        assert "$(CHECKOUT):/repo" in text, target


def test_the_suite_holds_a_heavy_job_slot_and_runs_capped():
    text = "\n".join(recipe("test"))
    assert "$(guard_slot)" in text
    assert "docker run --rm $(guard_caps)" in text


def test_the_gate_refuses_an_empty_registry():
    assert "\ncheck: require-registry\n" in MAKEFILE
    text = "\n".join(recipe("require-registry"))
    assert '[ -n "$(LUX_REGISTRY)" ]' in text
    assert "exit 1" in text


def test_release_refuses_ignored_errors_before_it_does_anything():
    first = recipe("release")[0]
    assert first.startswith("+@")
    assert "$(error REFUSING: make -i" in first


def test_status_and_release_refuse_another_tree():
    assert "$(REFUSE_OTHER_TREE)" in recipe("status")[0]
    assert "$(REFUSE_OTHER_TREE)" in recipe("release")[0]


def test_onboard_check_runs_the_sub_make_on_a_line_of_its_own():
    lines = recipe("onboard-check")
    naming_make = [line for line in lines if "$(MAKE)" in line]
    assert naming_make
    assert not any("$(GUARD_RUN)" in line for line in naming_make)


def test_onboard_check_judges_the_audit_exit_status():
    text = "\n".join(recipe("onboard-check"))
    assert "|| a=$$?" in text
    assert '[ "$$a" -le 1 ]' in text


def test_the_version_check_fails_when_latest_cannot_be_read():
    text = "\n".join(recipe("guard-version-check"))
    assert 'if [ -z "$$latest" ]' in text
    assert '[ -n "$$latest" ] &&' not in text


def test_the_commit_message_scan_is_phony():
    phony = next(line for line in MAKEFILE.splitlines() if line.startswith(".PHONY:"))
    assert "gitleaks-commit-msg" in phony.split()
