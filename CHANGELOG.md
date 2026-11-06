# Changelog

All notable changes to brother_ql. This is a **library**, so it is [SemVer](https://semver.org/) and this file holds the content itself (the fleet's per-version `change_logs/` + `release_notes/` split is for deployable apps).

Each released version is anchored by an annotated `v<VERSION>` git tag and a matching GitHub Release carrying that version's notes.

## 2.0.1 — 2026-11-06

Docs, packaging and tooling. No library code changed: `git diff v2.0.0..v2.0.1 -- src` is empty, so the installed package behaves exactly as 2.0.0 does.

### Features

- **The docs are a `docs/` tree**: usage, API, CLI, configuration, advanced, troubleshooting and development pages replace the long README and `ADVANCED.md`. The README's sections describing a repo layout that no longer exists are gone.
- **The sdist now carries `CHANGELOG.md` and `docs/`.**

### Fixes

- **`make check` and `make release` refuse an empty `LUX_REGISTRY`** (BROTHERQL-27). Every guard-backed target skips without one, so the gate could exit 0 having judged almost nothing, and `make release` would then publish.
- **`make -i release` no longer publishes past a red gate** (BROTHERQL-27), and `release` refuses `-t`, `-e`, `--eval`, `-I`, and a `MAKE` or `SHELL` chosen from outside. Other ways to talk the recipe past a red by typing make arguments remain open (BROTHERQL-41).
- **`make test` holds a heavy-job slot and runs under the memory cap**, like every guard run (BROTHERQL-27).
- **`guard-version-check` fails when it cannot pull or read the latest image**, rather than reading a stale or missing one as current (BROTHERQL-27).
- **`onboard-check` judges the audit's exit status** and no longer runs its guards under `make -n` (BROTHERQL-27).
- **Recipes mount the checkout quoted and by its own path**, not the caller's directory, so a directory name holding shell syntax stays a name and `make -C` reads the right tree (BROTHERQL-22, BROTHERQL-27).
- **`make test` emits its pytest config checked and per run, and reports coverage to two decimals**, so 89.5% no longer rounds up past a floor of 90 (BROTHERQL-19, BROTHERQL-21).

### Infra / Ops

- Fleet guards at luxarch 0.345.2, luxlint 0.74.0 and luxaudit 0.16.0, with guard-run v7, gitleaks v20 and hooks re-emitted (BROTHERQL-18, BROTHERQL-20, BROTHERQL-22, BROTHERQL-27, BROTHERQL-43).
- `make check` is the emitted check-gate: every leg runs, and it fails at the end naming each red one. `make -k check` is no longer needed.
- `git commit` also scans the commit message for secrets (`hooks/commit-msg`). Guard-status files and a signed LuxPM sync receipt are committed.
- `requirements/audit.txt` resolves `pillow==13.0.0`. It is audit-only: nothing installs from it.

### Notes

- **Upgrading from 2.0.0:** nothing to do.
- **Pillow's floor is unchanged at `>=10.0`** (BROTHERQL-23), so a consumer can still resolve an older Pillow with known CVEs. If you pin dependencies, pin `Pillow>=13.0.0`.
- Guard escalations raised from this repo and fixed upstream: BROTHERQL-17 (luxarch 0.255.0), -19 (luxlint 0.64.0), -21 (luxlint 0.67.0), -24 and -25 (luxarch 0.329.0). Open escalations against the guards, including the secret-scan gate, are BROTHERQL-28 to -38 and -40.
- `make check` is green at this release: lint 20/0 (3 N/A), mypy 0, 87 tests, coverage 90.36%, arch 43/0 (35 N/A), audit 3 packages 0 vulnerable, gitleaks clean. No `## Known reds`.

## 2.0.0 — 2026-09-26

Fleet-guard onboarding, and the config-override feature finally does what the docs always said.

### Breaking

- **Requires Python 3.14+** (was 3.13+). One version, agreeing everywhere: `requires-python`, the ruff/mypy target, and the test/build image.
- **The library no longer reads configuration from the filesystem.** `~/.brother_ql/`, `~/.config/brother_ql/` and `/etc/brother_ql/` are not searched. They never actually worked — the bundled config came first in the search order and always exists, so those paths were unreachable — but the documented behaviour is gone deliberately, replaced by an explicit API (below) and by the new CLI, which does the searching. A program gets only the definitions it asks for.
- **A malformed label/model entry raises `ValueError`** naming the file and identifier, instead of being logged and skipped. A skipped definition resurfaced later as a misleading "Unknown label identifier".
- **`load_image()` returns a decoded copy** rather than a lazily-opened image, so the file handle is closed before it returns.
- **`brother_ql.backends` is gone.** It was an empty module — a docstring claiming "backwards compatibility for code that used the old backend system" over no code at all, so `from brother_ql.backends import …` failed anyway. Upstream's transport layer (pyusb / network / linux_kernel) is not part of this fork by design: the library returns raster instructions as bytes and you send them, per "Sending to Printer" in the README.
- **The `dev` extra is gone.** `pip install brother_ql[dev]` no longer resolves. It listed black, ruff, mypy, pytest, pytest-cov and types-Pillow — a host toolchain nothing here installs or runs: linting, type-checking and tests all execute in Docker from pinned images (`make lint` / `make mypy` / `make test`).
- **`pyusb` and `attrs` are no longer dependencies** (BROTHERQL-16). Neither was ever imported: `pyusb` was declared for a USB backend this fork never brought over, and the specs are stdlib dataclasses. Every consumer was installing and scanning both for nothing. If you were relying on `brother_ql` to pull `pyusb` in for your own USB code, declare it yourself.

### Features

- **Explicit extension API** (BROTHERQL-7): `load_labels_from(path)` / `load_models_from(path)`, `register_label(spec)` / `register_model(spec)`, `all_labels()` / `all_models()`, `reset_labels()` / `reset_models()`. Definitions merge **by identifier**, so an override names only the fields it changes — a positioning override is a two-line file — and unmentioned definitions stay available. Previously a user file would have replaced the whole set.
- **`BROTHER_QL_LABELS` / `BROTHER_QL_MODELS`** name one or more JSON files (`os.pathsep`-separated, applied left to right) for the no-code case.
- **`brother-ql` CLI** (BROTHERQL-15): `labels`, `models`, `config`, `convert`. It owns per-machine config discovery — `/etc/brother_ql` → `$XDG_CONFIG_HOME/brother_ql` → `~/.brother_ql` → `--labels` / `--models` flags — and passes what it finds to the library's loaders. `--no-user-config` ignores discovered files for a reproducible run; `brother-ql config` prints what was searched and loaded. This also gives the long-declared `click` dependency its first importer.
- **Lazy loading**: importing `brother_ql` touches no files and cannot fail on someone else's config. `LABEL_SPECS` / `PRINTER_MODELS` still resolve, via module `__getattr__`.

### Fixes

- **`filtered_hsv` no longer calls `Image.getdata()`** (BROTHERQL-9), deprecated and removed in Pillow 14, which would have broken all red/black printing. Replaced with `tobytes()`; byte-identical output on 120 cases, and the Pillow floor did not move.
- **`load_image` no longer leaks a file handle** for every path input (BROTHERQL-10). Its only caller never closed the image.

### Refactors

- Package moved to `src/brother_ql/` (import name unchanged) so tests and type-checking resolve the installed artifact.
- Build backend is now **hatchling**, with the version read from the `VERSION` file (`dynamic = ["version"]`); `MANIFEST.in` and the setuptools tables are gone. `__version__` derives from installed metadata instead of repeating the literal.
- f-string logging calls converted to lazy `%`-style (ruff `G004`).

### Infra / Ops

- Onboarded to the three fleet guards (BROTHERQL-1): luxarch, luxlint and luxaudit are pinned in the Makefile and wired into `make check` (`guard-version-check honest lint mypy test arch audit gitleaks`), with `make status` publishing the committed `.lux*-status.json` files.
- `make format` is `luxlint --format` (the canonical fixer); `make audit-lock` compiles `requirements/audit.txt`, an audit-only pinned set so luxaudit has something to scan (BROTHERQL-6) — nothing installs from it and the declared ranges are unchanged.
- Committed git hooks run gitleaks on every commit and push; the fleet Claude Code hooks are installed from the pinned image.

### Notes

- **Upgrading from 1.0.0:** if you relied on a config file in `~/.brother_ql/` (it would not have been read), either use the `brother-ql` CLI, which reads that exact path, or call `load_labels_from()` / `load_models_from()`, or set `BROTHER_QL_LABELS` / `BROTHER_QL_MODELS`. Partial overrides now merge instead of replacing the set.
- **Not on PyPI, by choice.** `pip install brother-ql` fetches the original pklaus library (0.9.4), not this fork. Install from the repository: `pip install 'brother_ql @ git+https://github.com/luxardolabs/brother_ql.git@v2.0.0'`, or from the sdist/wheel attached to the release — those artifacts are the distribution channel.
- Guard escalations raised from this repo and fixed upstream: BROTHERQL-2, -3, -4 (luxarch 0.184.0), -13 (0.185.0), -5 (luxaudit 0.8.0), -12 (luxlint 0.55.0).
- `make check` is green at this release: lint 18/0 (3 N/A), mypy 0, 73 tests, arch 34/0 (11 N/A), audit 3 packages 0 vulnerable, gitleaks clean. No `## Known reds`.

## 1.0.0 — 2025-11-14

The published baseline: the modernized fork of [pklaus/brother_ql](https://github.com/pklaus/brother_ql) — type hints throughout, JSON-driven label and printer specifications, and a simplified `convert()` interface. It predates this changelog; the entry is here so the version history is complete.
