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

The library generates raster instructions as bytes and never talks to a printer itself — USB, network and Windows examples are in [Usage](docs/usage.md#sending-to-a-printer).

There is also a command line:

```sh
brother-ql labels                 # what label definitions are available
brother-ql convert label.png --model QL-810W --label 62x29 -o out.bin
```

## Documentation

| Page                                       | What's in it                                                                                            |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| [Usage](docs/usage.md)                     | Creating images, label sizes, conversion options, red/black, full-bleed, sending bytes, worked examples |
| [Configuration](docs/configuration.md)     | Where definitions come from, adding your own labels and models, how merging works                       |
| [Command line](docs/cli.md)                | The `brother-ql` command and the per-machine config discovery it owns                                   |
| [API reference](docs/api.md)               | `convert()`, `BrotherQLRaster`, lookups, the extension API, types                                       |
| [Troubleshooting](docs/troubleshooting.md) | Off-center labels, quality, red not printing, debug logging                                             |
| [Advanced](docs/advanced.md)               | Thermal printing findings, the raster buffer, protocol details, performance                             |
| [Development](docs/development.md)         | Tests, layout, the quality gate, releases, contributing                                                 |
| [Changelog](CHANGELOG.md)                  | What changed, per version                                                                               |

## Releases

Versions follow [SemVer](https://semver.org/); each release is tagged `v<version>` with notes and artifacts on the [releases page](https://github.com/luxardolabs/brother_ql/releases).

**Upgrading from 1.0.0** — it requires Python 3.14+, and the library no longer searches `~/.brother_ql`, `~/.config/brother_ql` or `/etc/brother_ql` (those paths were documented but never actually reachable). Use the `brother-ql` command, which does read them, or load your file explicitly. See [Configuration](docs/configuration.md) and the changelog's Breaking section.

## License

GPL-3.0-or-later

Original work Copyright (C) 2016-2023 Philipp Klaus and contributors\
Modified work Copyright (C) 2025 Luxardo Labs

## Acknowledgments

This is a modernized fork of the original [brother_ql](https://github.com/pklaus/brother_ql) library by Philipp Klaus. The core protocol implementation remains largely unchanged, while the architecture has been modernized for Python 3.14+ with type safety, JSON configuration, and simplified printing interface.
