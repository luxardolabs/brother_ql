# Brother QL Label Printer Library

A clean, modern Python library for Brother QL series label printers. Pure Python 3.14+ with full type hints and JSON-based configuration.

## Features

- ✨ **Simple API** - Just 3 steps: create image, generate instructions, send to printer
- 🎯 **Type Safe** - Full type hints and mypy compliance
- 📋 **JSON Configuration** - All specs externalized, easy to customize
- 🖼️ **Image Processing** - Dithering, rotation, positioning
- 🏷️ **Many Label Sizes** - Die-cut and endless labels supported
- 🎨 **Red/Black Printing** - For compatible models (QL-8xx series)
- 🚀 **Few Dependencies** - Pillow and packbits for imaging, click for the CLI
- 🔒 **Security Audited** - No shell execution, network code, or eval

## Installation

This fork is **not on PyPI, and there are no plans to publish it there**. `pip install brother-ql` fetches the original [pklaus/brother_ql](https://pypi.org/project/brother-ql/) (0.9.4) — a different library with a different API. Install this one from the repository, or from the artifacts attached to a [release](https://github.com/luxardolabs/brother_ql/releases):

```bash
pip install 'brother_ql @ git+https://github.com/luxardolabs/brother_ql.git@v2.0.0'
```

Or from source:

```bash
git clone https://github.com/luxardolabs/brother_ql.git
cd brother_ql
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

| Label ID | Size         | Type             | Pixels (300 DPI) |
| -------- | ------------ | ---------------- | ---------------- |
| `23x23`  | 23×23mm      | Die-cut square   | 202×202          |
| `29x90`  | 29×90mm      | Die-cut address  | 306×991          |
| `62x29`  | 62×29mm      | Die-cut address  | 696×271          |
| `62x100` | 62×100mm     | Die-cut shipping | 696×1109         |
| `62`     | 62mm endless | Continuous       | 696×variable     |
| `29`     | 29mm endless | Continuous       | 306×variable     |

See all labels: run `brother-ql labels`, or read `src/brother_ql/config/labels.json`.

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

### Where Definitions Come From

Label and printer definitions ship with the package (`brother_ql/config/*.json`). Nothing is read from your home directory or `/etc`, and nothing is read at import time — you extend the bundled set explicitly, in code or by naming files in an environment variable:

| How                                                 | Use it when                                                                                                           |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `BROTHER_QL_LABELS` / `BROTHER_QL_MODELS`           | you just want to drop in a JSON file, no code. Several paths allowed, separated like `PATH` and applied left to right |
| `load_labels_from(path)` / `load_models_from(path)` | your application decides where its config lives                                                                       |
| `register_label(spec)` / `register_model(spec)`     | you build a definition in code                                                                                        |

Definitions merge **by identifier**: an entry changes only the fields it names, every other label and model stays available, and a later source wins over an earlier one. A malformed entry raises an error naming the file and the identifier rather than being skipped.

The `brother-ql` command adds a fourth way, for people rather than programs: it reads the conventional per-machine files and hands them to the library. See [Command Line](#command-line).

### Adding Custom Labels

Create `my_labels.json`:

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

Then point the library at it, either with the environment variable:

```sh
export BROTHER_QL_LABELS=/path/to/my_labels.json
```

or from code:

```python
from brother_ql.labels import load_labels_from

load_labels_from('/path/to/my_labels.json')
instructions = convert(qlr, [img], 'my_custom_50x30')
```

### Label Positioning Overrides

If labels print off-center, override the positioning for that model. Name only what changes — the model's other fields come from the bundled definition:

```json
{
  "QL-810W": {
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

```sh
export BROTHER_QL_MODELS=/path/to/my_models.json
```

## Command Line

Installing the package provides `brother-ql`:

```sh
brother-ql labels                 # list label definitions
brother-ql labels --model QL-810W # only those usable on that model
brother-ql models                 # list printer models and their capabilities
brother-ql config                 # what config was searched for and loaded
brother-ql convert label.png --model QL-810W --label 62x29 -o out.bin
```

`convert` writes raster instructions as bytes; sending them to a printer stays your call (see [Sending to Printer](#sending-to-printer)). Use `-o -` to write to stdout.

### Per-machine configuration

The library itself never searches the filesystem. The CLI does, reading these if present, lowest precedence first:

1. `/etc/brother_ql/labels.json` and `models.json`
1. `$XDG_CONFIG_HOME/brother_ql/…` (default `~/.config/brother_ql/…`)
1. `~/.brother_ql/…` (legacy location)
1. anything named with `--labels` / `--models`, left to right

So a custom label lives in `~/.brother_ql/labels.json` and is picked up by every `brother-ql` run, while a program using the library gets nothing it did not ask for. `--no-user-config` ignores the discovered files, which is what a reproducible run wants:

```sh
brother-ql --no-user-config labels
brother-ql --labels ./ci-labels.json convert label.png --model QL-810W --label my50x30 -o out.bin
```

`brother-ql config` is the first thing to run when a custom label "isn't there" — it prints every path searched, what was loaded, the environment variables, and the resulting counts.

## Releases

Versions follow [SemVer](https://semver.org/); [`CHANGELOG.md`](CHANGELOG.md) holds what changed, and each release is tagged `v<version>` with matching notes on the [releases page](https://github.com/luxardolabs/brother_ql/releases).

Pin a version by tag (this fork is not on PyPI — see [Installation](#installation)):

```sh
pip install 'brother_ql @ git+https://github.com/luxardolabs/brother_ql.git@v2.0.0'
```

**Upgrading from 1.0.0** — it requires Python 3.14+, and the library no longer searches `~/.brother_ql`, `~/.config/brother_ql` or `/etc/brother_ql` (those paths were documented but never actually reachable). Use the `brother-ql` command, which does read them, or load your file explicitly. See [Configuration](#configuration) and the changelog's Breaking section.

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

#### `get_model(identifier: str) -> PrinterModel | None`

Get printer model specification.

```python
from brother_ql.models import get_model

model = get_model('QL-810W')
print(f"Supports red: {model.has_two_color}")
```

### Extending the Definitions

Merged by identifier, so an entry overrides only the fields it names. See [Configuration](#configuration).

#### `load_labels_from(path)` / `load_models_from(path)`

Merge a JSON file over the current set.

```python
from brother_ql.labels import load_labels_from

load_labels_from('/srv/my_labels.json')
```

#### `register_label(spec)` / `register_model(spec)`

Add or replace one definition built in code.

#### `all_labels()` / `all_models()`

The current sets, keyed by identifier (a copy).

#### `reset_labels()` / `reset_models()`

Discard runtime additions; the next lookup reloads the bundled definitions plus anything named by `BROTHER_QL_LABELS` / `BROTHER_QL_MODELS`. Useful in tests.

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

Add a positioning override for that model. The `brother-ql` command reads `~/.brother_ql/models.json`; from code, load the file explicitly with `load_models_from()` (see [Configuration](#configuration)).

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
1. Create a feature branch
1. Add tests for new functionality
1. Run `pytest tests/` to ensure all tests pass
1. Submit a pull request

## License

GPL-3.0-or-later

Original work Copyright (C) 2016-2023 Philipp Klaus and contributors\
Modified work Copyright (C) 2025 Luxardo Labs

## Acknowledgments

This is a modernized fork of the original [brother_ql](https://github.com/pklaus/brother_ql) library by Philipp Klaus. The core protocol implementation remains largely unchanged, while the architecture has been modernized for Python 3.14+ with type safety, JSON configuration, and simplified printing interface.
