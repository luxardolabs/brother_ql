"""Test label positioning functionality.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import pytest
from PIL import Image

from brother_ql.label_positioning import (
    calculate_position,
    get_label_position,
    position_image_on_label,
    validate_image_dimensions,
)


def test_calculate_position_standard():
    """Test position calculation for standard width images."""
    # Standard width image
    position = calculate_position(
        image_width=202, device_width=720, standard_width=202, right_margin=42
    )

    # Should be positioned with right margin
    expected = 720 - 202 - 42
    assert position == expected


def test_calculate_position_wide():
    """Test position calculation for wider images."""
    # Image wider than standard
    position = calculate_position(
        image_width=300, device_width=720, standard_width=202, right_margin=42
    )

    # Should be centered on device
    expected = (720 // 2) - (300 // 2)
    assert position == expected


def test_calculate_position_with_offset():
    """Test position calculation with user offset."""
    # With positive offset
    position = calculate_position(
        image_width=202, device_width=720, standard_width=202, right_margin=42, offset_x=50
    )

    # The position is calculated then offset is added
    # Then it's clamped to valid range [0, device_width - image_width]
    base_position = 720 - 202 - 42  # 476
    expected = min(base_position + 50, 720 - 202)  # 526 clamped to 518
    assert position == 518  # Max valid position

    # With negative offset
    position = calculate_position(
        image_width=202, device_width=720, standard_width=202, right_margin=42, offset_x=-30
    )

    expected = 720 - 202 - 42 - 30
    assert position == expected


def test_calculate_position_bounds():
    """Test that position stays within bounds."""
    # Very large offset - should be clamped
    position = calculate_position(
        image_width=202, device_width=720, standard_width=202, right_margin=42, offset_x=1000
    )

    # Should not exceed device width minus image width
    max_position = 720 - 202
    assert position == max_position

    # Very negative offset - should be clamped to 0
    position = calculate_position(
        image_width=202, device_width=720, standard_width=202, right_margin=42, offset_x=-1000
    )

    assert position == 0


def test_get_label_position():
    """Test getting position overrides from model spec."""
    # With model and label that has override (QL-810W with 23x23)
    position = get_label_position("QL-810W", "23x23", 500)
    assert position == 450  # From JSON config

    # Without override - should return default
    position = get_label_position("QL-700", "62x29", 500)
    assert position == 500

    # No model specified - should return default
    position = get_label_position(None, None, 500)
    assert position == 500


def test_position_image_on_label():
    """Test positioning image on full-width canvas."""
    # Create test image
    img = Image.new("1", (202, 202), 0)

    # Position on label
    positioned = position_image_on_label(
        img, device_width=720, label_height=202, standard_width=202, right_margin=42
    )

    # Should be full device width
    assert positioned.size == (720, 202)

    # Test with offset
    positioned = position_image_on_label(
        img, device_width=720, label_height=202, standard_width=202, right_margin=42, offset_x=50
    )

    assert positioned.size == (720, 202)


def test_position_image_already_full_width():
    """Test that full-width images are returned as-is."""
    # Image already full device width
    img = Image.new("1", (720, 202), 0)

    positioned = position_image_on_label(
        img, device_width=720, label_height=202, standard_width=202, right_margin=42
    )

    # Should be returned unchanged
    assert positioned.size == (720, 202)
    assert positioned is img  # Same object


def test_validate_image_dimensions():
    """Test image dimension validation."""
    # Valid dimensions
    img = Image.new("RGB", (202, 202), "white")

    # Should not raise
    validate_image_dimensions(img, (202, 202), 720)

    # Wrong height - should raise
    img = Image.new("RGB", (202, 300), "white")
    with pytest.raises(ValueError, match="height"):
        validate_image_dimensions(img, (202, 202), 720)

    # Wrong width (strict mode) - should raise
    img = Image.new("RGB", (300, 202), "white")
    with pytest.raises(ValueError, match="width"):
        validate_image_dimensions(img, (202, 202), 720, allow_full_bleed=False)

    # Full bleed allowed - should not raise
    validate_image_dimensions(img, (202, 202), 720, allow_full_bleed=True)

    # Exceeds device width - should raise
    img = Image.new("RGB", (800, 202), "white")
    with pytest.raises(ValueError, match="exceeds device width"):
        validate_image_dimensions(img, (202, 202), 720)
