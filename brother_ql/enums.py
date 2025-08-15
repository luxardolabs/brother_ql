"""Enumerations and constants for Brother QL printers.

This module defines enums for media types and other printer-specific
constants used throughout the library.

Copyright (C) 2016-2023 Philipp Klaus and contributors
Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

from dataclasses import dataclass
from enum import Enum, IntEnum


class LabelKind(Enum):
    """Label type categories."""

    ENDLESS = "endless"
    DIE_CUT = "die_cut"
    ROUND_DIE_CUT = "round_die_cut"
    PTOUCH_ENDLESS = "ptouch_endless"


class PrinterModel(Enum):
    """Supported Brother QL printer models."""

    QL_500 = "QL-500"
    QL_550 = "QL-550"
    QL_560 = "QL-560"
    QL_570 = "QL-570"
    QL_580N = "QL-580N"
    QL_650TD = "QL-650TD"
    QL_700 = "QL-700"
    QL_710W = "QL-710W"
    QL_720NW = "QL-720NW"
    QL_800 = "QL-800"
    QL_810W = "QL-810W"
    QL_820NWB = "QL-820NWB"
    QL_1050 = "QL-1050"
    QL_1060N = "QL-1060N"
    PT_2430PC = "PT-2430PC"
    PT_P700 = "PT-P700"
    PT_P750W = "PT-P750W"

    @classmethod
    def from_string(cls, value: str) -> "PrinterModel":
        """Create PrinterModel from string value."""
        for model in cls:
            if model.value == value:
                return model
        raise ValueError(f"Unknown printer model: {value}")

    @property
    def is_two_color(self) -> bool:
        """Check if model supports two-color printing."""
        return self in (self.QL_800, self.QL_810W, self.QL_820NWB)

    @property
    def is_pt_series(self) -> bool:
        """Check if model is PT series."""
        return self.value.startswith("PT-")


class MediaType(IntEnum):
    """Media type codes for Brother QL printers."""

    PTOUCH_ENDLESS = 0x00
    ENDLESS_LABEL = 0x0A
    DIE_CUT_LABEL = 0x0B


class PrintQuality(Enum):
    """Print quality settings."""

    LOW = "low"
    HIGH = "high"


class Rotation(IntEnum):
    """Image rotation angles."""

    NONE = 0
    CLOCKWISE_90 = 90
    CLOCKWISE_180 = 180
    CLOCKWISE_270 = 270
    AUTO = -1  # Special value for automatic rotation


class BackendType(Enum):
    """Available backend types for printer communication."""

    PYUSB = "pyusb"
    NETWORK = "network"
    LINUX_KERNEL = "linux_kernel"


class ErrorCorrectionLevel(Enum):
    """QR code error correction levels."""

    LOW = "L"
    MEDIUM = "M"
    QUARTILE = "Q"
    HIGH = "H"


@dataclass(frozen=True)
class LabelSpec:
    """Specification for a label type."""

    identifier: str
    name: str
    kind: LabelKind
    tape_size: tuple[int, int]  # (width, length) in mm
    dots_printable: tuple[int, int]  # (width, height) in pixels
    dots_total: tuple[int, int]  # Total dots including margins
    feed_margin: int  # Feed margin in dots
    right_margin_dots: int  # Right margin in dots
    description: str

    @property
    def is_endless(self) -> bool:
        """Check if this is an endless label."""
        return self.kind in (LabelKind.ENDLESS, LabelKind.PTOUCH_ENDLESS)

    @property
    def is_die_cut(self) -> bool:
        """Check if this is a die-cut label."""
        return self.kind in (LabelKind.DIE_CUT, LabelKind.ROUND_DIE_CUT)

    @property
    def pixel_width(self) -> int:
        """Get printable pixel width."""
        return self.dots_printable[0]

    @property
    def pixel_height(self) -> int | None:
        """Get printable pixel height (None for endless)."""
        return self.dots_printable[1] if not self.is_endless else None


@dataclass(frozen=True)
class PrinterCapabilities:
    """Capabilities of a printer model."""

    model: PrinterModel
    min_feed: int
    max_feed: int
    min_length_dots: int
    max_length_dots: int
    bytes_per_row: int
    supports_compression: bool = False
    supports_cutting: bool = False
    supports_expanded_mode: bool = False
    supports_two_color: bool = False
    supports_mode_setting: bool = False
    supports_600dpi: bool = False

    @property
    def pixel_width(self) -> int:
        """Get pixel width for this printer."""
        return self.bytes_per_row * 8


class CommandType(Enum):
    """Brother QL command types."""

    INITIALIZE = "ESC @"
    STATUS_INFO = "ESC i S"
    SWITCH_MODE = "ESC i a"
    INVALIDATE = "NULL"
    MEDIA_AND_QUALITY = "ESC i z"
    AUTOCUT = "ESC i M"
    CUT_EVERY = "ESC i A"
    EXPANDED_MODE = "ESC i K"
    MARGINS = "ESC i d"
    COMPRESSION = "M"
    RASTER_DATA = "g/G/w"
    PRINT = "^Z/FF"


class StatusBit(IntEnum):
    """Status response bit positions."""

    ERROR_INFO_1 = 0
    ERROR_INFO_2 = 1
    MEDIA_WIDTH = 2
    MEDIA_TYPE = 3
    MODE = 5
    AUTO_CUT = 6
    FAN = 7

    # Error bits
    NO_MEDIA = 0x01
    END_OF_MEDIA = 0x02
    TAPE_JAM = 0x04
    COVER_OPEN = 0x10
    OVERHEATING = 0x20


class StatusCode(IntEnum):
    """Printer status codes."""

    READY = 0x00
    ERROR = 0x01
    PRINTING = 0x02
    RECEIVING = 0x03
    PHASE_CHANGE = 0x06
    WAITING = 0x0A
    COOLING = 0x0B
    PRINTING_COMPLETE = 0x0C
