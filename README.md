# Brother QL Label Printer Library

A clean, modern Python library for Brother QL series label printers. Pure Python 3.13+ with full type hints and JSON-based configuration.

## Features

- ✨ **Simple API** - Just 3 steps: create image, generate instructions, send to printer
- 🎯 **Type Safe** - Full type hints and mypy compliance
- 📋 **JSON Configuration** - All specs externalized, easy to customize
- 🖼️ **Image Processing** - Dithering, rotation, positioning
- 🏷️ **Many Label Sizes** - Die-cut and endless labels supported
- 🎨 **Red/Black Printing** - For compatible models (QL-8xx series)
- 🚀 **Minimal Dependencies** - Just PIL/Pillow for images
- 🔒 **Security Audited** - No shell execution, network code, or eval

## Installation

```bash
pip install brother-ql
```

Or install from source:

```bash
git clone https://github.com/luxardolabs/brother-ql.git
cd brother-ql
pip install -e .
```

## Quick Start

```python
from brother_ql import BrotherQLRaster, convert
from PIL import Image, ImageDraw

# Create a label image
img = Image.new('RGB', (696, 271), 'white')  # 62x29mm label
draw = ImageDraw.Draw(img)
draw.text((50, 100), "Hello World!", fill='black')

# Generate printer instructions
qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [img], '62x29')

# Send to printer (example: USB on Linux/Mac)
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

## Detailed Usage

### Creating Images

The library accepts PIL/Pillow images. Create them any way you like:

```python
from PIL import Image, ImageDraw

# Blank label
img = Image.new('RGB', (width, height), 'white')

# From file
img = Image.open('label.png')

# With drawing
draw = ImageDraw.Draw(img)
draw.rectangle([10, 10, 100, 100], outline='black', width=2)
draw.text((50, 50), "TEXT", fill='black')
```

### Label Sizes

Common label sizes (width x height in mm):

| Label ID | Size | Type | Pixels (300 DPI) |
|----------|------|------|------------------|
| `23x23` | 23×23mm | Die-cut square | 202×202 |
| `29x90` | 29×90mm | Die-cut address | 306×991 |
| `62x29` | 62×29mm | Die-cut address | 696×271 |
| `62x100` | 62×100mm | Die-cut shipping | 696×1109 |
| `62` | 62mm endless | Continuous | 696×variable |
| `29` | 29mm endless | Continuous | 306×variable |

See all labels: `brother_ql/config/labels.json`

### Printer Models

Supported models include:

- **QL-500/550/560/570** - Basic models
- **QL-600/650TD** - With cutter
- **QL-700/710W/720NW** - Network capable
- **QL-800/810W/820NWB** - Red/black printing
- **QL-1050/1060N** - Wide format
- **PT-P700/P750W/P900W/P950NW** - P-touch series

### Conversion Options

The `convert()` function accepts many options:

```python
instructions = convert(
    qlr,
    images=[img],
    label='62x29',
    
    # Cutting
    cut=True,           # Auto-cut after printing (default: True)
    
    # Image processing
    dither=True,        # Floyd-Steinberg dithering for photos (default: False)
    threshold=70,       # B/W threshold percentage (default: 70)
    rotate='auto',      # Rotation: 'auto', 0, 90, 180, 270 (default: 'auto')
    
    # Advanced
    compress=False,     # Compress data if supported (default: False)
    red=False,          # Red/black for QL-8xx models (default: False)
    dpi_600=False,      # 600 DPI mode if supported (default: False)
    hq=True,            # High quality mode (default: True)
    
    # Positioning
    offset_x=0,         # Horizontal offset in pixels (default: 0)
)
```

### Photo Printing

For best results with photos, use dithering:

```python
from PIL import Image

# Load and resize photo
photo = Image.open('photo.jpg')
photo = photo.resize((696, 464))  # 62mm wide label

# Convert with dithering
qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [photo], '62', dither=True)
```

### Red/Black Printing

For models that support it (QL-8xx series):

```python
# Image with red and black
img = Image.new('RGB', (696, 271), 'white')
draw = ImageDraw.Draw(img)
draw.text((50, 50), "BLACK", fill='black')
draw.text((50, 150), "RED", fill='red')

