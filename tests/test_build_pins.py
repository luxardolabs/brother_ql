"""scripts/check-build-pins.sh, run for real on a stand-in make that prints a database.

The suite's image has no make, so a stand-in make, first on PATH, prints the database `make -qp`
would print, and each test changes one part of it. That make reports what it uses for each shape
(a later setting, a target- or pattern-specific one, a second rule) was checked against GNU make;
these tests hold the checker's reading of that database.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOAL = "__build_pins_no_such_goal__"
DIGEST = "9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f"
PIN = (
    "pip install -q --root-user-action=ignore --no-deps --require-hashes"
    " -r requirements/build.txt >/dev/null"
)
BUILD = (
    "docker run --rm --user $(REPO_UID):$(REPO_GID) -e HOME=/tmp -v $(1):/repo -w /repo"
    " $(TAIL_IMAGE) sh -c '$(PIN_BUILD_TOOLS) && python -m build --no-isolation --outdir dist'"
)


def override(name, value, line=1):
    return f"# 'override' directive (from 'Makefile', line {line})\n{name} = {value}\n"


def rule(target, recipe):
    # A .recipe file holds make's lines as the database prints them, each opening with a tab.
    tabbed = "".join(
        f"{line}\n" if line.startswith("\t") else f"\t{line}\n"
        for line in recipe.splitlines()
    )
    return (
        f"{target}:\n#  Phony target (prerequisite of .PHONY).\n"
        f"#  recipe to execute (from 'Makefile', line 9):\n{tabbed}\n"
    )


def database(**parts):
    """A database as make prints it, with any part replaced."""
    recipes = {
        name: (ROOT / "scripts" / "build-pins" / f"{name}.recipe").read_text()
        for name in ("build", "test")
    }
    default = {
        "image": override("TAIL_IMAGE", f"python:3.14-slim@sha256:{DIGEST}"),
        "pin": override("PIN_BUILD_TOOLS", PIN),
        "build_artifacts": override("BUILD_ARTIFACTS", BUILD),
        "checkout": override("CHECKOUT", "'$(subst ','\\'',$(CURDIR))'"),
        "legs": "# makefile (from 'Makefile', line 321)\n"
        "CHECK_LEGS = lint mypy test arch audit gitleaks build-pins\n",
        "extra": "",
        "build": rule("build", recipes["build"]),
        "test": rule("test", recipes["test"]),
        "release": rule("release", '@set -e; $(call BUILD_ARTIFACTS,"$$D"); git tag'),
    }
    default.update(parts)
    return "# GNU Make 4.4.1\n\n" + "\n".join(default.values())


def check(
    tmp_path, db, stderr=f"make: *** No rule to make target '{GOAL}'.  Stop.", rc=2
):
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    shutil.copytree(ROOT / "scripts" / "build-pins", repo / "scripts" / "build-pins")
    shutil.copy(ROOT / "scripts" / "check-build-pins.sh", repo / "scripts")
    (repo / "Makefile").write_text("")
    (tmp_path / "db.txt").write_text(db)
    (tmp_path / "err.txt").write_text(stderr + "\n" if stderr else "")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    make = bin_dir / "make"
    make.write_text(
        f'#!/bin/sh\ncat "{tmp_path}/db.txt"\ncat "{tmp_path}/err.txt" >&2\nexit {rc}\n'
    )
    make.chmod(0o755)
    env = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "MAKEFLAGS": "k"}
    result = subprocess.run(
        ["/bin/sh", "scripts/check-build-pins.sh"],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, result.stdout + result.stderr


def test_the_pinned_build_passes(tmp_path):
    rc, out = check(tmp_path, database())
    assert rc == 0, out
    assert "make builds and tests with the pinned tools and image" in out


def test_a_target_specific_image_fails(tmp_path):
    extra = "# 'override' directive (from 'Makefile', line 99)\nbuild: TAIL_IMAGE := python:3.13-slim\n"
    rc, out = check(tmp_path, database(extra=extra))
    assert rc == 1
    assert "TAIL_IMAGE has 2 settings, not one" in out


def test_a_pattern_specific_image_fails(tmp_path):
    extra = "# makefile (from 'Makefile', line 99)\n# TAIL_IMAGE := python:3.13-slim\n"
    rc, out = check(tmp_path, database(extra=extra))
    assert rc == 1
    assert "TAIL_IMAGE has 2 settings, not one" in out


def test_an_image_set_outside_the_makefile_or_without_override_fails(tmp_path):
    local = (
        "# makefile (from 'Makefile.local', line 3)\nTAIL_IMAGE = python:3.14-slim\n"
    )
    rc, out = check(tmp_path, database(image=local))
    assert rc == 1
    assert "TAIL_IMAGE is not the Makefile's own override setting" in out


def test_an_image_without_a_digest_fails(tmp_path):
    rc, out = check(
        tmp_path, database(image=override("TAIL_IMAGE", "python:3.14-slim"))
    )
    assert rc == 1
    assert "TAIL_IMAGE is not python:3.14-slim pinned by digest" in out


def test_an_unhashed_pin_fails(tmp_path):
    pin = override("PIN_BUILD_TOOLS", "pip install -q build hatchling")
    rc, out = check(tmp_path, database(pin=pin))
    assert rc == 1
    assert "PIN_BUILD_TOOLS is not the hash-checked install" in out


def test_a_defined_pin_fails(tmp_path):
    defined = "# 'override' directive (from 'Makefile', line 5)\ndefine PIN_BUILD_TOOLS\npip install build\nendef\n"
    rc, out = check(tmp_path, database(pin=defined))
    assert rc == 1
    assert "PIN_BUILD_TOOLS" in out


def test_an_isolated_build_fails(tmp_path):
    isolated = override("BUILD_ARTIFACTS", BUILD.replace(" --no-isolation", ""))
    rc, out = check(tmp_path, database(build_artifacts=isolated))
    assert rc == 1
    assert "BUILD_ARTIFACTS does not build with the pinned tools" in out


def test_a_suite_recipe_that_differs_fails_and_shows_the_difference(tmp_path):
    recipe = (ROOT / "scripts" / "build-pins" / "test.recipe").read_text()
    changed = recipe.replace("--mount type=tmpfs,destination=/repo/src ", "")
    assert changed != recipe
    rc, out = check(tmp_path, database(test=rule("test", changed)))
    assert rc == 1
    assert "the recipe make runs for test is not scripts/build-pins/test.recipe" in out
    assert "tmpfs" in out


def test_a_release_that_installs_its_own_build_tools_fails(tmp_path):
    release = rule("release", 'pip install -q build && $(call BUILD_ARTIFACTS,"$$D")')
    rc, out = check(tmp_path, database(release=release))
    assert rc == 1
    assert "the release recipe installs or builds outside BUILD_ARTIFACTS" in out


def test_a_gate_without_this_leg_fails(tmp_path):
    legs = "# makefile (from 'Makefile', line 321)\nCHECK_LEGS = lint mypy test arch audit gitleaks\n"
    rc, out = check(tmp_path, database(legs=legs))
    assert rc == 1
    assert "does not run build-pins" in out


def test_a_make_warning_or_error_fails(tmp_path):
    warning = "Makefile:9: warning: overriding recipe for target 'test'\n" + (
        f"make: *** No rule to make target '{GOAL}'.  Stop."
    )
    rc, out = check(tmp_path, database(), stderr=warning)
    assert rc == 1
    assert "make could not print its database" in out


def test_the_parent_makes_flags_do_not_reach_the_database(tmp_path):
    repo_bin = tmp_path / "bin"
    rc, out = check(tmp_path, database())
    assert rc == 0, out
    # The stand-in records nothing, so prove the script unsets them: a make that fails on MAKEFLAGS.
    (repo_bin / "make").write_text(
        f'#!/bin/sh\n[ -z "${{MAKEFLAGS+x}}" ] || exit 9\ncat "{tmp_path}/db.txt"\n'
        f'cat "{tmp_path}/err.txt" >&2\nexit 2\n'
    )
    rc, out = check_again(tmp_path)
    assert rc == 0, out


def check_again(tmp_path):
    env = {"PATH": f"{tmp_path / 'bin'}:{os.environ['PATH']}", "MAKEFLAGS": "k"}
    result = subprocess.run(
        ["/bin/sh", "scripts/check-build-pins.sh"],
        cwd=tmp_path / "repo",
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, result.stdout + result.stderr
