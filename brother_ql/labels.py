"""Label specifications and management.

This module loads label definitions from JSON configuration files and
provides a typed interface for accessing label properties. Users can
add custom labels by creating JSON files in ~/.brother_ql/labels.json.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import json
import logging
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

logger = logging.getLogger(__name__)


class LabelKind(Enum):
    """Type of label."""

    DIE_CUT = "die-cut"
    ENDLESS = "endless"
    ROUND_DIE_CUT = "round-die-cut"
    PTOUCH_ENDLESS = "ptouch-endless"


@dataclass(frozen=True)
class LabelSpec:
    """Complete specification for a label type."""

    identifier: str
    name: str
    width_mm: float
    height_mm: float | None
    kind: LabelKind
    printable_width: int
    printable_height: int | None
    total_width: int
    total_height: int | None
    right_margin_dots: int = 0
    feed_margin: int = 35
    restricted_to_models: list[str] | None = None

    @property
    def dots_printable(self) -> tuple[int, int]:
        """Legacy property for compatibility."""
        return (self.printable_width, self.printable_height or 0)

    @property
    def dots_total(self) -> tuple[int, int]:
        """Legacy property for compatibility."""
        return (self.total_width, self.total_height or 0)

    @property
    def tape_size(self) -> tuple[float, float | None]:
        """Get tape size in mm."""
        return (self.width_mm, self.height_mm)

    @property
    def is_endless(self) -> bool:
        """Check if this is an endless label."""
        return self.kind in (LabelKind.ENDLESS, LabelKind.PTOUCH_ENDLESS)


def _load_labels_from_json() -> dict[str, LabelSpec]:
    """Load label specifications from JSON config file."""
    labels = {}

    # Find the config file - check multiple locations
    config_paths = [
        Path(__file__).parent / "config" / "labels.json",
        Path.home() / ".brother_ql" / "labels.json",
        Path.home() / ".config" / "brother_ql" / "labels.json",
        Path("/etc/brother_ql/labels.json"),
    ]

    config_file = None
    for path in config_paths:
        if path.exists():
            config_file = path
            logger.info(f"Loading labels from {path}")
            break

    if not config_file:
        raise FileNotFoundError(
            "No labels.json found. Expected in: " + ", ".join(str(p) for p in config_paths)
        )

    with open(config_file) as f:
        data = json.load(f)

    for label_id, spec in data.items():
        try:
            # Parse label kind
            kind_str = spec.get("kind", "die-cut")
            kind_map = {
                "die-cut": LabelKind.DIE_CUT,
                "endless": LabelKind.ENDLESS,
                "round-die-cut": LabelKind.ROUND_DIE_CUT,
                "ptouch-endless": LabelKind.PTOUCH_ENDLESS,
            }
            kind = kind_map.get(kind_str, LabelKind.DIE_CUT)

            # Create LabelSpec
            labels[label_id] = LabelSpec(
                identifier=label_id,
                name=spec.get("name", label_id),
                width_mm=float(spec["width_mm"]),
                height_mm=float(spec["height_mm"]) if spec.get("height_mm") else None,
                kind=kind,
                printable_width=int(spec["printable_width"]),
                printable_height=(
                    int(spec["printable_height"]) if spec.get("printable_height") else None
                ),
                total_width=int(spec.get("total_width", spec["printable_width"])),
                total_height=int(spec["total_height"]) if spec.get("total_height") else None,
                right_margin_dots=int(spec.get("right_margin_dots", 0)),
                feed_margin=int(spec.get("feed_margin", 35)),
                restricted_to_models=spec.get("restricted_to_models"),
            )
        except Exception as e:
            logger.error(f"Failed to load label {label_id}: {e}")

    return labels


# Load labels on module import
LABEL_SPECS = _load_labels_from_json()


def get_label(identifier: str) -> LabelSpec | None:
    """Get label specification by identifier."""
    return LABEL_SPECS.get(identifier)


def get_labels_for_model(model_name: str) -> list[LabelSpec]:
    """Get all labels compatible with a specific model."""
    labels = []
    for label in LABEL_SPECS.values():
        if label.restricted_to_models:
            if model_name in label.restricted_to_models:
                labels.append(label)
        else:
            labels.append(label)
    return labels


def get_die_cut_labels() -> list[LabelSpec]:
    """Get all die-cut labels."""
    return [
        label
        for label in LABEL_SPECS.values()
        if label.kind in (LabelKind.DIE_CUT, LabelKind.ROUND_DIE_CUT)
    ]


def get_endless_labels() -> list[LabelSpec]:
    """Get all endless labels."""
    return [
        label
        for label in LABEL_SPECS.values()
        if label.kind in (LabelKind.ENDLESS, LabelKind.PTOUCH_ENDLESS)
    ]
