"""Test extending the bundled label/model definitions without forking.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import json

import pytest

from brother_ql.label_positioning import get_label_position
from brother_ql.labels import (
    LABELS_ENV_VAR,
    LabelKind,
    LabelSpec,
    all_labels,
    get_label,
    load_labels_from,
    register_label,
    reset_labels,
)
from brother_ql.models import (
    MODELS_ENV_VAR,
    all_models,
    get_model,
    load_models_from,
    register_model,
    reset_models,
)


@pytest.fixture(autouse=True)
def _clean_registries():
    """Every test starts and ends on the bundled definitions alone."""
    reset_labels()
    reset_models()
    yield
    reset_labels()
    reset_models()


def _write(path, payload):
    path.write_text(json.dumps(payload))
    return path


def test_bundled_definitions_load_without_any_config(tmp_path, monkeypatch):
    """With no env var and no explicit load, the bundled set is what you get."""
    monkeypatch.delenv(LABELS_ENV_VAR, raising=False)
    monkeypatch.delenv(MODELS_ENV_VAR, raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))  # a home dir is never consulted
    _write(tmp_path / "labels.json", {"62": {"name": "hijacked"}})

    assert get_label("62").name != "hijacked"
    assert len(all_labels()) == 26
    assert len(all_models()) == 16


def test_env_var_adds_a_label_and_keeps_the_bundled_ones(tmp_path, monkeypatch):
    """The no-code path: point the env var at a file, keep everything else."""
    custom = _write(
        tmp_path / "mine.json",
        {
            "my50x30": {
                "name": "50mm x 30mm Custom",
                "width_mm": 50.0,
                "height_mm": 30.0,
                "printable_width": 590,
                "printable_height": 280,
            }
        },
    )
    monkeypatch.setenv(LABELS_ENV_VAR, str(custom))

    mine = get_label("my50x30")
    assert mine is not None
    assert mine.identifier == "my50x30"
    assert mine.width_mm == 50.0
    assert mine.total_width == 590  # defaulted from printable_width
    assert mine.kind is LabelKind.DIE_CUT
    assert get_label("62x29") is not None  # bundled set intact
    assert len(all_labels()) == 27


def test_partial_override_changes_only_the_named_fields(tmp_path, monkeypatch):
    """An override names one field; the rest of the bundled entry survives."""
    bundled = get_label("62x29")
    custom = _write(tmp_path / "mine.json", {"62x29": {"right_margin_dots": 12}})
    monkeypatch.setenv(LABELS_ENV_VAR, str(custom))
    reset_labels()

    overridden = get_label("62x29")
    assert overridden.right_margin_dots == 12
    assert overridden.printable_width == bundled.printable_width
    assert overridden.name == bundled.name
    assert overridden.kind == bundled.kind


def test_positioning_override_is_a_two_line_file(tmp_path, monkeypatch):
    """The documented use case: nudge one label on one model, keep the model."""
    bundled = get_model("QL-810W")
    custom = _write(
        tmp_path / "models.json",
        {"QL-810W": {"positioning": {"62x29": {"standard_position": 42}}}},
    )
    monkeypatch.setenv(MODELS_ENV_VAR, str(custom))
    reset_models()

    model = get_model("QL-810W")
    assert model.min_max_length_dots == bundled.min_max_length_dots
    assert model.bytes_per_row == bundled.bytes_per_row
    assert model.has_two_color == bundled.has_two_color
    assert get_label_position("QL-810W", "62x29", 500) == 42
    assert get_label_position("QL-810W", "12", 500) == 500


def test_files_apply_left_to_right(tmp_path, monkeypatch):
    """Later files win, so a site file can be layered under a machine one."""
    import os

    first = _write(tmp_path / "a.json", {"62x29": {"feed_margin": 10}})
    second = _write(tmp_path / "b.json", {"62x29": {"feed_margin": 20}})
    monkeypatch.setenv(LABELS_ENV_VAR, f"{first}{os.pathsep}{second}")

    assert get_label("62x29").feed_margin == 20


def test_load_labels_from_and_register_label(tmp_path):
    """The explicit API: a path the caller chose, or a spec built in code."""
    path = _write(tmp_path / "extra.json", {"62x29": {"feed_margin": 7}})
    load_labels_from(path)
    assert get_label("62x29").feed_margin == 7

    register_label(
        LabelSpec(
            identifier="coded",
            name="Built in code",
            width_mm=10.0,
            height_mm=10.0,
            kind=LabelKind.DIE_CUT,
            printable_width=100,
            printable_height=100,
            total_width=100,
            total_height=100,
        )
    )
    assert get_label("coded").name == "Built in code"


def test_load_models_from_and_register_model(tmp_path):
    """Same explicit API on the model side."""
    bundled = get_model("QL-700")
    path = _write(tmp_path / "extra.json", {"QL-700": {"additional_offset_r": 9}})
    load_models_from(path)
    assert get_model("QL-700").additional_offset_r == 9
    assert get_model("QL-700").min_max_length_dots == bundled.min_max_length_dots

    register_model(bundled.__class__(name="QL-FAKE", min_max_length_dots=(1, 2)))
    assert get_model("QL-FAKE") is not None


def test_malformed_entry_names_the_file_and_the_entry(tmp_path, monkeypatch):
    """A broken definition fails loudly, pointing at what to fix."""
    bad = _write(tmp_path / "bad.json", {"oops": {"name": "no dimensions"}})
    monkeypatch.setenv(LABELS_ENV_VAR, str(bad))

    with pytest.raises(ValueError, match=r"Malformed label entry 'oops'"):
        get_label("62x29")


def test_invalid_json_names_the_file(tmp_path, monkeypatch):
    """Not-JSON is reported as such, not as a missing label."""
    bad = tmp_path / "bad.json"
    bad.write_text("{definitely not json")
    monkeypatch.setenv(LABELS_ENV_VAR, str(bad))

    with pytest.raises(ValueError, match="is not valid JSON"):
        get_label("62x29")


def test_missing_env_file_is_an_error_not_a_silent_skip(tmp_path, monkeypatch):
    """A typo'd path must not look like 'no overrides configured'."""
    monkeypatch.setenv(LABELS_ENV_VAR, str(tmp_path / "nope.json"))

    with pytest.raises(FileNotFoundError, match="which is missing"):
        get_label("62x29")


def test_legacy_mapping_attributes_still_work():
    """Apps holding brother_ql.labels.LABEL_SPECS keep working."""
    from brother_ql import labels, models

    assert labels.LABEL_SPECS["62x29"].identifier == "62x29"
    assert models.PRINTER_MODELS["QL-810W"].name == "QL-810W"

    with pytest.raises(AttributeError):
        _ = labels.NOT_A_THING
