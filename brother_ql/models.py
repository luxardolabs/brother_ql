"""Printer model specifications and management.

This module loads printer model definitions from JSON configuration files
and provides a typed interface for accessing model capabilities and features.
Users can add custom models or positioning overrides via ~/.brother_ql/models.json.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import json
import logging
from dataclasses import dataclass
from pathlib import Path

from brother_ql.constants import DEFAULT_BYTES_PER_ROW

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PrinterModel:
    """Complete printer model specification."""

    name: str
    min_max_length_dots: tuple[int, int]
    bytes_per_row: int = DEFAULT_BYTES_PER_ROW
    additional_offset_r: int = 0

    # Feature flags
    has_cutting: bool = True
    has_mode_setting: bool = True
    has_expanded_mode: bool = True
    has_compression: bool = True
    has_two_color: bool = False
    has_600_dpi: bool = False

    # Positioning overrides (optional)
    positioning: dict[str, dict[str, int]] | None = None

    @property
    def identifier(self) -> str:
        """Get string identifier for compatibility."""
        return self.name

    @property
    def pixel_width(self) -> int:
        """Calculate pixel width from bytes per row."""
        return self.bytes_per_row * 8

    @property
    def is_two_color(self) -> bool:
        """Check if model supports red/black printing."""
        return self.has_two_color

    @property
    def is_wide_format(self) -> bool:
        """Check if this is a wide format model."""
        return self.bytes_per_row > DEFAULT_BYTES_PER_ROW


def _load_models_from_json() -> dict[str, PrinterModel]:
    """Load printer models from JSON config file."""
    models = {}

    # Find the config file
    config_paths = [
        Path(__file__).parent / "config" / "models.json",
        Path.home() / ".brother_ql" / "models.json",
        Path.home() / ".config" / "brother_ql" / "models.json",
        Path("/etc/brother_ql/models.json"),
    ]

    config_file = None
    for path in config_paths:
        if path.exists():
            config_file = path
            logger.info(f"Loading models from {path}")
            break

    if not config_file:
        raise FileNotFoundError(
            "No models.json found. Expected in: " + ", ".join(str(p) for p in config_paths)
        )

    with open(config_file) as f:
        data = json.load(f)

    for model_id, spec in data.items():
        try:
            models[model_id] = PrinterModel(
                name=spec["name"],
                min_max_length_dots=tuple(spec["min_max_length_dots"]),
                bytes_per_row=spec.get("bytes_per_row", DEFAULT_BYTES_PER_ROW),
                additional_offset_r=spec.get("additional_offset_r", 0),
                has_cutting=spec.get("has_cutting", True),
                has_mode_setting=spec.get("has_mode_setting", True),
                has_expanded_mode=spec.get("has_expanded_mode", True),
                has_compression=spec.get("has_compression", True),
                has_two_color=spec.get("has_two_color", False),
                has_600_dpi=spec.get("has_600_dpi", False),
                positioning=spec.get("positioning", None),
            )
        except Exception as e:
            logger.error(f"Failed to load model {model_id}: {e}")

    return models


# Load models on module import
PRINTER_MODELS = _load_models_from_json()


def get_model(identifier: str) -> PrinterModel | None:
    """Get a printer model by string identifier."""
    identifier = identifier.upper().replace("_", "-")
    return PRINTER_MODELS.get(identifier)


def get_two_color_models() -> list[PrinterModel]:
    """Get all models that support two-color printing."""
    return [m for m in PRINTER_MODELS.values() if m.has_two_color]


def get_models_with_compression() -> list[PrinterModel]:
    """Get all models that support compression."""
    return [m for m in PRINTER_MODELS.values() if m.has_compression]


def get_wide_format_models() -> list[PrinterModel]:
    """Get all wide format models."""
    return [m for m in PRINTER_MODELS.values() if m.is_wide_format]
