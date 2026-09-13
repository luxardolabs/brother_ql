"""Test printer model specifications.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from brother_ql.models import (
    get_model,
    get_models_with_compression,
    get_two_color_models,
    get_wide_format_models,
)


def test_get_model():
    """Test retrieving model specifications."""
    # Test QL-810W
    model = get_model("QL-810W")
    assert model is not None
    assert model.name == "QL-810W"
    assert model.has_two_color is True
    assert model.has_cutting is True
    assert model.bytes_per_row == 90
    assert model.pixel_width == 720

    # Test positioning overrides
    assert model.positioning is not None
    assert "23x23" in model.positioning
    assert model.positioning["23x23"]["standard_position"] == 450


def test_model_case_insensitive():
    """Test that model lookup is case-insensitive."""
    model1 = get_model("QL-810W")
    model2 = get_model("ql-810w")
    model3 = get_model("QL_810W")

    assert model1 == model2 == model3


def test_get_nonexistent_model():
    """Test that nonexistent models return None."""
    model = get_model("NONEXISTENT")
    assert model is None


def test_get_two_color_models():
    """Test getting models with red/black support."""
    models = get_two_color_models()

    assert len(models) > 0

    # All should have two-color support
    for model in models:
        assert model.has_two_color is True

    # QL-8xx series should be included
    model_names = [m.name for m in models]
    assert "QL-810W" in model_names
    assert "QL-820NWB" in model_names


def test_get_models_with_compression():
    """Test getting models with compression support."""
    models = get_models_with_compression()

    assert len(models) > 0

    # All should support compression
    for model in models:
        assert model.has_compression is True


def test_get_wide_format_models():
    """Test getting wide format models."""
    models = get_wide_format_models()

    # All wide format models should have > 90 bytes per row
    for model in models:
        assert model.bytes_per_row > 90
        assert model.is_wide_format is True


def test_model_properties():
    """Test model property accessors."""
    model = get_model("QL-700")

    # Test identifier property
    assert model.identifier == "QL-700"

    # Test pixel_width calculation
    assert model.pixel_width == model.bytes_per_row * 8

    # Test is_two_color property
    assert model.is_two_color is False

    # Test is_wide_format property
    assert model.is_wide_format is False
