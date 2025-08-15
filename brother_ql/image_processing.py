"""Image processing utilities for label generation.

This module provides image manipulation functions including loading,
rotation, resizing, dithering, and color separation for red/black printing.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import logging
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageChops, ImageOps

logger = logging.getLogger(__name__)


def filtered_hsv(
    im: Image.Image,
    filter_h: Callable[[int], int],
    filter_s: Callable[[int], int],
    filter_v: Callable[[int], int],
    default_col: tuple[int, int, int] = (255, 255, 255),
) -> Image.Image:
    """Filter image by HSV values to extract specific colors."""
    hsv_im = im.convert("HSV")
    H, S, V = 0, 1, 2
    hsv = hsv_im.split()
    mask_h = hsv[H].point(filter_h)
    mask_s = hsv[S].point(filter_s)
    mask_v = hsv[V].point(filter_v)

    Mdat = []
    for h, s, v in zip(mask_h.getdata(), mask_s.getdata(), mask_v.getdata(), strict=False):
        Mdat.append(255 if (h and s and v) else 0)

    mask = Image.new("L", im.size)
    mask.putdata(Mdat)

    im_result = Image.new("RGB", im.size, default_col)
    im_result.paste(im, mask=mask)
    return im_result


def load_image(image: Image.Image | str | Path) -> Image.Image:
    """
    Load image from various sources.

    Args:
        image: PIL Image, filename string, or Path object

    Returns:
        PIL Image object

    Raises:
        ValueError: If image cannot be loaded
    """
    if isinstance(image, Image.Image):
        return image

    try:
        return Image.open(image)
    except Exception as e:
        raise ValueError(
            f"Cannot load image. Expected PIL Image, filename, or Path object. Got: {type(image)}"
        ) from e


def prepare_image_mode(im: Image.Image, red: bool = False) -> Image.Image:
    """
    Prepare image mode for processing.

    Args:
        im: Input image
        red: Whether red/black printing is enabled

    Returns:
        Image with appropriate mode
    """
    # Handle transparency
    if im.mode.endswith("A"):
        # Place on white background
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    # Handle palette images (GIF)
    elif im.mode == "P":
        im = im.convert("RGB" if red else "L")
    # Handle grayscale when printing red
    elif im.mode == "L" and red:
        im = im.convert("RGB")

    return im


def rotate_image(im: Image.Image, rotate: str | int, expected_size: tuple[int, int]) -> Image.Image:
    """
    Handle image rotation.

    Args:
        im: Input image
        rotate: 'auto' or rotation angle in degrees
        expected_size: Expected (width, height) for auto-rotation

    Returns:
        Rotated image
    """
    if rotate == "auto":
        # Auto-rotate if image dimensions are swapped
        if im.size[0] == expected_size[1] and im.size[1] == expected_size[0]:
            return im.rotate(90, expand=True)
    elif rotate != 0:
        return im.rotate(float(rotate), expand=True)

    return im


def process_monochrome(im: Image.Image, dither: bool, threshold: int) -> Image.Image:
    """
    Convert image to monochrome (black and white).

    Args:
        im: Input image
        dither: Whether to use dithering
        threshold: Threshold value (0-255) for B/W conversion

    Returns:
        Monochrome image
    """
    # Convert to grayscale
    if im.mode != "L":
        im = im.convert("L")

    # Invert (white background to black background for thermal printing)
    im = ImageOps.invert(im)

    # Convert to 1-bit
    if dither:
        im = im.convert("1", dither=Image.Dither.FLOYDSTEINBERG)
    else:
        im = im.point(lambda x: 0 if x < threshold else 255, mode="1")

    return im


def process_red_black(im: Image.Image, threshold: int) -> tuple[Image.Image, Image.Image]:
    """
    Process image for red/black printing.

    Args:
        im: Input RGB image
        threshold: Threshold value for black/white conversion

    Returns:
        Tuple of (black_image, red_image)
    """

    # Extract red channel
    def filter_h_red(h: int) -> int:
        return 255 if (h < 40 or h > 210) else 0

    def filter_s_red(s: int) -> int:
        return 255 if s > 100 else 0

    def filter_v_red(v: int) -> int:
        return 255 if v > 80 else 0

    red_im = filtered_hsv(im, filter_h_red, filter_s_red, filter_v_red)
    red_im = red_im.convert("L")
    red_im = ImageOps.invert(red_im)
    red_im = red_im.point(lambda x: 0 if x < threshold else 255, mode="1")

    # Extract black channel
    def filter_v_black(v: int) -> int:
        return 255 if v < 80 else 0

    black_im = filtered_hsv(im, lambda h: 255, lambda s: 255, filter_v_black)
    black_im = black_im.convert("L")
    black_im = ImageOps.invert(black_im)
    black_im = black_im.point(lambda x: 0 if x < threshold else 255, mode="1")

    # Remove red pixels from black channel
    black_im = ImageChops.subtract(black_im, red_im)

    return black_im, red_im


def resize_image(
    im: Image.Image, target_size: tuple[int, int], dpi_600: bool = False
) -> Image.Image:
    """
    Resize image to target size.

    Args:
        im: Input image
        target_size: Target (width, height)
        dpi_600: Whether to adjust for 600 DPI mode

    Returns:
        Resized image
    """
    if dpi_600:
        # For 600 DPI, we need to resize width to half
        target_width = target_size[0] * 2
    else:
        target_width = target_size[0]

    if im.size[0] != target_width:
        # Calculate proportional height
        scale = target_width / im.size[0]
        target_height = int(im.size[1] * scale)
        im = im.resize((target_width, target_height), Image.Resampling.LANCZOS)
        logger.info(f"Resized image to {target_width}x{target_height}")

    if dpi_600:
        # Resize back to normal width for 600 DPI
        im = im.resize((im.size[0] // 2, im.size[1]))

    return im
