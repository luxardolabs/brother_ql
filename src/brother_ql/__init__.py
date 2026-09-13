"""Brother QL Label Printer Library

A modern Python library for Brother QL series label printers.

This library provides a clean, type-safe interface for generating
raster instructions that can be sent to Brother QL label printers.
All printer and label specifications are loaded from JSON configuration
files, making it easy to add support for new models or custom labels.

Basic Usage:
    >>> from brother_ql import BrotherQLRaster, convert
    >>> from PIL import Image
    >>>
    >>> # Create your label image
    >>> img = Image.new('RGB', (202, 202), 'white')
    >>>
    >>> # Generate printer instructions
    >>> qlr = BrotherQLRaster('QL-810W')
    >>> instructions = convert(qlr, [img], '23x23')
    >>>
    >>> # Send to printer (Linux/Mac)
    >>> with open('/dev/usb/lp0', 'wb') as printer:
    ...     printer.write(instructions)

Copyright (C) 2016-2023 Philipp Klaus and contributors (original)
Copyright (C) 2025 Luxardo Labs (modernization)
Licensed under GPL-3.0-or-later
"""

from importlib import metadata
from pathlib import Path

from brother_ql.conversion import convert
from brother_ql.exceptions import (
    BrotherQLError,
    BrotherQLRasterError,
    BrotherQLUnknownModel,
    BrotherQLUnsupportedCmd,
)
from brother_ql.raster import BrotherQLRaster

# The VERSION file at the repo root is the only version literal: an installed package reads
# it back from its metadata (hatchling stamped it at build time); an uninstalled source
# checkout reads the file itself (src/brother_ql/ -> two levels up).
try:
    __version__ = metadata.version("brother_ql")
except metadata.PackageNotFoundError:
    __version__ = (Path(__file__).resolve().parents[2] / "VERSION").read_text().strip()

__all__ = [
    "BrotherQLRaster",
    "convert",
    "BrotherQLError",
    "BrotherQLRasterError",
    "BrotherQLUnsupportedCmd",
    "BrotherQLUnknownModel",
]
