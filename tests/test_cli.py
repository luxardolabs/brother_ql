"""Test the CLI, which is the layer that reads per-machine configuration.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import json

import pytest
from click.testing import CliRunner
from PIL import Image

from brother_ql.cli import main
from brother_ql.labels import LABELS_ENV_VAR, reset_labels
from brother_ql.models import MODELS_ENV_VAR, reset_models


@pytest.fixture(autouse=True)
def _isolated(tmp_path, monkeypatch):
    """No ambient config: an empty home, no env vars, registries reset."""
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "home" / ".config"))
    monkeypatch.delenv(LABELS_ENV_VAR, raising=False)
    monkeypatch.delenv(MODELS_ENV_VAR, raising=False)
    (tmp_path / "home").mkdir()
    reset_labels()
    reset_models()
    yield
    reset_labels()
    reset_models()


CUSTOM_LABEL = {
    "my50x30": {
        "name": "50mm x 30mm Custom",
        "width_mm": 50.0,
        "height_mm": 30.0,
        "printable_width": 590,
        "printable_height": 280,
    }
}


def _write(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload))
    return path


def test_labels_lists_bundled_definitions():
    """The plain listing works with no configuration at all."""
    result = CliRunner().invoke(main, ["labels"])
    assert result.exit_code == 0
    assert "62x29" in result.output
    assert "endless" in result.output


def test_models_lists_bundled_definitions():
    """Models list, with their capabilities."""
    result = CliRunner().invoke(main, ["models"])
    assert result.exit_code == 0
    assert "QL-810W" in result.output
    assert "two-color" in result.output


def test_cli_discovers_the_legacy_home_config(tmp_path):
    """What the library refuses to do, the CLI does: read ~/.brother_ql."""
    _write(tmp_path / "home" / ".brother_ql" / "labels.json", CUSTOM_LABEL)

    result = CliRunner().invoke(main, ["labels"])
    assert result.exit_code == 0
    assert "my50x30" in result.output
    assert "62x29" in result.output  # merged, not replaced


def test_cli_discovers_the_xdg_config(tmp_path):
    """The modern location is read too, via XDG_CONFIG_HOME."""
    _write(
        tmp_path / "home" / ".config" / "brother_ql" / "labels.json",
        CUSTOM_LABEL,
    )

    result = CliRunner().invoke(main, ["labels"])
    assert result.exit_code == 0
    assert "my50x30" in result.output


def test_no_user_config_ignores_discovered_files(tmp_path):
    """A reproducible run can opt out of whatever the machine happens to have."""
    _write(tmp_path / "home" / ".brother_ql" / "labels.json", CUSTOM_LABEL)

    result = CliRunner().invoke(main, ["--no-user-config", "labels"])
    assert result.exit_code == 0
    assert "my50x30" not in result.output


def test_explicit_flag_loads_a_named_file(tmp_path):
    """--labels names a file the caller chose."""
    path = _write(tmp_path / "mine.json", CUSTOM_LABEL)

    result = CliRunner().invoke(main, ["--labels", str(path), "labels"])
    assert result.exit_code == 0
    assert "my50x30" in result.output


def test_config_command_reports_what_was_loaded(tmp_path):
    """`config` answers 'why isn't my label showing up'."""
    path = _write(tmp_path / "home" / ".brother_ql" / "labels.json", CUSTOM_LABEL)

    result = CliRunner().invoke(main, ["config"])
    assert result.exit_code == 0
    assert str(path) in result.output
    assert "Searched:" in result.output
    assert f"{LABELS_ENV_VAR} unset" in result.output
    assert "27 label(s), 16 model(s)." in result.output


def test_config_command_with_no_files():
    """With nothing to load, it says so rather than printing an empty list."""
    result = CliRunner().invoke(main, ["config"])
    assert result.exit_code == 0
    assert "bundled definitions only" in result.output


def test_positioning_override_from_home_config(tmp_path):
    """A two-line model override is picked up by the CLI."""
    _write(
        tmp_path / "home" / ".brother_ql" / "models.json",
        {"QL-810W": {"positioning": {"62x29": {"standard_position": 42}}}},
    )

    result = CliRunner().invoke(main, ["config"])
    assert result.exit_code == 0
    assert "models.json" in result.output


def test_convert_writes_instructions(tmp_path):
    """convert produces raster bytes for a real image."""
    png = tmp_path / "label.png"
    Image.new("RGB", (696, 271), "white").save(png)
    out = tmp_path / "out.bin"

    result = CliRunner().invoke(
        main,
        ["convert", str(png), "--model", "QL-810W", "--label", "62x29", "-o", str(out)],
    )
    assert result.exit_code == 0, result.output
    assert out.stat().st_size > 0


def test_convert_reports_an_unknown_label_as_a_cli_error(tmp_path):
    """A bad argument is a one-line error, not a traceback."""
    png = tmp_path / "label.png"
    Image.new("RGB", (696, 271), "white").save(png)

    result = CliRunner().invoke(
        main,
        [
            "convert",
            str(png),
            "--model",
            "QL-810W",
            "--label",
            "nope",
            "-o",
            str(tmp_path / "out.bin"),
        ],
    )
    assert result.exit_code == 1
    assert "Unknown label identifier: nope" in result.output
    assert "Traceback" not in result.output


def test_malformed_config_is_a_cli_error(tmp_path):
    """A broken config file names itself instead of crashing."""
    _write(tmp_path / "home" / ".brother_ql" / "labels.json", {"oops": {"name": "x"}})

    result = CliRunner().invoke(main, ["labels"])
    assert result.exit_code == 1
    assert "Malformed label entry 'oops'" in result.output
    assert "Traceback" not in result.output
