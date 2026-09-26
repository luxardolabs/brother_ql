# API reference

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

## Core functions

### `BrotherQLRaster(model: str)`

Create a raster generator for a specific printer model.

```python
qlr = BrotherQLRaster('QL-810W')
```

Raises `BrotherQLUnknownModel` if the model is not defined.

### `convert(qlr, images, label, **options) -> bytes`

Convert images to printer instructions.

**Parameters**

- `qlr`: `BrotherQLRaster` instance
- `images`: list of PIL Images, filenames, or `Path` objects
- `label`: label identifier string (e.g. `'62x29'`)
- `**options`: see [Conversion options](usage.md#conversion-options)

**Returns** — `bytes`, the printer instructions.

**Raises**

- `ValueError`: invalid label, unknown model, or an image that cannot be loaded
- `BrotherQLUnsupportedCmd`: feature not supported by the printer

## Lookups

### `get_label(identifier: str) -> LabelSpec | None`

```python
from brother_ql.labels import get_label

label = get_label('62x29')
print(f"Size: {label.printable_width}x{label.printable_height} pixels")
```

### `get_model(identifier: str) -> PrinterModel | None`

```python
from brother_ql.models import get_model

model = get_model('QL-810W')
print(f"Supports red: {model.has_two_color}")
```

Model lookup is case-insensitive and treats `_` as `-`, so `ql_810w` resolves.

### Filtered lookups

`get_labels_for_model(model_name)`, `get_die_cut_labels()`, `get_endless_labels()`, `get_two_color_models()`, `get_models_with_compression()`, `get_wide_format_models()`.

## Extending the definitions

Everything below merges **by identifier**, so an entry overrides only the fields it names. Concepts and file formats are in [Configuration](configuration.md).

### `load_labels_from(path)` / `load_models_from(path)`

Merge a JSON file over the current set.

```python
from brother_ql.labels import load_labels_from

load_labels_from('/srv/my_labels.json')
```

### `register_label(spec)` / `register_model(spec)`

Add or replace one definition built in code, from a `LabelSpec` / `PrinterModel`.

### `all_labels()` / `all_models()`

The current sets, keyed by identifier, as a copy.

### `reset_labels()` / `reset_models()`

Discard runtime additions; the next lookup reloads the bundled definitions plus anything named by `BROTHER_QL_LABELS` / `BROTHER_QL_MODELS`. Useful in tests.

### `LABEL_SPECS` / `PRINTER_MODELS`

The legacy mappings still resolve, served lazily through the module's `__getattr__`. Prefer `all_labels()` / `all_models()` in new code.

## Types

### `LabelSpec`

Frozen dataclass: `identifier`, `name`, `width_mm`, `height_mm`, `kind` (`LabelKind`), `printable_width`, `printable_height`, `total_width`, `total_height`, `right_margin_dots`, `feed_margin`, `restricted_to_models`. Properties: `dots_printable`, `dots_total`, `tape_size`, `is_endless`.

### `PrinterModel`

Frozen dataclass: `name`, `min_max_length_dots`, `bytes_per_row`, `additional_offset_r`, the `has_*` capability flags, and `positioning`. Properties: `identifier`, `pixel_width`, `is_two_color`, `is_wide_format`.

### `LabelKind`

`DIE_CUT`, `ENDLESS`, `ROUND_DIE_CUT`, `PTOUCH_ENDLESS`.

## Exceptions

`BrotherQLError` (base), `BrotherQLRasterError`, `BrotherQLUnknownModel`, `BrotherQLUnsupportedCmd`.

## Version

`brother_ql.__version__` derives from the installed package metadata, falling back to the repository's `VERSION` file in a source checkout.
