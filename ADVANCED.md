# Advanced Usage and Customization

## JSON Configuration

The Brother QL library uses JSON files for all printer and label specifications, making it easy to add custom labels or adjust positioning without modifying code.

### Configuration File Locations

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

### Fixing Label Positioning

If your labels print off-center, you can add positioning overrides without modifying the library.

Create `~/.brother_ql/models.json`:

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

The `standard_position` value determines the X-axis position in the 720-pixel wide raster buffer.

## Experimental Findings

### QL-810W Thermal Printing Discoveries

Through extensive testing with the Brother QL-810W, we've discovered capabilities beyond the official specifications:

#### 1. True Physical Print Width

**Official Spec**: 23x23mm labels have 202 pixels printable width  
**Discovery**: The physical thermal elements can print approximately 300 pixels

This means you can achieve full-bleed printing on die-cut labels by creating wider images:

```python
# Standard 23x23 (with margins)
img = Image.new('RGB', (202, 202), 'white')

# Full-bleed 23x23 (edge-to-edge)
img = Image.new('RGB', (300, 202), 'white')
```

#### 2. Raster Buffer Width

The QL series uses a 720-pixel wide raster buffer. The label's physical position within this buffer determines centering:

- **Pixel 0-719**: Full device width
- **Pixel ~450**: Center position for 23x23mm on QL-810W (experimentally determined)
- **Pixel 400-700**: Approximate physical label area for 23x23mm

#### 3. Label Positioning Within Buffer

Different labels sit at different positions in the buffer:

| Label Size | Standard Position | Physical Start | Physical End |
|------------|------------------|----------------|--------------|
| 23x23mm    | 450              | ~400           | ~700         |
| 62x29mm    | (right-aligned)  | varies         | ~720         |

#### 4. Binary Thermal Printing

The QL series uses direct thermal printing which is strictly binary:
- Each pixel is either heated (black) or not heated (white)
- No grayscale capability at the hardware level
- Grayscale simulation achieved through Floyd-Steinberg dithering

#### 5. Print Quality Factors

Best print quality is achieved by:
1. Using the correct threshold for B/W conversion (default: 70%)
2. Applying dithering for photos
3. Ensuring proper label positioning
4. Using high-quality mode (default enabled)

### Why These Findings Matter

1. **Full-Bleed Printing**: You can print edge-to-edge on die-cut labels
2. **Custom Labels**: Understanding the buffer helps position custom label sizes
3. **Quality Optimization**: Knowing the binary nature helps choose appropriate image processing

## Printer Protocol Details

The Brother QL printers use a raster protocol where images are sent as binary data:

1. **Initialization**: Reset printer to known state
2. **Mode Setting**: Configure cutting, quality, etc.
3. **Media Info**: Tell printer the label type and size
4. **Raster Data**: Send image data line by line
5. **Print Command**: Trigger the actual printing

The library handles all protocol details automatically through the `BrotherQLRaster` class.

## Performance Optimization

### Image Processing

- **Pre-size images** to exact label dimensions to avoid resizing
- **Use monochrome mode** when possible (faster than dithering)
- **Cache converted images** if printing multiple copies

### Printing

- **Compression**: Enable for large labels (reduces data transfer)
- **Direct device access**: Faster than print spoolers
- **Batch printing**: Reuse the `BrotherQLRaster` instance

Example of efficient batch printing:

```python
qlr = BrotherQLRaster('QL-810W')
images = [img1, img2, img3]

for img in images:
    instructions = convert(qlr, [img], '62x29')
    with open('/dev/usb/lp0', 'wb') as printer:
        printer.write(instructions)
    qlr.data = b''  # Clear for next image
```

## Troubleshooting

### Debug Output

Enable logging to see what the library is doing:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

# Now conversion will show debug info
instructions = convert(qlr, [img], '62x29')
```

### Common Issues

**Labels consistently off-center**: Add positioning override in JSON config

**Poor dithering quality**: Adjust threshold parameter (default 70%)

**Red not printing**: Ensure image uses pure red (255, 0, 0) not dark red

**Compression errors**: Disable compression, not all models support it properly