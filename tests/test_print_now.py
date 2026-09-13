"""End-to-end check for the 23x23mm die-cut label on a QL-810W.

Was a repo-root scratch script (`test_print_now.py`) that drew an alignment target,
converted it, and wrote `test_23x23.bin` to the CWD as a side effect at import time.
Relocated here per the fleet layout standard (tests live at repo-root `tests/`) and
turned into a real pytest test: same alignment image, same conversion, but the
instruction stream is asserted rather than written to the working tree.

To produce a physical alignment print, write `instructions` to the device — see the
"Sending to Printer" section of README.md.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from PIL import Image, ImageDraw

from brother_ql import BrotherQLRaster, convert


def _alignment_target() -> Image.Image:
    """Draw the 23x23mm alignment target: border, crosshair and edge labels."""
    img = Image.new("RGB", (202, 202), "white")
    draw = ImageDraw.Draw(img)

    # Border, 2px in from the edge — shows whether the label is clipped.
    draw.rectangle([2, 2, 199, 199], outline="black", width=2)

    # Centre crosshair.
    draw.line([101, 50, 101, 150], fill="black", width=1)
    draw.line([50, 101, 150, 101], fill="black", width=1)

    # Edge markers — reveal rotation and mirroring.
    draw.text((101, 40), "TOP", fill="black", anchor="mm")
    draw.text((101, 160), "BOTTOM", fill="black", anchor="mm")
    draw.text((40, 101), "L", fill="black", anchor="mm")
    draw.text((162, 101), "R", fill="black", anchor="mm")
    draw.text((101, 101), "23x23", fill="black", anchor="mm")

    return img


def test_23x23_alignment_target_converts() -> None:
    """A 23x23 alignment target converts to a well-formed instruction stream."""
    qlr = BrotherQLRaster("QL-810W")
    instructions = convert(qlr, [_alignment_target()], "23x23", cut=True)

    assert isinstance(instructions, bytes)
    assert instructions, "convert() produced no instructions"

    # ESC @ (initialise) must appear, and the stream must end with the EOF marker
    # that tells the printer this was the last page.
    assert b"\x1b\x40" in instructions
    assert instructions.endswith(b"\x1a")


def test_23x23_alignment_target_is_deterministic() -> None:
    """The same image and options produce byte-identical instructions."""
    first = convert(
        BrotherQLRaster("QL-810W"), [_alignment_target()], "23x23", cut=True
    )
    second = convert(
        BrotherQLRaster("QL-810W"), [_alignment_target()], "23x23", cut=True
    )

    assert first == second