# Convert with red enabled
instructions = convert(qlr, [img], '62x29', red=True)
```

### Full-Bleed Printing

For edge-to-edge printing on die-cut labels:

```python
# Create wider image (actual physical width)
img = Image.new('RGB', (300, 202), 'white')  # 23x23 full bleed

# Use custom label definition
instructions = convert(qlr, [img], '23x23_fullbleed')
```

## Sending to Printer

This library generates Brother QL raster instructions as bytes. You can send these to your printer however you like:

### USB (Linux/Mac)

```python
# Direct device write
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)

# Check permissions if needed:
# sudo usermod -a -G lp $USER
```

### Network Printer

```python
import socket

# Send to network printer
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.connect(('192.168.1.100', 9100))  # Default port 9100
    s.send(instructions)
```

### Windows

```python
# Windows printer (requires pywin32)
import win32print
import win32api

printer_name = win32print.GetDefaultPrinter()
hprinter = win32print.OpenPrinter(printer_name)
try:
    win32print.StartDocPrinter(hprinter, 1, ("Label", None, "RAW"))
    win32print.WritePrinter(hprinter, instructions)
finally:
    win32print.ClosePrinter(hprinter)
```

### Finding Your Printer

```bash
# USB devices on Linux/Mac
ls /dev/usb/lp*

