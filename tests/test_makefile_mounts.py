"""Every Makefile line that runs a container mounts this checkout, not the caller's directory.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import re
from pathlib import Path

MAKEFILE = Path(__file__).resolve().parent.parent / "Makefile"

# `$(PWD)` / `${PWD}` is the caller's shell directory, so under `make -C <repo>` a mount
# built from it runs another tree. `$(CURDIR)` is the directory make runs in (the repo,
# under a plain `make` or `make -C <repo>`), which is what every mount uses.
CALLER_DIR = re.compile(r"\$[({]PWD[)}]")


def _logical_lines(text):
    """Makefile lines with backslash continuations joined, comments dropped."""
    joined = re.sub(r"\\\n", " ", text)
    return [line for line in joined.splitlines() if not line.lstrip().startswith("#")]


def test_no_line_mounts_the_callers_directory():
    offenders = [
        line.strip()
        for line in _logical_lines(MAKEFILE.read_text())
        if CALLER_DIR.search(line)
    ]
    assert offenders == []


def test_the_check_catches_each_spelling_of_the_callers_directory():
    for line in (
        "\tdocker run -v $(PWD):/repo img",
        '\tdocker run -v "${PWD}":/repo img',
        "\tdocker run --mount type=bind,src=$(PWD),dst=/repo img",
        "GUARD_RUN = docker run --rm -v $(PWD):/repo",
        "\tdocker run --rm \\\n    -v$(PWD):/repo img",
    ):
        assert any(CALLER_DIR.search(logical) for logical in _logical_lines(line)), line
