"""Pytest configuration and fixtures.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import pytest
from PIL import Image


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
