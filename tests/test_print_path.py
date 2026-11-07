"""The raster a printer receives, read back from convert() and BrotherQLRaster.

Each test decodes the bytes a QL printer is sent: the row count from ESC i z, and every
uncompressed raster row (`g 0x00 <length> <row>`) before the final print command.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import struct

import pytest
from PIL import Image

from brother_ql import BrotherQLRaster, convert

ROW_BYTES = 90  # a 720-dot QL head


def raster_rows(data: bytes) -> list[bytes]:
    """The uncompressed QL raster rows of a one-page job, in order."""
    at = data.rindex(b"\x1b\x69\x7a")
    count = struct.unpack("<L", data[at + 7 : at + 11])[0]
    assert data.endswith(b"\x1a")
    block = data[-1 - count * (3 + ROW_BYTES) : -1]
    rows = [block[i : i + 3 + ROW_BYTES] for i in range(0, len(block), 3 + ROW_BYTES)]
    assert len(rows) == count
    for row in rows:
        assert row[:3] == b"\x67\x00" + bytes([ROW_BYTES])
    return [row[3:] for row in rows]


def dots(row: bytes) -> int:
    """How many dots of one raster row the printer burns."""
    return sum(bin(byte).count("1") for byte in row)


def test_600_dpi_on_an_endless_label_prints_the_printable_width():
    # 600 DPI is 300 dots across the head and 600 along the tape: an image twice the
    # printable width keeps its rows and is halved across.
    img = Image.new("L", (696 * 2, 100), 0)
    rows = raster_rows(convert(BrotherQLRaster("QL-570"), [img], "62", dpi_600=True))
    assert len(rows) == 100
    assert {dots(row) for row in rows} == {696}


def test_600_dpi_on_a_die_cut_label_takes_a_600_dpi_image():
    img = Image.new("L", (696 * 2, 271 * 2), 0)
    rows = raster_rows(convert(BrotherQLRaster("QL-570"), [img], "62x29", dpi_600=True))
    assert len(rows) == 271 * 2
    assert {dots(row) for row in rows} == {696}


def test_600_dpi_on_a_die_cut_label_refuses_a_300_dpi_image():
    img = Image.new("L", (696, 271), 0)
    with pytest.raises(ValueError, match="height"):
        convert(BrotherQLRaster("QL-570"), [img], "62x29", dpi_600=True)


@pytest.mark.parametrize("mode", ["1", "L", "RGB"])
def test_a_white_image_narrower_than_the_head_prints_nothing(mode):
    # 29x90 is 306 dots wide on a 720-dot head, so the image is padded.
    img = Image.new(mode, (306, 991), 1 if mode == "1" else "white")
    rows = raster_rows(convert(BrotherQLRaster("QL-810W"), [img], "29x90"))
    assert {dots(row) for row in rows} == {0}


@pytest.mark.parametrize("mode", ["1", "L"])
def test_a_black_image_narrower_than_the_head_prints_only_itself(mode):
    img = Image.new(mode, (306, 991), 0)
    rows = raster_rows(convert(BrotherQLRaster("QL-810W"), [img], "29x90"))
    assert {dots(row) for row in rows} == {306}


@pytest.mark.parametrize("name", ["PT-P750W", "pt-p750w", "pt_p750w"])
def test_a_p_touch_gets_p_touch_rows_however_its_name_is_spelled(name):
    qlr = BrotherQLRaster(name)
    assert qlr.model == "PT-P750W"
    qlr.add_raster_data(Image.new("1", (qlr.get_pixel_width(), 2), 0))
    assert qlr.data.startswith(b"\x47")
