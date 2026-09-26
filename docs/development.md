# Development

*Last grounded: 2026-09-26 — brother_ql 2.0.0.*

Everything runs in Docker. There is no local virtualenv to set up, and no host toolchain to install — lint, types, tests, dependency audit and the secret scan all run from pinned images.

## The gate

```sh
make check    # the full gate, in canonical order
make -k check # run every step even after one fails
```

`check` is `guard-version-check honest lint mypy test arch audit gitleaks`. It is a prerequisite list, so it stops at the first failure; `-k` shows every verdict.

| Target            | What it does                                                 |
| ----------------- | ------------------------------------------------------------ |
| `make lint`       | ruff + markdown + repo rules, canonical config               |
| `make mypy`       | mypy, canonical config, mount-only                           |
| `make test`       | pytest against the installed package                         |
| `make arch`       | architecture conformance                                     |
| `make audit`      | dependency CVEs against `requirements/audit.txt`             |
| `make gitleaks`   | secret scan over the full history                            |
| `make format`     | apply the canonical formatter (run before committing)        |
| `make status`     | regenerate the committed guard-status files                  |
| `make audit-lock` | recompile `requirements/audit.txt` after a dependency change |
| `make build`      | build the sdist + wheel                                      |
| `make release`    | the library release ritual — see [Releases](#releases)       |

`make help` lists them all.

## Running tests

```sh
make test
```

The package is installed into a throwaway container first, so the suite exercises the artifact a user would get rather than the working tree. Running `pytest` directly will not work: the canonical config requires pytest-asyncio, and the tests import `brother_ql` as an installed package.

The suite is 73 tests across 9 files, covering conversion, labels and models, raster generation, image processing, positioning, config-override precedence, the CLI, and end-to-end byte generation.

## Repository layout

The package lives under `src/` so tests and type-checking resolve the *installed* artifact rather than the working tree:

```
src/brother_ql/
├── __init__.py           # Package exports, __version__ from installed metadata
├── cli.py                # The brother-ql command (and all config discovery)
├── conversion.py         # Main convert() function
├── raster.py             # BrotherQLRaster class
├── image_processing.py   # Image manipulation
├── label_positioning.py  # Label alignment
├── labels.py             # Label specifications + extension API
├── models.py             # Printer models + extension API
├── constants.py          # Shared constants
├── enums.py              # Enumerations
├── exceptions.py         # Error types
└── config/
    ├── labels.json       # Bundled label definitions
    └── models.json       # Bundled printer definitions

tests/
├── test_cli.py                 # CLI behaviour and config discovery
├── test_config_overrides.py    # Merge precedence and partial overrides
├── test_conversion.py          # Conversion tests
├── test_image_processing.py    # Image tests
├── test_label_positioning.py   # Positioning tests
├── test_labels.py              # Label tests
├── test_models.py              # Model tests
├── test_print_now.py           # End-to-end byte generation
└── test_raster.py              # Raster tests
```

## Dependencies

`[project].dependencies` is exactly what the package imports: `click` (CLI), `packbits` (raster compression), `Pillow` (imaging). There is no `dev` extra — the tooling comes from the pinned images.

`requirements/audit.txt` is a compiled, audit-only pin of those ranges so the dependency scanner has concrete versions to check. Nothing installs from it. Regenerate it with `make audit-lock` whenever `[project].dependencies` changes; a stale compile is a stale audit.

## Releases

Versions are SemVer, and the `VERSION` file is the only place the number appears — `pyproject.toml` reads it, and `__version__` derives from installed metadata.

A release is a tag **plus** a release object: `make release` runs the gate, builds the artifacts, creates the annotated `v<VERSION>` tag, pushes, and publishes the GitHub Release with that version's changelog section as the notes and the sdist and wheel attached. The ordered ritual is `.claude/skills/release/SKILL.md`; what shipped in each version is [`CHANGELOG.md`](../CHANGELOG.md).

## Contributing

1. Fork the repository
1. Create a feature branch
1. Add tests for new functionality
1. Run `make format`, then `make check` — both must be clean
1. Update the docs your change touches, and bump the "last grounded" marker on each page you edit
1. Submit a pull request
