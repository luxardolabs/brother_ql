"""scripts/release-preflight.sh, run for real on a stand-in for make's /proc directory.

The suite's image has neither make nor git, so a stand-in git, first on PATH, answers as a clean
main would, and each test changes one answer.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "release-preflight.sh"


CLEAN_GIT = """#!/bin/sh
case "$*" in
"rev-parse --is-inside-work-tree") echo true ;;
"rev-parse --show-toplevel") pwd -P ;;
"symbolic-ref -q HEAD") echo refs/heads/main ;;
"for-each-ref refs/replace") ;;
"remote get-url origin" | "remote get-url --push origin") echo https://example.invalid/r.git ;;
"-c core.fsmonitor=false status --porcelain --untracked-files=all") ;;
"ls-tree -r HEAD") printf '100644 blob aaaa\\tVERSION\\n' ;;
"hash-object --no-filters VERSION") echo aaaa ;;
"show HEAD:VERSION") echo 1.0.0 ;;
"show HEAD:CHANGELOG.md") printf '## 1.0.0 - x\\n\\nnotes\\n' ;;
"rev-parse -q --verify refs/tags/v1.0.0") exit 1 ;;
*) echo "unexpected: git $*" >&2; exit 99 ;;
esac
"""


def preflight(
    tmp_path,
    argv,
    environ=b"PATH=/usr/bin\x00",
    local="LUX_REGISTRY ?= registry.invalid:5000\n",
    git_answers="",
):
    """Run the preflight on a fake /proc directory, and return (stdout word, stderr).

    `git_answers` holds `case` branches tried before those of a clean main.
    """
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "cmdline").write_bytes(b"".join(a.encode() + b"\x00" for a in argv))
    (proc / "environ").write_bytes(environ)
    if local is not None:
        (tmp_path / "Makefile.local").write_text(local)
    tools = tmp_path / "tools"
    tools.mkdir()
    git = tools / "git"
    git.write_text(CLEAN_GIT.replace('case "$*" in\n', f'case "$*" in\n{git_answers}'))
    git.chmod(0o755)
    done = subprocess.run(
        ["/bin/sh", str(SCRIPT), str(proc)],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        check=True,
        env={"PATH": f"{tools}:/usr/bin:/bin", "LC_ALL": "C"},
    )
    return done.stdout.strip(), done.stderr


def test_a_clean_main_with_plain_settings_passes(tmp_path):
    assert preflight(tmp_path, ["make", "release"]) == ("ok", "")


@pytest.mark.parametrize(
    ("answer", "reason"),
    [
        ('"rev-parse --is-inside-work-tree") exit 128 ;;', "working tree"),
        ('"rev-parse --show-toplevel") echo /elsewhere ;;', "core.worktree"),
        ('"symbolic-ref -q HEAD") echo refs/heads/other ;;', "main"),
        ('"symbolic-ref -q HEAD") echo heads/main ;;', "main"),
        ('"for-each-ref refs/replace") exit 128 ;;', "refs/replace"),
        ('"for-each-ref refs/replace") echo some-ref ;;', "refs/replace"),
        ('"remote get-url origin") exit 2 ;;', "origin"),
        (
            '"remote get-url --push origin") echo /sink.git ;;',
            "pushes",
        ),
        # A git that dies prints nothing, which must not read as a clean tree.
        (
            '"-c core.fsmonitor=false status --porcelain --untracked-files=all") '
            "exit 128 ;;",
            "git status failed",
        ),
        (
            '"-c core.fsmonitor=false status --porcelain --untracked-files=all") '
            "echo ' M x' ;;",
            "dirty",
        ),
        ('"ls-tree -r HEAD") exit 128 ;;', "tree at HEAD"),
        ('"ls-tree -r HEAD") ;;', "tree at HEAD"),
        ('"hash-object --no-filters VERSION") echo bbbb ;;', "VERSION on disk"),
        ('"hash-object --no-filters VERSION") exit 128 ;;', "VERSION on disk"),
        (
            "\"ls-tree -r HEAD\") printf '120000 blob aaaa\\tVERSION\\n' ;;",
            "VERSION on disk",
        ),
        (
            "\"ls-tree -r HEAD\") printf '160000 commit aaaa\\tVERSION\\n' ;;",
            "VERSION on disk",
        ),
        ('"show HEAD:VERSION") echo 1.0.0 main ;;', "X.Y.Z"),
        ('"show HEAD:VERSION") exit 128 ;;', "X.Y.Z"),
        ('"show HEAD:CHANGELOG.md") printf "## 1.0.0 - x\\n" ;;', "no notes"),
        ('"rev-parse -q --verify refs/tags/v1.0.0") echo abc ;;', "already exists"),
    ],
)
def test_a_repository_that_is_not_a_clean_main_is_refused(tmp_path, answer, reason):
    word, said = preflight(tmp_path, ["make", "release"], git_answers=answer + "\n")
    assert word == "refused"
    assert reason in said


@pytest.mark.parametrize(
    "local",
    [
        "LUX_REGISTRY = registry.invalid; exit 0;\n",
        'HEAVY_MEMORY = 6g"; exit 0; "\n',
        "HEAVY_CPUS = `true`\n",
        "HEAVY_CPUS = $(shell true)\n",
        "LUX_REGISTRY = a b\n",
        "LUX_REGISTRY = a \\\n",
        "CHECK_LEGS := lint\n",
        ".IGNORE:\n",
        "TAIL_IMAGE := attacker/python:evil\n",
    ],
)
def test_makefile_local_may_hold_plain_settings_only(tmp_path, local):
    word, said = preflight(tmp_path, ["make", "release"], local=local)
    assert word == "refused"
    assert "Makefile.local" in said


@pytest.mark.parametrize(
    "local",
    [
        "# a comment\n\nLUX_REGISTRY ?= docker.registry.invalid:5000\n",
        "LUX_REGISTRY := r\nHEAVY_SLOTS = 3\nHEAVY_SLOT_DIR ::= /var/tmp/s\nHEAVY_MEMORY=6g\n",
    ],
)
def test_plain_settings_pass(tmp_path, local):
    assert preflight(tmp_path, ["make", "release"], local=local)[0] == "ok"


def test_settings_from_make_s_include_search_are_refused(tmp_path):
    word, said = preflight(tmp_path, ["make", "release"], local=None)
    assert word == "refused"
    assert "no Makefile.local" in said


@pytest.mark.parametrize(
    "argv",
    [
        ["make", "release", "-i"],
        ["make", "-i", "release"],
        ["make", "release", "MAKEFLAGS=-i"],
        ["make", "release", "RELEASE_VERSION=0.9.9"],
        ["make", "release", "TAIL_IMAGE=attacker/python:evil"],
        ["make", "release", "--eval=.IGNORE: release"],
        ["make", "release", "--eval=release: MAKEFLAGS:="],
        ["make", "-f", "other.mk", "release"],
        ["make", "-C", ".", "release"],
        ["make", "-j2", "release"],
        ["make", "check", "release"],
        ["make"],
        # A newline-led argument is a variable to make, and must not read as nothing here.
        ["make", "release", "\nMAKE=true"],
        ["make", "release", "\nRELEASE_VERSION=0.9.9"],
        # The recipe passes a first argument of -n before asking this script; here it is refused.
        ["make", "-n", "release"],
        ["make", "release", "-n"],
    ],
)
def test_anything_but_the_bare_form_is_refused(tmp_path, argv):
    answer, reason = preflight(tmp_path, argv)
    assert answer == "refused"
    assert "takes no arguments" in reason


@pytest.mark.parametrize(
    "name",
    [
        "true",
        "evil/not-make",
        # A tab would reach $(MAKE) as a separator, carrying a flag or another tree.
        "make\t-ohonest",
        "make\t-Cgreen",
        "/usr/bin/make\t-i",
    ],
)
def test_a_name_that_would_change_what_the_gate_runs_is_refused(tmp_path, name):
    answer, reason = preflight(tmp_path, [name, "release"])
    assert answer == "refused"
    assert "name" in reason


@pytest.mark.parametrize(
    "variable",
    [
        b"MAKEFLAGS=-i",
        b"GNUMAKEFLAGS=--eval=x",
        b"MAKEFILES=/dev/null",
        b"MAKEOVERRIDES=X=1",
        b"MAKE=true",
        b"TAIL_IMAGE=attacker/python:evil",
        b"LUX_REGISTRY=attacker.invalid",
        b"LUXLINT_IMAGE=attacker/luxlint:1",
        b"GIT_DIR=/tmp/other",
        b"GIT_WORK_TREE=/tmp/other",
        b"GIT_CONFIG_COUNT=1",
        b"GH_REPO=attacker/other",
        b"DOCKER_HOST=tcp://attacker.invalid",
        b"LD_PRELOAD=/tmp/evil.so",
        b"BASH_FUNC_make%%=() { :; }",
        b"GIT_REPLACE_REF_BASE=refs/other/",
        b"GIT_EXEC_PATH=/tmp/other",
        b"GH_CONFIG_DIR=/tmp/other",
        b"GLOBIGNORE=dist/*.whl",
        b"SHELLOPTS=noexec",
        b"BASH_ENV=/tmp/other",
        b"ENV=/tmp/other",
    ],
)
def test_what_steers_the_release_from_the_environment_is_refused(tmp_path, variable):
    environ = b"PATH=/usr/bin\x00" + variable + b"\x00HOME=/root\x00"
    answer, reason = preflight(tmp_path, ["make", "release"], environ)
    assert answer == "refused"
    assert variable.split(b"=")[0].decode() in reason


@pytest.mark.parametrize(
    "variable",
    [
        b"GIT_EDITOR=true",
        b"TERM=xterm",
        b"NOTES=first line\nMAKE=true",
        b"BASH_FUNC_which%%=() { :; }",
        b"BASH_FUNC_module%%=() { :; }",
        b"BASH_FUNC_switchml%%=() { :; }",
    ],
)
def test_an_ordinary_environment_is_not_refused(tmp_path, variable):
    environ = b"PATH=/usr/bin\x00" + variable + b"\x00"
    assert preflight(tmp_path, ["make", "release"], environ) == ("ok", "")


def test_an_unreadable_proc_is_refused_not_passed(tmp_path):
    done = subprocess.run(
        ["/bin/sh", str(SCRIPT), str(tmp_path / "missing")],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        check=True,
    )
    assert done.stdout.strip() == "refused"
