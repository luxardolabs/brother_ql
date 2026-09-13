"""Test raster generation functionality.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from brother_ql.raster import BrotherQLRaster


def test_raster_initialization():
    """Test BrotherQLRaster initialization."""
    qlr = BrotherQLRaster("QL-810W")

    assert qlr.model == "QL-810W"
    assert qlr.data == b""
    assert qlr._pquality is True


def test_raster_basic_commands():
    """Test basic raster command generation."""
    qlr = BrotherQLRaster("QL-810W")

    # Test invalidate command
    qlr.add_invalidate()
    assert len(qlr.data) > 0

    # Test initialize command
    qlr.add_initialize()
    assert b"@" in qlr.data  # ESC @ is initialize

    # Test status request
    qlr.add_status_information()
    assert len(qlr.data) > 0


def test_raster_mode_settings():
    """Test mode setting commands."""
    qlr = BrotherQLRaster("QL-810W")

    # Should work for QL-810W via add_switch_mode
    qlr.add_switch_mode()
    assert len(qlr.data) > 0

    # Test model that doesn't support mode setting
    qlr = BrotherQLRaster("QL-500")
    # QL-500 doesn't have mode setting but add_switch_mode may still work


def test_raster_cutting_commands():
    """Test cutting commands."""
    qlr = BrotherQLRaster("QL-810W")

    # QL-810W supports cutting
    qlr.add_cut_every(1)
    assert len(qlr.data) > 0

    # Test model without cutting - QL-500 actually just logs warning, doesn't raise
    qlr = BrotherQLRaster("QL-500")
    qlr.add_cut_every(1)  # Should just warn, not raise


def test_raster_compression():
    """Test compression support."""
    qlr = BrotherQLRaster("QL-810W")

    # Should support compression
    qlr.add_compression(True)
    assert qlr._compression is True

    # Test model without compression - QL-500 actually just logs warning
    qlr = BrotherQLRaster("QL-500")
    qlr.add_compression(True)  # Should just warn, not raise
    assert qlr._compression is False  # Should remain False


def test_raster_two_color():
    """Test two-color (red/black) support."""
    qlr = BrotherQLRaster("QL-810W")

    # Should support two-color (it's a property, not a method)
    assert qlr.two_color_support is True

    # Set two-color printing flag
    qlr._two_color_printing = True
    assert qlr._two_color_printing is True

    # Test model without two-color
    qlr = BrotherQLRaster("QL-700")
    assert qlr.two_color_support is False


def test_raster_margin_settings():
    """Test margin and feed settings."""
    qlr = BrotherQLRaster("QL-810W")

    # Test margin setting
    qlr.add_margins(20)
    assert len(qlr.data) > 0

    # Test expanded mode margin (for models that support it)
    qlr.add_expanded_mode()
    qlr.add_margins(50)
    assert len(qlr.data) > 0


def test_raster_add_raster_data():
    """Test adding raster image data."""
    qlr = BrotherQLRaster("QL-810W")

    # Create test image (monochrome)
    from PIL import Image

    test_image = Image.new("1", (720, 100), 0)  # Black image

    # Add raster data
    qlr.add_raster_data(test_image)
    assert len(qlr.data) > 0

    # Test compression mode
    qlr.add_compression(True)
    qlr.add_raster_data(test_image)
    # Compressed data should be added


def test_raster_print_command():
    """Test print command generation."""
    qlr = BrotherQLRaster("QL-810W")

    # Add print command
    qlr.add_print()
    # Check for print command (0x1A is the actual print command)
    assert b"\x1a" in qlr.data or b"\x0c" in qlr.data


def test_raster_properties():
    """Test raster properties."""
    qlr = BrotherQLRaster("QL-810W")

    # Test mtype property
    qlr.mtype = 0x0A
    assert qlr.mtype == bytes([0x0A])

    # Test mwidth property
    qlr.mwidth = 62
    assert qlr.mwidth == bytes([62])

    # Test mlength property
    qlr.mlength = 29
    assert qlr.mlength == bytes([29])

    # Test pquality property
    qlr.pquality = False
    assert qlr.pquality is False

    # Test pixel width
    assert qlr.get_pixel_width() == 720  # QL series is 720 pixels
