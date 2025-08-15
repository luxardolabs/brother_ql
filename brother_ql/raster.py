"""
Brother QL raster instruction generator.

This module implements the raster protocol for Brother QL label printers,
allowing you to build a complete set of printer instructions step by step.

The BrotherQLRaster class provides methods to add various commands like
initialization, media settings, compression, and raster data. The resulting
bytecode can be sent directly to the printer.

Copyright (C) 2016-2023 Philipp Klaus and contributors
Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import logging
import struct
from io import BytesIO

import packbits
from PIL import Image

from .exceptions import BrotherQLRasterError, BrotherQLUnknownModel, BrotherQLUnsupportedCmd
from .models import get_model

logger = logging.getLogger(__name__)


class BrotherQLRaster:
    """
    Facilitates the creation of a complete set of raster instructions.

    This class creates raster instructions by adding them one after the other
    using the methods of the class. Each method call adds instructions to
    the member variable `data`.

    Attributes:
        model: The printer model string
        data: The resulting bytecode with all instructions
        exception_on_warning: If True, raise exception for unsupported instructions.
                            If False, log warning and ignore.
        page_number: Current page number being processed
        cut_at_end: Whether to cut at the end of printing
        dpi_600: Whether to use 600 DPI mode
        two_color_printing: Whether to use two-color printing mode
    """

    def __init__(self, model: str = "QL-500"):
        """
        Initialize a BrotherQLRaster instance.

        Args:
            model: Choose from the list of available models.

        Raises:
            BrotherQLUnknownModel: If the model is not supported.
        """
        model_spec = get_model(model)
        if not model_spec:
            raise BrotherQLUnknownModel(f"Unknown model: {model}")

        self.model = model
        self._model_spec = model_spec
        self.data = b""
        self._pquality = True
        self.page_number = 0
        self.cut_at_end = True
        self.dpi_600 = False
        self.two_color_printing = False
        self._compression = False
        self.exception_on_warning = False

        # Initialize media properties
        self._mtype: bytes | None = None
        self._mwidth: bytes | None = None
        self._mlength: bytes | None = None

    def _warn(self, problem: str, kind: type = BrotherQLRasterError) -> None:
        """
        Log warning or raise exception based on configuration.

        Args:
            problem: The warning message
            kind: Exception class to raise if exception_on_warning is True

        Raises:
            Exception of type `kind` if exception_on_warning is True
        """
        if self.exception_on_warning:
            raise kind(problem)
        else:
            logger.warning(problem)

    def _unsupported(self, problem: str) -> None:
        """
        Handle unsupported command.

        Args:
            problem: Description of the unsupported command

        Raises:
            BrotherQLUnsupportedCmd: If exception_on_warning is True
        """
        self._warn(problem, kind=BrotherQLUnsupportedCmd)

    @property
    def two_color_support(self) -> bool:
        """Check if the model supports two-color printing."""
        return self._model_spec.has_two_color

    @property
    def mtype(self) -> bytes | None:
        """Media type property."""
        return self._mtype

    @mtype.setter
    def mtype(self, value: int) -> None:
        """Set media type."""
        self._mtype = bytes([value & 0xFF])

    @property
    def mwidth(self) -> bytes | None:
        """Media width property."""
        return self._mwidth

    @mwidth.setter
    def mwidth(self, value: int) -> None:
        """Set media width."""
        self._mwidth = bytes([value & 0xFF])

    @property
    def mlength(self) -> bytes | None:
        """Media length property."""
        return self._mlength

    @mlength.setter
    def mlength(self, value: int) -> None:
        """Set media length."""
        self._mlength = bytes([value & 0xFF])

    @property
    def pquality(self) -> bool:
        """Print quality property."""
        return self._pquality

    @pquality.setter
    def pquality(self, value: bool) -> None:
        """Set print quality."""
        self._pquality = bool(value)

    def add_initialize(self) -> None:
        """Initialize the printer (ESC @)."""
        self.page_number = 0
        self.data += b"\x1b\x40"  # ESC @

    def add_status_information(self) -> None:
        """Request status information (ESC i S)."""
        self.data += b"\x1b\x69\x53"  # ESC i S

    def add_switch_mode(self) -> None:
        """
        Switch to raster mode on printers that support mode change.

        Other printers are already in raster mode.
        """
        if not self._model_spec.has_mode_setting:
            self._unsupported(
                "Trying to switch the operating mode on a printer "
                "that doesn't support the command."
            )
            return
        self.data += b"\x1b\x69\x61\x01"  # ESC i a

    def add_invalidate(self) -> None:
        """Clear command buffer with null bytes."""
        self.data += b"\x00" * 200

    def add_media_and_quality(self, rnumber: int) -> None:
        """
        Add media and quality settings.

        Args:
            rnumber: Raster number
        """
        self.data += b"\x1b\x69\x7a"  # ESC i z

        valid_flags = 0x80
        valid_flags |= (self._mtype is not None) << 1
        valid_flags |= (self._mwidth is not None) << 2
        valid_flags |= (self._mlength is not None) << 3
        valid_flags |= self._pquality << 6

        self.data += bytes([valid_flags])

        vals = [self._mtype, self._mwidth, self._mlength]
        self.data += b"".join(b"\x00" if val is None else val for val in vals)
        self.data += struct.pack("<L", rnumber)
        self.data += bytes([0 if self.page_number == 0 else 1])
        self.data += b"\x00"

    def add_autocut(self, autocut: bool = False) -> None:
        """
        Add autocut setting.

        Args:
            autocut: Whether to enable autocut
        """
        if not self._model_spec.has_cutting:
            self._unsupported(
                "Trying to call add_autocut with a printer " "that doesn't support it"
            )
            return
        self.data += b"\x1b\x69\x4d"  # ESC i M
        self.data += bytes([autocut << 6])

    def add_cut_every(self, n: int = 1) -> None:
        """
        Set cut frequency.

        Args:
            n: Cut every n labels
        """
        if not self._model_spec.has_cutting:
            self._unsupported(
                "Trying to call add_cut_every with a printer " "that doesn't support it"
            )
            return
        self.data += b"\x1b\x69\x41"  # ESC i A
        self.data += bytes([n & 0xFF])

    def add_expanded_mode(self) -> None:
        """Add expanded mode settings (DPI/cutting/two-color)."""
        if not self._model_spec.has_expanded_mode:
            self._unsupported(
                "Trying to set expanded mode (dpi/cutting at end) "
                "on a printer that doesn't support it"
            )
            return
        if self.two_color_printing and not self.two_color_support:
            self._unsupported(
                "Trying to set two_color_printing in expanded mode "
                "on a printer that doesn't support it."
            )
            return

        self.data += b"\x1b\x69\x4b"  # ESC i K

        flags = 0x00
        flags |= self.cut_at_end << 3
        flags |= self.dpi_600 << 6
        flags |= self.two_color_printing << 0

        self.data += bytes([flags])

    def add_margins(self, dots: int = 0x23) -> None:
        """
        Add margin settings.

        Args:
            dots: Margin size in dots
        """
        self.data += b"\x1b\x69\x64"  # ESC i d
        self.data += struct.pack("<H", dots)

    def add_compression(self, compression: bool = True) -> None:
        """
        Enable or disable compression for raster image lines.

        Not all models support compression. If unsupported but enabled,
        either a warning is logged or an exception is raised based on
        the exception_on_warning setting.

        Args:
            compression: Whether compression should be enabled
        """
        if not self._model_spec.has_compression:
            self._unsupported("Trying to set compression on a printer " "that doesn't support it")
            return

        self._compression = compression
        self.data += b"\x4d"  # M
        self.data += bytes([compression << 1])

    def get_pixel_width(self) -> int:
        """
        Get the pixel width for the current model.

        Returns:
            Pixel width in pixels
        """
        nbpr = self._model_spec.bytes_per_row
        return nbpr * 8

    def add_raster_data(self, image: Image.Image, second_image: Image.Image | None = None) -> None:
        """
        Add image data to the raster instructions.

        The provided image must be binary (every pixel is either black or white).

        Args:
            image: The primary image to be converted and added
            second_image: Optional second image for two-color printing (red layer)

        Raises:
            BrotherQLRasterError: If image dimensions are incorrect
        """
        logger.debug(f"raster_image_size: {image.size[0]}x{image.size[1]}")

        expected_width = self.get_pixel_width()
        if image.size[0] != expected_width:
            raise BrotherQLRasterError(
                f"Wrong pixel width: {image.size[0]}, expected {expected_width}"
            )

        images = [image]
        if second_image:
            if image.size != second_image.size:
                raise BrotherQLRasterError(
                    f"First and second image don't have the same dimensions: "
                    f"{image.size} vs {second_image.size}."
                )
            images.append(second_image)

        frames: list[bytes] = []
        for img in images:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
            img = img.convert("1")
            frames.append(bytes(img.tobytes(encoder_name="raw")))

        frame_len = len(frames[0])
        row_len = images[0].size[0] // 8
        start = 0
        file_str = BytesIO()

        while start + row_len <= frame_len:
            for i, frame in enumerate(frames):
                row = frame[start : start + row_len]

                if self._compression:
                    row = packbits.encode(row)

                translen = len(row)  # number of bytes to be transmitted

                if self.model.startswith("PT"):
                    file_str.write(b"\x47")
                    file_str.write(bytes([translen % 256, translen // 256]))
                else:
                    if second_image:
                        file_str.write(b"\x77\x01" if i == 0 else b"\x77\x02")
                    else:
                        file_str.write(b"\x67\x00")
                    file_str.write(bytes([translen]))

                file_str.write(row)
            start += row_len

        self.data += file_str.getvalue()

    def add_print(self, last_page: bool = True) -> None:
        """
        Add print command.

        Args:
            last_page: If True, adds EOF marker. If False, adds form feed.
        """
        if last_page:
            self.data += b"\x1a"  # 0x1A = ^Z = SUB; here: EOF = End of File
        else:
            self.data += b"\x0c"  # 0x0C = FF = Form Feed
