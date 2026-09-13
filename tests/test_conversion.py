"""Test conversion module functionality.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import pytest
from PIL import Image

from brother_ql import BrotherQLRaster, convert
from brother_ql.exceptions import BrotherQLUnsupportedCmd


def test_basic_conversion():
    """Test basic image to raster conversion."""
    # Create a simple test image
    img = Image.new("RGB", (696, 271), "white")

    # Create raster object
    qlr = BrotherQLRaster("QL-810W")

    # Convert to instructions
    instructions = convert(qlr, [img], "62x29")

    # Verify we got bytes back
    assert isinstance(instructions, bytes)
    assert len(instructions) > 0


def test_dithering_option():
    """Test Floyd-Steinberg dithering."""
    # Create grayscale image
    img = Image.new("L", (696, 271))

    qlr = BrotherQLRaster("QL-810W")

    # Convert with dithering
    instructions_dither = convert(qlr, [img], "62x29", dither=True)

    # Convert without dithering
    instructions_nodither = convert(qlr, [img], "62x29", dither=False)

    # Both should produce valid output
    assert len(instructions_dither) > 0
    assert len(instructions_nodither) > 0


def test_red_black_printing():
    """Test red/black conversion for compatible models."""
    img = Image.new("RGB", (696, 271), "white")

    # QL-810W supports red/black
    qlr = BrotherQLRaster("QL-810W")
    instructions = convert(qlr, [img], "62x29", red=True)
    assert len(instructions) > 0

    # QL-700 does not support red/black
    qlr = BrotherQLRaster("QL-700")
    with pytest.raises(BrotherQLUnsupportedCmd):
        convert(qlr, [img], "62x29", red=True)


def test_endless_label():
    """Test conversion for endless labels."""
    # Create variable height image matching the label's printable width
    # 62mm endless label has printable_width of 696 pixels
    img = Image.new("RGB", (696, 500), "white")

    qlr = BrotherQLRaster("QL-810W")

    # Convert for endless 62mm label
    instructions = convert(qlr, [img], "62")

    assert len(instructions) > 0


def test_rotation_options():
    """Test image rotation options."""
    img = Image.new("RGB", (271, 696), "white")  # Portrait orientation

    qlr = BrotherQLRaster("QL-810W")

    # Test auto rotation
    instructions = convert(qlr, [img], "62x29", rotate="auto")
    assert len(instructions) > 0

    # Test explicit 90 degree rotation
    instructions = convert(qlr, [img], "62x29", rotate=90)
    assert len(instructions) > 0


def test_offset_parameter():
    """Test horizontal offset positioning."""
    img = Image.new("RGB", (696, 271), "white")

    qlr = BrotherQLRaster("QL-810W")

    # Test with offset
    instructions = convert(qlr, [img], "62x29", offset_x=50)
    assert len(instructions) > 0

    # Test with negative offset
    instructions = convert(qlr, [img], "62x29", offset_x=-30)
    assert len(instructions) > 0


def test_full_bleed_printing():
    """Test full-bleed printing with wider images."""
    # Create image wider than standard printable area
    img = Image.new("RGB", (300, 202), "white")  # 23x23 full bleed

    qlr = BrotherQLRaster("QL-810W")

    # Should work with fullbleed label definition
    instructions = convert(qlr, [img], "23x23_fullbleed")
    assert len(instructions) > 0


def test_invalid_image_size():
    """Test that invalid image sizes raise errors."""
    # Wrong height for die-cut label
    img = Image.new("RGB", (696, 300), "white")  # Wrong height for 62x29

    qlr = BrotherQLRaster("QL-810W")

    with pytest.raises(ValueError):
        convert(qlr, [img], "62x29")


def test_threshold_parameter():
    """Test black/white threshold parameter."""
    # Create grayscale image with various shades
    img = Image.new("L", (696, 271))

    qlr = BrotherQLRaster("QL-810W")

    # Test different threshold values
    instructions_low = convert(qlr, [img], "62x29", threshold=30)
    instructions_high = convert(qlr, [img], "62x29", threshold=90)

    assert len(instructions_low) > 0
    assert len(instructions_high) > 0