# Network printers (if they respond to ping)
ping 192.168.1.100
```

## Configuration

### JSON Files Location

Configuration files are loaded from (first found wins):

1. `~/.brother_ql/labels.json` and `~/.brother_ql/models.json`
2. `~/.config/brother_ql/labels.json` and `~/.config/brother_ql/models.json`  
3. `/etc/brother_ql/labels.json` and `/etc/brother_ql/models.json`
4. Built-in `brother_ql/config/*.json`

### Adding Custom Labels

Create `~/.brother_ql/labels.json`:

```json
{
  "my_custom_50x30": {
    "name": "50mm x 30mm Custom",
    "width_mm": 50.0,
    "height_mm": 30.0,
    "kind": "die-cut",
    "printable_width": 554,
    "printable_height": 271,
    "total_width": 590,
    "total_height": 306,
    "right_margin_dots": 0,
    "feed_margin": 35
  }
}
```

Then use it:

```python
instructions = convert(qlr, [img], 'my_custom_50x30')
```

### Label Positioning Overrides

If labels print off-center, add positioning overrides in `~/.brother_ql/models.json`:

```json
{
  "QL-810W": {
    "name": "QL-810W",
    "min_max_length_dots": [150, 11811],
    "bytes_per_row": 90,
    "positioning": {
      "23x23": {
        "standard_position": 450,
        "comment": "Experimentally determined center position"
      },
      "my_custom_50x30": {
        "standard_position": 400
      }
    }
  }
}
```

## API Reference

### Core Functions

#### `BrotherQLRaster(model: str)`

Create a raster generator for a specific printer model.

```python
qlr = BrotherQLRaster('QL-810W')
```

#### `convert(qlr, images, label, **options) -> bytes`

Convert images to printer instructions.

**Parameters:**
- `qlr`: BrotherQLRaster instance
- `images`: List of PIL Images, filenames, or Path objects
- `label`: Label identifier string (e.g., '62x29')
- `**options`: See Conversion Options above

**Returns:**
- `bytes`: Printer instructions ready to send

**Raises:**
- `ValueError`: Invalid label or image size
- `BrotherQLUnsupportedCmd`: Feature not supported by printer

### Utility Functions

#### `get_label(identifier: str) -> LabelSpec`

Get label specification by ID.

```python
from brother_ql.labels import get_label

label = get_label('62x29')
print(f"Size: {label.printable_width}x{label.printable_height} pixels")
```

#### `get_model(identifier: str) -> PrinterModel`

Get printer model specification.

```python
from brother_ql.models import get_model

model = get_model('QL-810W')
print(f"Supports red: {model.has_two_color}")
```

## Examples

### QR Code Label

```python
import qrcode
from PIL import Image
from brother_ql import BrotherQLRaster, convert

# Generate QR code
qr = qrcode.QRCode(version=1, box_size=10, border=4)
qr.add_data('https://example.com')
qr.make(fit=True)
qr_img = qr.make_image(fill_color="black", back_color="white")

# Resize to label
qr_img = qr_img.resize((202, 202))

# Generate and send
qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [qr_img], '23x23')

# Send to printer
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

### Name Badge

```python
from PIL import Image, ImageDraw

# Create badge
img = Image.new('RGB', (696, 271), 'white')  # 62x29mm
draw = ImageDraw.Draw(img)

# Border
draw.rectangle([5, 5, 691, 266], outline='black', width=3)

# Name
draw.text((348, 100), "John Doe", fill='black', anchor='mm')
draw.text((348, 180), "Engineering", fill='gray', anchor='mm')

# Generate and send
qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [img], '62x29')
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

### Shipping Label

```python
from PIL import Image, ImageDraw

# Create shipping label
img = Image.new('RGB', (696, 1109), 'white')  # 62x100mm
draw = ImageDraw.Draw(img)

# Sender
draw.text((50, 50), "FROM:", fill='black')
draw.text((50, 100), "Acme Corp\n123 Main St\nCity, ST 12345", fill='black')

# Divider
draw.line([50, 300, 646, 300], fill='black', width=2)

# Recipient
draw.text((50, 350), "TO:", fill='black')
draw.text((50, 420), "Jane Smith\n456 Oak Ave\nTown, ST 67890", fill='black')

# Barcode area
draw.rectangle([200, 800, 496, 900], outline='black', width=2)
draw.text((348, 850), "|| || | |||| | ||", fill='black', anchor='mm')

# Generate and send
qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [img], '62x100')
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

## Testing

### Running Tests

```bash
# Install test dependencies
pip install pytest

# Run all tests
pytest tests/

# Run with verbose output
pytest tests/ -v

# Run specific test file
pytest tests/test_conversion.py
```

### Test Coverage

The test suite includes:
- **Conversion tests** - Image to raster conversion with various options
- **Label tests** - Label loading and specifications
- **Model tests** - Printer model capabilities
- **Raster tests** - Low-level raster generation
- **Image processing tests** - Dithering, rotation, resizing
- **Positioning tests** - Label alignment and centering

All tests should pass before submitting pull requests.

## Architecture

```
brother_ql/
├── __init__.py           # Package exports
├── conversion.py         # Main convert() function
├── raster.py            # BrotherQLRaster class
├── image_processing.py   # Image manipulation
├── label_positioning.py  # Label alignment
├── labels.py            # Label specifications
├── models.py            # Printer models
├── constants.py         # Shared constants
├── enums.py             # Enumerations
├── exceptions.py        # Error types
└── config/
    ├── labels.json      # Label definitions
    └── models.json      # Printer definitions

tests/
├── test_conversion.py    # Conversion tests
├── test_labels.py       # Label tests
├── test_models.py       # Model tests
├── test_raster.py       # Raster tests
├── test_image_processing.py  # Image tests
└── test_label_positioning.py # Positioning tests
```

## Troubleshooting

### Permission Denied on USB

```bash
# Add user to lp group
sudo usermod -a -G lp $USER
# Log out and back in
```

### Labels Print Off-Center

Add positioning override in `~/.brother_ql/models.json` (see Configuration above).

### Poor Image Quality

- Use `dither=True` for photos
- Ensure image is correct resolution (300 DPI)
- Try `hq=True` (usually default)

### Red Not Printing

- Check model supports red (`QL-8xx` series)
- Use `red=True` parameter
- Ensure image has actual red colors

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Run `pytest tests/` to ensure all tests pass
5. Submit a pull request

## License

GPL-3.0-or-later

Original work Copyright (C) 2016-2023 Philipp Klaus and contributors  
Modified work Copyright (C) 2025 Luxardo Labs

## Acknowledgments

This is a modernized fork of the original [brother_ql](https://github.com/pklaus/brother_ql) 
library by Philipp Klaus. The core protocol implementation remains largely unchanged, 
while the architecture has been modernized for Python 3.13+ with type safety, 
JSON configuration, and simplified printing interface.