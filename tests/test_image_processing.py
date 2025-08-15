"""Test image processing functionality.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from PIL import Image

from brother_ql.image_processing import (
    load_image,
    prepare_image_mode,
    process_monochrome,
    process_red_black,
    rotate_image,
)


def test_process_monochrome():
    """Test monochrome processing."""
    # Test RGB to monochrome with threshold
    img = Image.new("RGB", (100, 100), (128, 128, 128))
    mono = process_monochrome(img, dither=False, threshold=50)

    assert mono.mode == "1"
    assert mono.size == (100, 100)

    # Test with dithering
    mono_dither = process_monochrome(img, dither=True, threshold=50)
    assert mono_dither.mode == "1"


def test_threshold_values():
    """Test different threshold values."""
    # Create grayscale gradient
    img = Image.new("L", (100, 100), 128)

    # Low threshold - more black pixels
    mono_low = process_monochrome(img, dither=False, threshold=30)

    # High threshold - more white pixels
    mono_high = process_monochrome(img, dither=False, threshold=90)

    # Both should be monochrome
    assert mono_low.mode == "1"
    assert mono_high.mode == "1"


def test_dithering():
    """Test Floyd-Steinberg dithering."""
    # Create grayscale image
    img = Image.new("L", (100, 100), 128)

    # Apply dithering
    dithered = process_monochrome(img, dither=True, threshold=50)

    assert dithered.mode == "1"
    assert dithered.size == (100, 100)


def test_rotate_image():
    """Test image rotation."""
    # Create test image
    img = Image.new("RGB", (100, 200), "white")
    expected_size = (100, 200)

    # Test 90 degree rotation
    rotated = rotate_image(img, 90, expected_size)
    assert rotated.size == (200, 100)  # Width and height swapped

    # Test 180 degree rotation
    rotated = rotate_image(img, 180, expected_size)
    assert rotated.size == (100, 200)  # Same size

    # Test 270 degree rotation
    rotated = rotate_image(img, 270, expected_size)
    assert rotated.size == (200, 100)  # Width and height swapped

    # Test 0 degree (no rotation)
    rotated = rotate_image(img, 0, expected_size)
    assert rotated.size == (100, 200)  # Same size


def test_rotate_auto():
    """Test automatic rotation detection."""
    # Portrait image for landscape label
    img = Image.new("RGB", (271, 696), "white")
    expected_size = (696, 271)

    # Auto should rotate to landscape
    rotated = rotate_image(img, "auto", expected_size)
    assert rotated.size == expected_size

    # Already landscape - no rotation needed
    img = Image.new("RGB", (696, 271), "white")
    rotated = rotate_image(img, "auto", expected_size)
    assert rotated.size == expected_size


def test_process_red_black():
    """Test red/black separation."""
    # Create image with red and black
    img = Image.new("RGB", (100, 100))

    # Process for red/black printing
    black_layer, red_layer = process_red_black(img, threshold=50)

    assert black_layer.mode == "1"
    assert red_layer.mode == "1"
    assert black_layer.size == (100, 100)
    assert red_layer.size == (100, 100)


def test_prepare_image_mode():
    """Test image mode preparation."""
    # Test RGB image
    img = Image.new("RGB", (100, 100))
    prepared = prepare_image_mode(img, red=False)
    assert prepared.mode in ["RGB", "L", "1"]

    # Test with red enabled
    prepared_red = prepare_image_mode(img, red=True)
    assert prepared_red.mode == "RGB"

    # Test monochrome image
    img_mono = Image.new("1", (100, 100))
    prepared = prepare_image_mode(img_mono, red=False)
    assert prepared.mode == "1"


def test_load_image():
    """Test image loading from file."""
    # Create a test image file
    import os
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        test_img = Image.new("RGB", (100, 100), "white")
        test_img.save(f.name)
        temp_path = f.name

    try:
        # Load from string path
        loaded = load_image(temp_path)
        assert isinstance(loaded, Image.Image)
        assert loaded.size == (100, 100)

        # Load from Path object
        from pathlib import Path

        loaded = load_image(Path(temp_path))
        assert isinstance(loaded, Image.Image)

        # Pass through Image object
        img = Image.new("RGB", (50, 50))
        loaded = load_image(img)
        assert loaded is img
    finally:
        os.unlink(temp_path)
