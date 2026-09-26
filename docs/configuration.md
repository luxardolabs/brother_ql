# Configuration

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

Every printer and label specification is JSON, so you can add a label or fix positioning without changing code — or forking.

## Where definitions come from

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

The `brother-ql` command adds a fourth way, for people rather than programs: it reads the conventional per-machine files and hands them to the library. See [Command line](cli.md).

## Rules that apply to all of them

- **Merging is by identifier.** An entry overrides only the fields it names; everything else on that label or model comes from the bundled definition, and definitions you never mention stay available.
- **Later wins.** Bundled, then each env-named file left to right, then explicit `load_*_from` / `register_*` calls.
- **Mistakes are loud.** A malformed entry raises an error naming the file and the identifier; a path that does not exist is an error, not a silent skip. Neither is swallowed, because a skipped definition resurfaces much later as a confusing "Unknown label identifier".
- `all_labels()` / `all_models()` return the current sets; `reset_labels()` / `reset_models()` discard runtime additions (useful in tests).

## Adding a custom label

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

Then point the library at it:

```sh
export BROTHER_QL_LABELS=/path/to/labels.json
```

or from code:

```python
from brother_ql.labels import load_labels_from

load_labels_from('/path/to/labels.json')
instructions = convert(qlr, [img], 'my_custom_50x30')
```

`total_width` defaults to `printable_width` when omitted, `kind` to `die-cut`.

## Fixing label positioning

If labels print off-center, override the positioning for that model. Because merging is per identifier, the override names only `positioning` — dimensions and capabilities stay as bundled:

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
export BROTHER_QL_MODELS=/path/to/models.json
```

`standard_position` is the X position in the 720-pixel raster buffer — see [Advanced](advanced.md#3-label-positioning-within-buffer).

## Why the library does not read your home directory (and the CLI does)

Config discovery is a property of an *application*, not a library. A library that reads `$HOME` at import behaves differently on two machines running identical code, can fail to import because of a file nobody remembers writing, and lets an ambient file change what physically prints. So the split is:

- **`brother_ql` the library**: bundled definitions, plus exactly what the caller passes in.
- **`brother-ql` the CLI**: reads `/etc/brother_ql/`, `$XDG_CONFIG_HOME/brother_ql/` and `~/.brother_ql/` (lowest precedence first), then `--labels` / `--models`, and hands each file to the loaders above.

That keeps the drop-in-a-JSON workflow for people using the command, while a service importing the library stays deterministic.

> Before 2.0.0 the library *documented* those three directories but could never read them — the bundled file came first in the search order and always exists. See the changelog's Breaking section.
