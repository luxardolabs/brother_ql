# Advanced

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

Findings, protocol notes and performance guidance. For adding labels or fixing positioning, see [Configuration](configuration.md).

## Experimental findings

Through extensive testing with the Brother QL-810W, we've found capabilities beyond the official specifications.

### 1. True physical print width

**Official spec**: 23x23mm labels have 202 pixels printable width. **Discovery**: the physical thermal elements can print approximately 300 pixels.

So you can achieve full-bleed printing on die-cut labels by creating wider images:

```python
# Standard 23x23 (with margins)
img = Image.new('RGB', (202, 202), 'white')

# Full-bleed 23x23 (edge-to-edge)
img = Image.new('RGB', (300, 202), 'white')
```

### 2. Raster buffer width

The QL series uses a 720-pixel wide raster buffer. The label's physical position within this buffer determines centering:

- **Pixel 0-719**: full device width
- **Pixel ~450**: center position for 23x23mm on QL-810W (experimentally determined)
- **Pixel 400-700**: approximate physical label area for 23x23mm

### 3. Label positioning within buffer

Different labels sit at different positions in the buffer:

| Label size | Standard position | Physical start | Physical end |
| ---------- | ----------------- | -------------- | ------------ |
| 23x23mm    | 450               | ~400           | ~700         |
| 62x29mm    | (right-aligned)   | varies         | ~720         |

This is what a `positioning` override in a model definition changes.

### 4. Binary thermal printing

The QL series uses direct thermal printing, which is strictly binary:

- each pixel is either heated (black) or not heated (white)
- no grayscale capability at the hardware level
- grayscale is simulated with Floyd-Steinberg dithering

### 5. Print quality factors

Best print quality comes from:

1. the correct threshold for B/W conversion (default: 70%)
1. dithering for photos
1. proper label positioning
1. high-quality mode (default enabled)

### Why these findings matter

1. **Full-bleed printing**: you can print edge-to-edge on die-cut labels
1. **Custom labels**: understanding the buffer helps position custom sizes
1. **Quality optimization**: knowing the binary nature helps choose image processing

## Printer protocol details

Brother QL printers use a raster protocol where images are sent as binary data:

1. **Initialization**: reset printer to a known state
1. **Mode setting**: configure cutting, quality, etc.
1. **Media info**: tell the printer the label type and size
1. **Raster data**: send image data line by line
1. **Print command**: trigger the actual printing

`BrotherQLRaster` handles all of this.

## Performance

### Image processing

- **Pre-size images** to exact label dimensions to avoid resizing
- **Use monochrome mode** when possible (faster than dithering)
- **Cache converted images** if printing multiple copies

### Printing

- **Compression**: enable for large labels (reduces data transfer)
- **Direct device access**: faster than print spoolers
- **Batch printing**: reuse the `BrotherQLRaster` instance

```python
qlr = BrotherQLRaster('QL-810W')
images = [img1, img2, img3]

for img in images:
    instructions = convert(qlr, [img], '62x29')
    with open('/dev/usb/lp0', 'wb') as printer:
        printer.write(instructions)
    qlr.data = b''  # Clear for next image
```
