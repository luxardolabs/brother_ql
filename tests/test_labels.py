"""Test label specifications and loading.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from brother_ql.labels import (
    LabelKind,
    get_die_cut_labels,
    get_endless_labels,
    get_label,
    get_labels_for_model,
)


def test_get_label():
    """Test retrieving label specifications."""
    # Test common label
    label = get_label("62x29")
    assert label is not None
    assert label.identifier == "62x29"
    assert label.width_mm == 62.0
    assert label.height_mm == 29.0
    assert label.printable_width == 696
    assert label.printable_height == 271

    # Test endless label
    label = get_label("62")
    assert label is not None
    assert label.width_mm == 62.0
    assert label.height_mm is None  # Endless
    assert label.kind == LabelKind.ENDLESS


def test_get_nonexistent_label():
    """Test that nonexistent labels return None."""
    label = get_label("nonexistent")
    assert label is None


def test_label_properties():
    """Test label property accessors."""
    label = get_label("23x23")

    # Test tape_size property
    assert label.tape_size == (23.0, 23.0)

    # Test dots_printable property
    assert label.dots_printable == (202, 202)

    # Test is_endless property
    assert label.is_endless is False

    # Test endless label
    endless = get_label("62")
    assert endless.is_endless is True


def test_get_die_cut_labels():
    """Test retrieving all die-cut labels."""
    die_cut = get_die_cut_labels()

    assert len(die_cut) > 0

    # All should be die-cut or round-die-cut
    for label in die_cut:
        assert label.kind in (LabelKind.DIE_CUT, LabelKind.ROUND_DIE_CUT)


def test_get_endless_labels():
    """Test retrieving all endless labels."""
    endless = get_endless_labels()

    assert len(endless) > 0

    # All should be endless type
    for label in endless:
        assert label.kind in (LabelKind.ENDLESS, LabelKind.PTOUCH_ENDLESS)
        assert label.height_mm is None


def test_get_labels_for_model():
    """Test getting labels compatible with specific models."""
    # Test QL model
    labels = get_labels_for_model("QL-810W")
    assert len(labels) > 0

    # Should include common labels
    label_ids = [label.identifier for label in labels]
    assert "62x29" in label_ids
    assert "23x23" in label_ids

    # Test PT model - should have PT-specific labels
    labels = get_labels_for_model("PT-P750W")
    label_ids = [label.identifier for label in labels]
    # PT models typically use different label sizes
