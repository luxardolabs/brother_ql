"""Constants for Brother QL label printers.

Central location for all magic numbers and constants used throughout the library.
"""

# Printer specifications
DEFAULT_BYTES_PER_ROW = 90  # Most QL models use 90 bytes per row
DEFAULT_PIXEL_WIDTH = DEFAULT_BYTES_PER_ROW * 8  # 720 pixels

# Wide format models
WIDE_BYTES_PER_ROW = 162  # QL-1050/1060N
WIDE_PIXEL_WIDTH = WIDE_BYTES_PER_ROW * 8  # 1296 pixels

# PT series
PT_P750W_BYTES_PER_ROW = 16
PT_P900W_BYTES_PER_ROW = 70


# Default thresholds
DEFAULT_THRESHOLD_PERCENT = 70  # Default threshold for B/W conversion (%)

# Feed margins
DEFAULT_FEED_MARGIN = 35
DEFAULT_MIN_FEED = 35
DEFAULT_MAX_FEED = 1500

# DPI settings
STANDARD_DPI = 300
HIGH_DPI = 600

# Raster instruction protocol
RASTER_HEADER_SIZE = 3  # 'g' + 2 bytes for length
COMPRESSION_FLAG = 0x02

# Status response sizes
STATUS_RESPONSE_SIZE = 32
STATUS_EXTENDED_SIZE = 48

# Model feature flags
FEATURE_CUTTING = 0x01
FEATURE_COMPRESSION = 0x02
FEATURE_TWO_COLOR = 0x04
FEATURE_HIGH_DPI = 0x08
FEATURE_MODE_SETTING = 0x10
FEATURE_EXPANDED_MODE = 0x20
