"""Label positioning and alignment functions.

This module handles the positioning of label images within the printer's
raster buffer, including support for custom offsets and model-specific
positioning overrides loaded from JSON configuration.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from PIL import Image

from brother_ql.models import get_model


def get_label_position(model: str | None, label_id: str | None, default: int) -> int:
    """Get label position override from model spec if one exists."""
    if model and label_id:
        model_spec = get_model(model)
        if model_spec and model_spec.positioning and label_id in model_spec.positioning:
            return model_spec.positioning[label_id].get("standard_position", default)
    return default


def position_image_on_label(
    im: Image.Image,
    device_width: int,
    label_height: int,
    standard_width: int,
    right_margin: int,
    model: str | None = None,
    label_id: str | None = None,
    offset_x: int = 0,
) -> Image.Image:
    """
    Position image on the label canvas.

    Args:
        im: Input image
        device_width: Device pixel width (e.g., 720 for QL series)
        label_height: Label height in pixels
        standard_width: Standard printable width for this label
        right_margin: Right margin in pixels
        model: Printer model
        label_id: Label identifier
        offset_x: User-specified horizontal offset

    Returns:
        Positioned image on full-width canvas
    """
    # If image is already full device width, return as-is
    if im.size[0] == device_width:
        return im

    # Create full-width canvas
    if im.mode == "1":
        # For monochrome, use white background (0)
        new_im = Image.new("1", (device_width, label_height), 0)
    elif im.mode == "L":
        # For grayscale, use white background (255)
        new_im = Image.new("L", (device_width, label_height), 255)
    else:
        # For color, use white background
        new_im = Image.new(im.mode, (device_width, label_height), (255, 255, 255))

    # Calculate position
    x_position = calculate_position(
        im.size[0], device_width, standard_width, right_margin, model, label_id, offset_x
    )

    # Paste image at calculated position
    new_im.paste(im, (x_position, 0))

    return new_im


def calculate_position(
    image_width: int,
    device_width: int,
    standard_width: int,
    right_margin: int,
    model: str | None = None,
    label_id: str | None = None,
    offset_x: int = 0,
) -> int:
    """
    Calculate X position for image placement.

    Args:
        image_width: Width of the image to position
        device_width: Device pixel width
        standard_width: Standard printable width for this label
        right_margin: Right margin in pixels
        model: Printer model
        label_id: Label identifier
        offset_x: User-specified horizontal offset

    Returns:
        X position for image placement
    """
    # Determine base position
    if image_width > standard_width:
        # Wider than standard - center on device
        # JSON config can override this with positioning data
        default_center = device_width // 2
        x_position = default_center - (image_width // 2)

        # Check for model-specific position override from JSON
        x_position = get_label_position(model, label_id, x_position)
    else:
        # Standard width - use normal positioning
        default_position = device_width - image_width - right_margin

        # Check for model-specific overrides from JSON
        x_position = get_label_position(model, label_id, default_position)

    # Apply user offset
    x_position += offset_x

    # Ensure position stays within bounds
    x_position = max(0, min(x_position, device_width - image_width))

    return x_position


def validate_image_dimensions(
    im: Image.Image,
    expected_size: tuple[int, int],
    device_width: int,
    allow_full_bleed: bool = True,
) -> None:
    """
    Validate image dimensions against label requirements.

    Args:
        im: Input image
        expected_size: Expected (width, height)
        device_width: Maximum device width
        allow_full_bleed: Whether to allow wider images for full-bleed printing

    Raises:
        ValueError: If dimensions are invalid
    """
    # Height must match exactly
    if im.size[1] != expected_size[1]:
        raise ValueError(f"Image height {im.size[1]} doesn't match label height {expected_size[1]}")

    # Width validation
    if allow_full_bleed:
        # Allow any width up to device maximum
        if im.size[0] > device_width:
            raise ValueError(f"Image width {im.size[0]} exceeds device width {device_width}")
    else:
        # Strict width matching
        if im.size[0] != expected_size[0]:
            raise ValueError(
                f"Image width {im.size[0]} doesn't match expected width {expected_size[0]}"
            )
