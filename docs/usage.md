# Usage

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

The library turns PIL images into Brother QL raster instructions. It never talks to a printer: `convert()` returns bytes and you send them (see [Sending to a printer](#sending-to-a-printer)).

## Creating images

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

## Label sizes

Common label sizes (width x height in mm):

| Label ID | Size         | Type             | Pixels (300 DPI) |
| -------- | ------------ | ---------------- | ---------------- |
| `23x23`  | 23×23mm      | Die-cut square   | 202×202          |
| `29x90`  | 29×90mm      | Die-cut address  | 306×991          |
| `62x29`  | 62×29mm      | Die-cut address  | 696×271          |
| `62x100` | 62×100mm     | Die-cut shipping | 696×1109         |
| `62`     | 62mm endless | Continuous       | 696×variable     |
| `29`     | 29mm endless | Continuous       | 306×variable     |

See all labels: run `brother-ql labels`, or read `src/brother_ql/config/labels.json`. To add your own, see [Configuration](configuration.md).

## Printer models

Supported models include:

- **QL-500/550/560/570** - Basic models
- **QL-600/650TD** - With cutter
- **QL-700/710W/720NW** - Network capable
- **QL-800/810W/820NWB** - Red/black printing
- **QL-1050/1060N** - Wide format
- **PT-P700/P750W/P900W/P950NW** - P-touch series

`brother-ql models` lists them with their capabilities.

## Conversion options

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

## Photo printing

For best results with photos, use dithering — the hardware is strictly binary, so grayscale is simulated (see [Advanced](advanced.md)):

```python
from PIL import Image

photo = Image.open('photo.jpg')
photo = photo.resize((696, 464))  # 62mm wide label

qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [photo], '62', dither=True)
```

## Red/black printing

For models that support it (QL-8xx series):

```python
img = Image.new('RGB', (696, 271), 'white')
draw = ImageDraw.Draw(img)
draw.text((50, 50), "BLACK", fill='black')
draw.text((50, 150), "RED", fill='red')

instructions = convert(qlr, [img], '62x29', red=True)
```

Use pure red (255, 0, 0) — dark reds fall on the black side of the separation.

## Full-bleed printing

For edge-to-edge printing on die-cut labels, using a label definition wider than the official printable area:

```python
img = Image.new('RGB', (300, 202), 'white')  # 23x23 full bleed
instructions = convert(qlr, [img], '23x23_fullbleed')
```

Why this works is in [Advanced](advanced.md#1-true-physical-print-width).

## Sending to a printer

This library generates raster instructions as bytes. Send them however you like.

### USB (Linux/Mac)

```python
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

If you get a permission error, see [Troubleshooting](troubleshooting.md#permission-denied-on-usb).

### Network printer

```python
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.connect(('192.168.1.100', 9100))  # Default port 9100
    s.send(instructions)
```

### Windows

```python
# Requires pywin32
import win32print

printer_name = win32print.GetDefaultPrinter()
hprinter = win32print.OpenPrinter(printer_name)
try:
    win32print.StartDocPrinter(hprinter, 1, ("Label", None, "RAW"))
    win32print.WritePrinter(hprinter, instructions)
finally:
    win32print.ClosePrinter(hprinter)
```

### Finding your printer

```bash
# USB devices on Linux/Mac
ls /dev/usb/lp*

# Network printers (if they respond to ping)
ping 192.168.1.100
```

## Examples

### QR code label

```python
import qrcode
from brother_ql import BrotherQLRaster, convert

qr = qrcode.QRCode(version=1, box_size=10, border=4)
qr.add_data('https://example.com')
qr.make(fit=True)
qr_img = qr.make_image(fill_color="black", back_color="white")
qr_img = qr_img.resize((202, 202))

qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [qr_img], '23x23')

with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

### Name badge

```python
from PIL import Image, ImageDraw

img = Image.new('RGB', (696, 271), 'white')  # 62x29mm
draw = ImageDraw.Draw(img)
draw.rectangle([5, 5, 691, 266], outline='black', width=3)
draw.text((348, 100), "John Doe", fill='black', anchor='mm')
draw.text((348, 180), "Engineering", fill='gray', anchor='mm')

qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [img], '62x29')
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

### Shipping label

```python
from PIL import Image, ImageDraw

img = Image.new('RGB', (696, 1109), 'white')  # 62x100mm
draw = ImageDraw.Draw(img)

draw.text((50, 50), "FROM:", fill='black')
draw.text((50, 100), "Acme Corp\n123 Main St\nCity, ST 12345", fill='black')

draw.line([50, 300, 646, 300], fill='black', width=2)

draw.text((50, 350), "TO:", fill='black')
draw.text((50, 420), "Jane Smith\n456 Oak Ave\nTown, ST 67890", fill='black')

draw.rectangle([200, 800, 496, 900], outline='black', width=2)
draw.text((348, 850), "|| || | |||| | ||", fill='black', anchor='mm')

qlr = BrotherQLRaster('QL-810W')
instructions = convert(qlr, [img], '62x100')
with open('/dev/usb/lp0', 'wb') as printer:
    printer.write(instructions)
```

Batch printing reuses the raster instance — see [Advanced](advanced.md#printing).
