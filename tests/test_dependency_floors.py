"""The declared dependency ranges admit no release the audit knows to be vulnerable.

`make audit` scans the newest release a range admits, so a floor below the newest fix is
invisible to it: a consumer can resolve that older release and still satisfy this package.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import re
import tomllib
from pathlib import Path

PYPROJECT = Path(__file__).resolve().parent.parent / "pyproject.toml"

# Pillow 13.0.0 carries the fixes for every advisory luxaudit reports against 12.x and below.
PILLOW_FIXED = (13, 0)


def _declared_floor(package):
    """The `>=` floor of a package in [project].dependencies, as a tuple of ints."""
    project = tomllib.loads(PYPROJECT.read_text())["project"]
    for requirement in project["dependencies"]:
        match = re.fullmatch(rf"{package}>=([0-9.]+)", requirement, re.IGNORECASE)
        if match:
            return tuple(int(part) for part in match.group(1).split("."))
    raise AssertionError(f"{package} has no >= floor in {project['dependencies']}")


def test_pillow_floor_excludes_the_vulnerable_releases():
    assert _declared_floor("Pillow") >= PILLOW_FIXED
