# Advanced Usage and Customization

## JSON Configuration

The Brother QL library uses JSON files for all printer and label specifications, making it easy to add custom labels or adjust positioning without modifying code — or forking.

### How Definitions Are Loaded

The definitions bundled with the package (`src/brother_ql/config/*.json` in this repository) are the starting point, and you layer your own over them. There is no directory scan: the library never reads `~/.brother_ql`, `~/.config` or `/etc`, so the same code behaves the same on a laptop, in CI and in production. Loading happens on first use, so importing `brother_ql` touches no files.

Three ways to add your own, all equivalent in effect:

```sh
# 1. No code. Several paths allowed, separated like PATH, applied left to right.
export BROTHER_QL_LABELS=/srv/labels.json
export BROTHER_QL_MODELS=/srv/models.json
```

```python
# 2. Your application picks the path.
from brother_ql.labels import load_labels_from
from brother_ql.models import load_models_from

load_labels_from('/srv/labels.json')
load_models_from('/srv/models.json')
```

```python
# 3. Built in code, no file at all.
from brother_ql.labels import LabelKind, LabelSpec, register_label

register_label(LabelSpec(
    identifier='my_custom_50x30',
    name='50mm x 30mm Custom',
    width_mm=50.0,
    height_mm=30.0,
    kind=LabelKind.DIE_CUT,
    printable_width=554,
    printable_height=271,
    total_width=590,
    total_height=306,
))
```

Rules that apply to all three:

- **Merging is by identifier.** An entry overrides only the fields it names; everything else on that label or model comes from the bundled definition, and definitions you never mention stay available.
- **Later wins.** Bundled, then each env-named file left to right, then explicit `load_*_from` / `register_*` calls.
- **Mistakes are loud.** A malformed entry raises an error naming the file and the identifier; a path that does not exist is an error, not a silent skip. Neither is swallowed, because a skipped definition resurfaces much later as a confusing "Unknown label identifier".
- `all_labels()` / `all_models()` return the current sets; `reset_labels()` / `reset_models()` discard runtime additions (useful in tests).

### Why the library does not read `~/.brother_ql` — and the CLI does

Config discovery is a property of an *application*, not a library. A library that reads `$HOME` at import behaves differently on two machines running identical code, can fail to import because of a file nobody remembers writing, and lets an ambient file change what physically prints. So the split is:

- **`brother_ql` the library**: bundled definitions, plus exactly what the caller passes in.
- **`brother-ql` the CLI**: reads `/etc/brother_ql/`, `$XDG_CONFIG_HOME/brother_ql/` and `~/.brother_ql/` (lowest precedence first), then `--labels` / `--models`, and hands each file to the loaders above.

That keeps the drop-in-a-JSON workflow for people using the command, while a service importing the library stays deterministic. `brother-ql config` prints what was searched and loaded; `brother-ql --no-user-config` ignores the machine's files entirely.

### Adding Custom Labels

Create a `labels.json` anywhere you like:

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

If your labels print off-center, you can add positioning overrides without modifying the library. Because merging is per identifier, the override names only `positioning` — dimensions and capabilities stay as bundled:

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

The `standard_position` value determines the X-axis position in the 720-pixel wide raster buffer.

## Experimental Findings

### QL-810W Thermal Printing Discoveries

Through extensive testing with the Brother QL-810W, we've discovered capabilities beyond the official specifications:

#### 1. True Physical Print Width

**Official Spec**: 23x23mm labels have 202 pixels printable width\
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
| ---------- | ----------------- | -------------- | ------------ |
| 23x23mm    | 450               | ~400           | ~700         |
| 62x29mm    | (right-aligned)   | varies         | ~720         |

#### 4. Binary Thermal Printing

The QL series uses direct thermal printing which is strictly binary:

- Each pixel is either heated (black) or not heated (white)
- No grayscale capability at the hardware level
- Grayscale simulation achieved through Floyd-Steinberg dithering

#### 5. Print Quality Factors

Best print quality is achieved by:

1. Using the correct threshold for B/W conversion (default: 70%)
1. Applying dithering for photos
1. Ensuring proper label positioning
1. Using high-quality mode (default enabled)

### Why These Findings Matter

1. **Full-Bleed Printing**: You can print edge-to-edge on die-cut labels
1. **Custom Labels**: Understanding the buffer helps position custom label sizes
1. **Quality Optimization**: Knowing the binary nature helps choose appropriate image processing

## Printer Protocol Details

The Brother QL printers use a raster protocol where images are sent as binary data:

1. **Initialization**: Reset printer to known state
1. **Mode Setting**: Configure cutting, quality, etc.
1. **Media Info**: Tell printer the label type and size
1. **Raster Data**: Send image data line by line
1. **Print Command**: Trigger the actual printing

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
