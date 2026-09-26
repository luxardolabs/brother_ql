# Troubleshooting

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

## Debug output

Start here — the library logs what it loads and what it does:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

instructions = convert(qlr, [img], '62x29')
```

For configuration problems specifically, `brother-ql config` prints every path searched and everything loaded — see [Command line](cli.md#when-a-custom-label-isnt-there).

## Permission denied on USB

```bash
# Add user to lp group
sudo usermod -a -G lp $USER
# Log out and back in
```

## Labels print off-center

Add a positioning override for that model — it names only `positioning`, so the model's other fields stay as bundled. See [Fixing label positioning](configuration.md#fixing-label-positioning).

The `brother-ql` command reads `~/.brother_ql/models.json` automatically; from code, load the file explicitly with `load_models_from()`.

## A custom label "isn't there"

Run `brother-ql config`. The usual causes: the file is somewhere the CLI does not search, `--no-user-config` is in play, or the library is being used directly (it searches nothing by design — see [Configuration](configuration.md#why-the-library-does-not-read-your-home-directory-and-the-cli-does)).

## Poor image quality

- Use `dither=True` for photos
- Ensure the image is the correct resolution (300 DPI)
- Try `hq=True` (usually the default)
- Adjust `threshold` (default 70%)

## Red not printing

- Check the model supports red (QL-8xx series): `brother-ql models` shows `two-color`
- Pass `red=True`
- Use pure red (255, 0, 0) — dark reds fall on the black side of the separation

## Compression errors

Disable compression. Not all models implement it properly, and it is off by default.

## Unknown label identifier

The identifier is not in the bundled set or anything you loaded. `brother-ql labels` lists what is available. If you expected an override to supply it, the file may not have been read at all — see above.

## Malformed entry errors

An error naming a file and an entry means exactly that: the definition is invalid, and it is refused rather than skipped, because a skipped definition resurfaces later as a confusing "Unknown label identifier". Fix the named entry. Required fields are `width_mm` and `printable_width` for a new label, `name` and `min_max_length_dots` for a new model; an override of an existing identifier needs only the fields it changes.
