"""Pytest configuration and fixtures.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import sys
from pathlib import Path

import pytest
from PIL import Image

SOURCE_TREE = Path(__file__).resolve().parent.parent / "src"


def pytest_sessionfinish(session):
    """Fail the run if any test imported code from the source tree instead of the wheel."""
    from_tree = sorted(
        name
        for name, module in list(sys.modules.items())
        if (path := getattr(module, "__file__", None))
        and Path(path).resolve().is_relative_to(SOURCE_TREE)
    )
    if from_tree:
        session.exitstatus = pytest.ExitCode.TESTS_FAILED
        sys.stderr.write(
            f"\nFAIL: modules imported from the source tree, not the installed wheel: {from_tree}\n"
        )


@pytest.fixture
def sample_image():
    """Create a sample test image."""
    return Image.new("RGB", (696, 271), "white")


@pytest.fixture
def sample_23x23_image():
    """Create a 23x23mm label test image."""
    return Image.new("RGB", (202, 202), "white")


@pytest.fixture
def sample_endless_image():
    """Create an endless label test image."""
    return Image.new("RGB", (696, 500), "white")
