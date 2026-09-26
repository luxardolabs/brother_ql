# Command line

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

Installing the package provides `brother-ql`:

```sh
brother-ql labels                 # list label definitions
brother-ql labels --model QL-810W # only those usable on that model
brother-ql models                 # list printer models and their capabilities
brother-ql config                 # what config was searched for and loaded
brother-ql convert label.png --model QL-810W --label 62x29 -o out.bin
```

`convert` writes raster instructions as bytes; sending them to a printer stays your call (see [Sending to a printer](usage.md#sending-to-a-printer)). Use `-o -` to write to stdout.

## Per-machine configuration

The library itself never searches the filesystem. The CLI does, reading these if present, lowest precedence first:

1. `/etc/brother_ql/labels.json` and `models.json`
1. `$XDG_CONFIG_HOME/brother_ql/…` (default `~/.config/brother_ql/…`)
1. `~/.brother_ql/…` (legacy location)
1. anything named with `--labels` / `--models`, left to right

So a custom label lives in `~/.brother_ql/labels.json` and is picked up by every `brother-ql` run, while a program using the library gets nothing it did not ask for. Each file found is handed to the library's own loaders, so the merge rules in [Configuration](configuration.md#rules-that-apply-to-all-of-them) apply unchanged.

`--no-user-config` ignores the discovered files, which is what a reproducible run wants:

```sh
brother-ql --no-user-config labels
brother-ql --labels ./ci-labels.json convert label.png --model QL-810W --label my50x30 -o out.bin
```

## When a custom label "isn't there"

Run `brother-ql config`. It prints every path searched, what was loaded in precedence order, the state of `BROTHER_QL_LABELS` / `BROTHER_QL_MODELS`, and the resulting counts:

```
Loaded, lowest precedence first:
  /home/you/.brother_ql/labels.json

Searched:
  /etc/brother_ql/labels.json, /etc/brother_ql/models.json
  /home/you/.config/brother_ql/labels.json, /home/you/.config/brother_ql/models.json
  /home/you/.brother_ql/labels.json, /home/you/.brother_ql/models.json
  BROTHER_QL_LABELS unset
  BROTHER_QL_MODELS unset

27 label(s), 16 model(s).
```

A malformed file, or a `--labels` path that does not exist, is reported as a one-line CLI error naming the file and the entry — never a traceback and never a silent skip.
