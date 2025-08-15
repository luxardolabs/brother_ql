"""Image to raster instruction conversion.

This module provides the main convert() function that transforms images
into Brother QL printer instructions. It handles all aspects of the
conversion process including image loading, processing, positioning,
and raster generation.

Example:
    Basic label printing::

        from brother_ql import BrotherQLRaster, convert
        from PIL import Image

        img = Image.new('RGB', (202, 202), 'white')
        qlr = BrotherQLRaster('QL-810W')
        instructions = convert(qlr, [img], '23x23')

        with open('/dev/usb/lp0', 'wb') as printer:
            printer.write(instructions)

    Photo printing with dithering::

        photo = Image.open('photo.jpg')
        instructions = convert(qlr, [photo], '62x100', dither=True)

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import logging
from pathlib import Path
from typing import Any

from PIL import Image

from brother_ql.constants import DEFAULT_THRESHOLD_PERCENT
from brother_ql.enums import MediaType
from brother_ql.exceptions import BrotherQLUnsupportedCmd
from brother_ql.image_processing import (
    load_image,
    prepare_image_mode,
    process_monochrome,
    process_red_black,
    resize_image,
    rotate_image,
)
from brother_ql.label_positioning import (
    position_image_on_label,
    validate_image_dimensions,
)
from brother_ql.labels import LabelKind, get_label
from brother_ql.models import get_model
from brother_ql.raster import BrotherQLRaster

logger = logging.getLogger(__name__)


def convert(
    qlr: BrotherQLRaster, images: list[Image.Image | str | Path], label: str, **kwargs: Any
) -> bytes:
    """
    Convert images to Brother QL raster instructions.

    This is the main entry point for image conversion. It orchestrates
    the entire process of loading, processing, positioning, and converting
    images to printer instructions.

    Args:
        qlr: BrotherQLRaster instance configured for target printer
        images: List of images to print (PIL Images, filenames, or Paths)
        label: Label identifier (e.g., '23x23', '62')
        **kwargs: Additional options

    Keyword Args:
        cut (bool): Enable cutting after printing (default: True)
        dither (bool): Use dithering for grayscale (default: False)
        compress (bool): Enable compression if supported (default: False)
        red (bool): Enable red/black printing (default: False)
        rotate (str|int): Rotation angle or 'auto' (default: 'auto')
        dpi_600 (bool): Use 600 DPI mode if supported (default: False)
        hq (bool): High quality printing (default: True)
        threshold (float): B/W threshold percentage (default: 70)
        offset_x (int): Horizontal offset in pixels (default: 0)

    Returns:
        Bytes containing raster instructions ready to send to printer

    Raises:
        ValueError: If label or image specifications are invalid
        BrotherQLUnsupportedCmd: If feature not supported by printer model
    """
    # Parse options
    options = _parse_options(kwargs)

    # Get label and model specifications
    label_spec = get_label(label)
    if not label_spec:
        raise ValueError(f"Unknown label identifier: {label}")

    model_spec = get_model(qlr.model)
    if not model_spec:
        raise ValueError(f"Unknown printer model: {qlr.model}")

    # Validate compatibility
    _validate_compatibility(label_spec, model_spec, options)

    # Initialize printer
    _initialize_printer(qlr)

    # Process each image
    for image_source in images:
        # Load and prepare image
        im = load_image(image_source)
        im = prepare_image_mode(im, options["red"])

        # Process based on label type
        if label_spec.is_endless:
            im = _process_endless(im, label_spec, model_spec, options)
        else:
            im = _process_die_cut(im, label_spec, model_spec, options)

        # Convert to monochrome or red/black
        if options["red"]:
            black_im, red_im = process_red_black(im, options["threshold"])
            _configure_and_print(qlr, label_spec, black_im, red_im, options)
        else:
            im = process_monochrome(im, options["dither"], options["threshold"])
            _configure_and_print(qlr, label_spec, im, None, options)

    return qlr.data


def _parse_options(kwargs: dict[str, Any]) -> dict[str, Any]:
    """Parse and validate conversion options."""
    options = {
        "cut": kwargs.get("cut", True),
        "dither": kwargs.get("dither", False),
        "compress": kwargs.get("compress", False),
        "red": kwargs.get("red", False),
        "rotate": kwargs.get("rotate", "auto"),
        "dpi_600": kwargs.get("dpi_600", False),
        "hq": kwargs.get("hq", True),
        "threshold": kwargs.get("threshold", DEFAULT_THRESHOLD_PERCENT),
        "offset_x": kwargs.get("offset_x", 0),
    }

    # Convert threshold from percentage to 0-255
    threshold_pct = 100.0 - options["threshold"]
    options["threshold"] = min(255, max(0, int(threshold_pct / 100.0 * 255)))

    # Validate rotate
    if options["rotate"] != "auto":
        options["rotate"] = int(options["rotate"])
        if options["rotate"] not in (0, 90, 180, 270):
            raise ValueError(f"Invalid rotation: {options['rotate']}")

    return options


def _validate_compatibility(label_spec: Any, model_spec: Any, options: dict[str, Any]) -> None:
    """Validate that requested features are compatible."""
    # Check label restrictions
    if label_spec.restricted_to_models:
        if model_spec.identifier not in label_spec.restricted_to_models:
            raise ValueError(
                f"Label {label_spec.identifier} not compatible with {model_spec.identifier}"
            )

    # Check two-color support
    if options["red"] and not model_spec.has_two_color:
        raise BrotherQLUnsupportedCmd(
            f"Red/black printing not supported on {model_spec.identifier}"
        )

    # Check compression support
    if options["compress"] and not model_spec.has_compression:
        logger.warning(f"Compression not supported on {model_spec.identifier}")
        options["compress"] = False


def _initialize_printer(qlr: BrotherQLRaster) -> None:
    """Initialize printer for printing."""
    try:
        qlr.add_switch_mode()
    except BrotherQLUnsupportedCmd:
        pass

    qlr.add_invalidate()
    qlr.add_initialize()

    try:
        qlr.add_switch_mode()
    except BrotherQLUnsupportedCmd:
        pass


def _process_endless(
    im: Image.Image, label_spec: Any, model_spec: Any, options: dict[str, Any]
) -> Image.Image:
    """Process image for endless label."""
    # Rotate if needed
    if options["rotate"] != "auto" and options["rotate"] != 0:
        im = im.rotate(float(options["rotate"]), expand=True)

    # Resize to label width
    if options["dpi_600"]:
        target_width = label_spec.printable_width * 2
    else:
        target_width = label_spec.printable_width

    im = resize_image(im, (target_width, im.size[1]), options["dpi_600"])

    # Position on device width if needed
    if im.size[0] < model_spec.pixel_width:
        im = position_image_on_label(
            im,
            model_spec.pixel_width,
            im.size[1],
            label_spec.printable_width,
            label_spec.right_margin_dots,
            model_spec.identifier,
            label_spec.identifier,
            options["offset_x"],
        )

    return im


def _process_die_cut(
    im: Image.Image, label_spec: Any, model_spec: Any, options: dict[str, Any]
) -> Image.Image:
    """Process image for die-cut label."""
    # Expected size
    expected_size = (label_spec.printable_width, label_spec.printable_height)

    # Handle rotation
    im = rotate_image(im, options["rotate"], expected_size)

    # Validate dimensions (allow full-bleed)
    validate_image_dimensions(im, expected_size, model_spec.pixel_width, allow_full_bleed=True)

    # Handle 600 DPI
    if options["dpi_600"]:
        im = im.resize((im.size[0] // 2, im.size[1]))

    # Position on label
    im = position_image_on_label(
        im,
        model_spec.pixel_width,
        expected_size[1],
        label_spec.printable_width,
        label_spec.right_margin_dots + model_spec.additional_offset_r,
        model_spec.identifier,
        label_spec.identifier,
        options["offset_x"],
    )

    return im


def _configure_and_print(
    qlr: BrotherQLRaster,
    label_spec: Any,
    black_im: Image.Image,
    red_im: Image.Image | None,
    options: dict[str, Any],
) -> None:
    """Configure printer settings and add raster data."""
    # Status information
    qlr.add_status_information()

    # Set media type
    if label_spec.kind == LabelKind.DIE_CUT:
        qlr.mtype = MediaType.DIE_CUT_LABEL
    elif label_spec.kind == LabelKind.ROUND_DIE_CUT:
        qlr.mtype = MediaType.DIE_CUT_LABEL
    elif label_spec.kind == LabelKind.ENDLESS:
        qlr.mtype = MediaType.ENDLESS_LABEL
    elif label_spec.kind == LabelKind.PTOUCH_ENDLESS:
        qlr.mtype = MediaType.PTOUCH_ENDLESS

    # Set media dimensions (convert to int)
    qlr.mwidth = int(label_spec.width_mm)
    qlr.mlength = int(label_spec.height_mm or 0)

    # Print quality
    qlr.pquality = bool(options["hq"])
    qlr.add_media_and_quality(black_im.size[1])

    # Cutting configuration
    if options["cut"]:
        try:
            qlr.add_autocut(True)
            qlr.add_cut_every(1)
        except BrotherQLUnsupportedCmd:
            pass

    # Expanded mode settings
    try:
        qlr.dpi_600 = options["dpi_600"]
        qlr.cut_at_end = options["cut"]
        qlr.two_color_printing = bool(red_im)
        qlr.add_expanded_mode()
    except BrotherQLUnsupportedCmd:
        pass

    # Margins
    qlr.add_margins(label_spec.feed_margin)

    # Compression
    if options["compress"]:
        try:
            qlr.add_compression(True)
        except BrotherQLUnsupportedCmd:
            pass

    # Add raster data
    if red_im:
        qlr.add_raster_data(black_im, red_im)
    else:
        qlr.add_raster_data(black_im)

    # Print command
    qlr.add_print()
