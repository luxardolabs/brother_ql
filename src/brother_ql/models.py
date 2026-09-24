"""Printer model specifications and management.

The definitions bundled in ``config/models.json`` are the starting point. Callers
extend or override them explicitly::

    from brother_ql.models import load_models_from, register_model

    load_models_from("my_models.json")   # merged over the bundled set
    register_model(my_spec)              # or build one in code

Without writing code, point ``BROTHER_QL_MODELS`` at one or more JSON files
(``os.pathsep``-separated, applied left to right).

Definitions merge BY IDENTIFIER, which is what makes a positioning override a
two-line file: an entry for ``QL-810W`` naming only ``positioning`` keeps every
other field of the bundled model. Nothing is read from the home directory or
/etc, and nothing is read at import — the first lookup loads.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import json
import logging
import os
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

from brother_ql.constants import DEFAULT_BYTES_PER_ROW

logger = logging.getLogger(__name__)

#: Environment variable naming extra model JSON files, merged over the bundled set.
MODELS_ENV_VAR = "BROTHER_QL_MODELS"

_BUNDLED_MODELS = Path(__file__).parent / "config" / "models.json"

_FLAG_FIELDS = (
    "has_cutting",
    "has_mode_setting",
    "has_expanded_mode",
    "has_compression",
    "has_two_color",
    "has_600_dpi",
)


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


_models: dict[str, PrinterModel] | None = None


def _spec_from_json(
    model_id: str, raw: dict[str, Any], base: PrinterModel | None
) -> PrinterModel:
    """Convert one JSON entry to a PrinterModel, overlaying `base` when it exists.

    Only the keys present in `raw` are applied, so a positioning-only override
    keeps the bundled model's dimensions and capabilities.
    """
    fields: dict[str, Any] = {}
    if "name" in raw:
        fields["name"] = str(raw["name"])
    if "min_max_length_dots" in raw:
        low, high = raw["min_max_length_dots"]
        fields["min_max_length_dots"] = (int(low), int(high))
    if "bytes_per_row" in raw:
        fields["bytes_per_row"] = int(raw["bytes_per_row"])
    if "additional_offset_r" in raw:
        fields["additional_offset_r"] = int(raw["additional_offset_r"])
    for flag in _FLAG_FIELDS:
        if flag in raw:
            fields[flag] = bool(raw[flag])
    if "positioning" in raw:
        fields["positioning"] = raw["positioning"]

    if base is not None:
        return replace(base, **fields)

    return PrinterModel(
        name=fields["name"],
        min_max_length_dots=fields["min_max_length_dots"],
        bytes_per_row=fields.get("bytes_per_row", DEFAULT_BYTES_PER_ROW),
        additional_offset_r=fields.get("additional_offset_r", 0),
        has_cutting=fields.get("has_cutting", True),
        has_mode_setting=fields.get("has_mode_setting", True),
        has_expanded_mode=fields.get("has_expanded_mode", True),
        has_compression=fields.get("has_compression", True),
        has_two_color=fields.get("has_two_color", False),
        has_600_dpi=fields.get("has_600_dpi", False),
        positioning=fields.get("positioning"),
    )


def _merge_file(path: Path, into: dict[str, PrinterModel]) -> None:
    """Merge one JSON file of model definitions into `into`, keyed by identifier."""
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path} is not valid JSON") from exc

    for model_id, raw in data.items():
        try:
            into[model_id] = _spec_from_json(model_id, raw, into.get(model_id))
        except (AttributeError, KeyError, TypeError, ValueError) as exc:
            # Naming the file and the entry is the whole value here: the caller has
            # to know WHICH definition to fix, and a skipped entry would resurface
            # later as a misleading "Unknown printer model".
            raise ValueError(f"Malformed model entry {model_id!r} in {path}") from exc

    logger.debug("Loaded %d model definition(s) from %s", len(data), path)


def _env_paths() -> list[Path]:
    """The model files named by BROTHER_QL_MODELS, in the order given."""
    return [Path(p) for p in os.environ.get(MODELS_ENV_VAR, "").split(os.pathsep) if p]


def _registry() -> dict[str, PrinterModel]:
    """The live model set, loaded on first use from bundled + env-named files."""
    global _models
    if _models is None:
        models: dict[str, PrinterModel] = {}
        _merge_file(_BUNDLED_MODELS, models)
        for path in _env_paths():
            if not path.exists():
                raise FileNotFoundError(
                    f"{MODELS_ENV_VAR} names {path}, which is missing"
                )
            _merge_file(path, models)
        _models = models
    return _models


def load_models_from(path: str | Path) -> None:
    """Merge a JSON file of model definitions over the current set."""
    _merge_file(Path(path), _registry())


def register_model(spec: PrinterModel) -> None:
    """Add or replace a single model definition programmatically."""
    _registry()[spec.name] = spec


def reset_models() -> None:
    """Drop runtime additions; the next lookup reloads bundled + env-named files."""
    global _models
    _models = None


def all_models() -> dict[str, PrinterModel]:
    """Every known model by identifier, as a copy (add via register_model)."""
    return dict(_registry())


def get_model(identifier: str) -> PrinterModel | None:
    """Get a printer model by string identifier."""
    identifier = identifier.upper().replace("_", "-")
    return _registry().get(identifier)


def get_two_color_models() -> list[PrinterModel]:
    """Get all models that support two-color printing."""
    return [m for m in _registry().values() if m.has_two_color]


def get_models_with_compression() -> list[PrinterModel]:
    """Get all models that support compression."""
    return [m for m in _registry().values() if m.has_compression]


def get_wide_format_models() -> list[PrinterModel]:
    """Get all wide format models."""
    return [m for m in _registry().values() if m.is_wide_format]


def __getattr__(name: str) -> object:
    """Serve the legacy PRINTER_MODELS mapping without loading it at import."""
    if name == "PRINTER_MODELS":
        return all_models()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
