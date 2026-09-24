"""Label specifications and management.

The definitions bundled in ``config/labels.json`` are the starting point. Callers
extend or override them explicitly::

    from brother_ql.labels import load_labels_from, register_label

    load_labels_from("my_labels.json")   # merged over the bundled set
    register_label(my_spec)              # or build one in code

Without writing code, point ``BROTHER_QL_LABELS`` at one or more JSON files
(``os.pathsep``-separated, applied left to right).

Definitions merge BY IDENTIFIER: an entry for ``62x29`` changes only the fields it
names and leaves the rest of the bundled entry intact, while identifiers nobody
mentions stay available. Nothing is read from the home directory or /etc, and
nothing is read at import — the first lookup loads.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import json
import logging
import os
from dataclasses import dataclass, replace
from enum import Enum
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

#: Environment variable naming extra label JSON files, merged over the bundled set.
LABELS_ENV_VAR = "BROTHER_QL_LABELS"

_BUNDLED_LABELS = Path(__file__).parent / "config" / "labels.json"


class LabelKind(Enum):
    """Type of label."""

    DIE_CUT = "die-cut"
    ENDLESS = "endless"
    ROUND_DIE_CUT = "round-die-cut"
    PTOUCH_ENDLESS = "ptouch-endless"


_KIND_BY_NAME = {kind.value: kind for kind in LabelKind}


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


_labels: dict[str, LabelSpec] | None = None


def _spec_from_json(
    label_id: str, raw: dict[str, Any], base: LabelSpec | None
) -> LabelSpec:
    """Convert one JSON entry to a LabelSpec, overlaying `base` when it exists.

    Only the keys present in `raw` are applied, so an override can name a single
    field. Without a `base` the entry is new and must carry the fields that have
    no sensible default.
    """
    fields: dict[str, Any] = {}
    if "name" in raw:
        fields["name"] = str(raw["name"])
    if "width_mm" in raw:
        fields["width_mm"] = float(raw["width_mm"])
    if "height_mm" in raw:
        fields["height_mm"] = float(raw["height_mm"]) if raw["height_mm"] else None
    if "kind" in raw:
        fields["kind"] = _KIND_BY_NAME.get(raw["kind"], LabelKind.DIE_CUT)
    if "printable_width" in raw:
        fields["printable_width"] = int(raw["printable_width"])
    if "printable_height" in raw:
        fields["printable_height"] = (
            int(raw["printable_height"]) if raw["printable_height"] else None
        )
    if "total_width" in raw:
        fields["total_width"] = int(raw["total_width"])
    if "total_height" in raw:
        fields["total_height"] = (
            int(raw["total_height"]) if raw["total_height"] else None
        )
    if "right_margin_dots" in raw:
        fields["right_margin_dots"] = int(raw["right_margin_dots"])
    if "feed_margin" in raw:
        fields["feed_margin"] = int(raw["feed_margin"])
    if "restricted_to_models" in raw:
        fields["restricted_to_models"] = raw["restricted_to_models"]

    if base is not None:
        return replace(base, **fields)

    return LabelSpec(
        identifier=label_id,
        name=fields.get("name", label_id),
        width_mm=fields["width_mm"],
        height_mm=fields.get("height_mm"),
        kind=fields.get("kind", LabelKind.DIE_CUT),
        printable_width=fields["printable_width"],
        printable_height=fields.get("printable_height"),
        total_width=fields.get("total_width", fields["printable_width"]),
        total_height=fields.get("total_height"),
        right_margin_dots=fields.get("right_margin_dots", 0),
        feed_margin=fields.get("feed_margin", 35),
        restricted_to_models=fields.get("restricted_to_models"),
    )


def _merge_file(path: Path, into: dict[str, LabelSpec]) -> None:
    """Merge one JSON file of label definitions into `into`, keyed by identifier."""
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path} is not valid JSON") from exc

    for label_id, raw in data.items():
        try:
            into[label_id] = _spec_from_json(label_id, raw, into.get(label_id))
        except (AttributeError, KeyError, TypeError, ValueError) as exc:
            # Naming the file and the entry is the whole value here: the caller has
            # to know WHICH definition to fix, and a skipped entry would resurface
            # later as a misleading "Unknown label identifier".
            raise ValueError(f"Malformed label entry {label_id!r} in {path}") from exc

    logger.debug("Loaded %d label definition(s) from %s", len(data), path)


def _env_paths() -> list[Path]:
    """The label files named by BROTHER_QL_LABELS, in the order given."""
    return [Path(p) for p in os.environ.get(LABELS_ENV_VAR, "").split(os.pathsep) if p]


def _registry() -> dict[str, LabelSpec]:
    """The live label set, loaded on first use from bundled + env-named files."""
    global _labels
    if _labels is None:
        labels: dict[str, LabelSpec] = {}
        _merge_file(_BUNDLED_LABELS, labels)
        for path in _env_paths():
            if not path.exists():
                raise FileNotFoundError(
                    f"{LABELS_ENV_VAR} names {path}, which is missing"
                )
            _merge_file(path, labels)
        _labels = labels
    return _labels


def load_labels_from(path: str | Path) -> None:
    """Merge a JSON file of label definitions over the current set."""
    _merge_file(Path(path), _registry())


def register_label(spec: LabelSpec) -> None:
    """Add or replace a single label definition programmatically."""
    _registry()[spec.identifier] = spec


def reset_labels() -> None:
    """Drop runtime additions; the next lookup reloads bundled + env-named files."""
    global _labels
    _labels = None


def all_labels() -> dict[str, LabelSpec]:
    """Every known label by identifier, as a copy (add via register_label)."""
    return dict(_registry())


def get_label(identifier: str) -> LabelSpec | None:
    """Get label specification by identifier."""
    return _registry().get(identifier)


def get_labels_for_model(model_name: str) -> list[LabelSpec]:
    """Get all labels compatible with a specific model."""
    labels = []
    for label in _registry().values():
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
        for label in _registry().values()
        if label.kind in (LabelKind.DIE_CUT, LabelKind.ROUND_DIE_CUT)
    ]


def get_endless_labels() -> list[LabelSpec]:
    """Get all endless labels."""
    return [
        label
        for label in _registry().values()
        if label.kind in (LabelKind.ENDLESS, LabelKind.PTOUCH_ENDLESS)
    ]


def __getattr__(name: str) -> object:
    """Serve the legacy LABEL_SPECS mapping without loading it at import."""
    if name == "LABEL_SPECS":
        return all_labels()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
