# Development

*Last grounded: 2026-11-18 — brother_ql 2.0.3.*

Everything runs in Docker. There is no local virtualenv to set up, and no host toolchain to install — lint, types, tests, dependency audit and the secret scan all run from pinned images.

## The gate

```sh
make check    # the full gate, in canonical order
```

`check` runs `guard-version-check` and `honest` first, and either one failing stops it. It then runs every leg of `lint mypy test arch audit gitleaks build-pins`, even past a failure, and fails at the end naming each red leg.

The guards come from a private registry, so `make check` and `make release` need `LUX_REGISTRY` in `Makefile.local` and refuse without it, because a gate of skips has judged nothing. With it unset, `lint`, `mypy`, `test`, `arch`, `audit`, `format`, `status`, `honest`, `guard-version-check`, `onboard-check` and `onboard-guards` run on their own skip with a message, and `gitleaks` and `gitleaks-staged` fail on the image name. Run the Makefile from its own directory or with `make -C <dir>`: `make -f <path>` from elsewhere is refused.

| Target               | What it does                                                       |
| -------------------- | ------------------------------------------------------------------ |
| `make onboard-check` | proves all three guards are wired and honest (not green)           |
| `make lint`          | ruff + markdown + repo rules, canonical config                     |
| `make mypy`          | mypy, canonical config, mount-only                                 |
| `make test`          | pytest against the installed package                               |
| `make arch`          | architecture conformance                                           |
| `make audit`         | dependency CVEs against `requirements/audit.txt` and `build.txt`   |
| `make gitleaks`      | secret scan over the full history                                  |
| `make format`        | apply the canonical formatter (run before committing)              |
| `make status`        | regenerate the committed guard-status files                        |
| `make audit-lock`    | recompile `requirements/audit.txt` to the newest admitted releases |
| `make build`         | build the sdist + wheel with the pinned build tools                |
| `make build-lock`    | recompile `requirements/build.txt` (build + hatchling, hashed)     |
| `make build-pins`    | check from make's own database that the build is pinned            |
| `make release`       | the library release ritual — see [Releases](#releases)             |

`make help` lists them all.

## Running tests

```sh
make test
```

`make test` builds a wheel in a throwaway container with the same pinned tools as `make build`, then installs it in a second container and runs the suite against it there. That container sees the repository with `src/` hidden under an empty tmpfs, so the suite exercises the artifact a user would get and can reach the working tree by no import, path or subprocess. Running `pytest` directly will not work: the canonical config requires pytest-asyncio, and the tests import `brother_ql` as an installed package.

The suite is 385 tests across 16 files, covering that the package under test is the installed wheel, the build-pins check, conversion, labels and models, raster generation and the bytes a printer receives, image processing, positioning, config-override precedence, the CLI, end-to-end byte generation, the dependency floors, the release preflight script, and the text of the Makefile's recipes. The suite's image has no `make`, so the Makefile tests read its text: they pin each recipe's shape and do not run it.

The coverage floor is `[test].coverage_min = 90` in `.luxlint.toml`, set from a measured 90% branch coverage. `make test` enforces it: it runs the suite under branch coverage (`COVERAGE_CORE=sysmon`) against the installed package, then feeds `coverage report` to `luxlint --coverage-ratchet`. A failing test or coverage below the floor fails `make test`. Raise the floor when coverage rises, and never lower it.

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
├── test_build_pins.py          # The build-pins check, on a stand-in make
├── test_cli.py                 # CLI behaviour and config discovery
├── test_config_overrides.py    # Merge precedence and partial overrides
├── test_conversion.py          # Conversion tests
├── test_dependency_floors.py   # Ranges admit no release with an advisory
├── test_image_processing.py    # Image tests
├── test_installed_artifact.py  # The suite runs against the installed wheel
├── test_label_positioning.py   # Positioning tests
├── test_labels.py              # Label tests
├── test_makefile_mounts.py     # Container mounts name the checkout
├── test_makefile_recipes.py    # The gate recipes' shape
├── test_models.py              # Model tests
├── test_print_now.py           # End-to-end byte generation
├── test_print_path.py          # The raster a printer receives, decoded
├── test_raster.py              # Raster tests
└── test_release_preflight.py   # The release preflight script, run for real
```

## Dependencies

`[project].dependencies` is exactly what the package imports: `click` (CLI), `packbits` (raster compression), `Pillow` (imaging). There is no `dev` extra — the tooling comes from the pinned images. `make audit` scans the newest release each range admits, so a floor must itself exclude every release with a known advisory: `Pillow>=13.0` is the first with none, and `tests/test_dependency_floors.py` holds it there.

`requirements/audit.txt` is a compiled, audit-only pin of those ranges so the dependency scanner has concrete versions to check. Nothing installs from it. `make audit-lock` resolves the newest release each range admits (`uv pip compile --upgrade`), so run it whenever `[project].dependencies` changes and before trusting a clean `make audit`: a stale compile is a stale audit.

What builds the artifacts is pinned by the commit, not chosen at build time. `requirements/build.txt` pins `build`, `hatchling` and their dependencies with hashes, compiled from `requirements/build.in` by `make build-lock`. `make build`, `make release` and `make test` install it with `--require-hashes` and build without an isolated environment, so `[build-system].requires` is never resolved from the network. The test and build image `TAIL_IMAGE` is pinned by digest in one `override` definition; the Makefile comment beside it says how to move it. `make build-pins`, a leg of `make check`, asks make itself what it will use: it reads the database of the make that runs it (`make -qp` on a goal given its own empty rule, so none of the Makefile's recipes runs) and fails when a `GNUmakefile`, another makefile, a make flag set in the Makefile, `.IGNORE`, `.ONESHELL`, `.POSIX` or another shell would change how recipes run, and unless `TAIL_IMAGE`, `PIN_BUILD_TOOLS`, `BUILD_ARTIFACTS` and `CHECKOUT` each have one setting, the Makefile's own `override`, with no target- or pattern-specific setting; unless the recipes make runs for `build` and `test` are `scripts/build-pins/build.recipe` and `test.recipe`; and unless the release builds through `BUILD_ARTIFACTS` alone. Changing either recipe on purpose means updating its `.recipe` file in the same commit. Unlike `audit.txt` this is an install input, and `make audit` scans it too. To take a newer build tool, run `make build-lock`, then `make test` and `make build`, and commit the result.

## Releases

Versions are SemVer, and the `VERSION` file is the only place the number appears — `pyproject.toml` reads it, and `__version__` derives from installed metadata.

A release is a tag **plus** a release object: `make release` runs the gate, builds the artifacts, creates the annotated `v<VERSION>` tag, pushes, and publishes the GitHub Release with that version's changelog section as the notes and the sdist and wheel attached. A red gate ships only as the fleet's release gate allows: when only the guard legs (`lint`, `mypy`, `arch`, `audit`) failed and every red is recorded under `### Known reds` in that version's changelog entry with its issue and why it is not fixable here (`scripts/release-known-reds.py` judges it against the clone's guard status); the release skill says how a red is approved. It takes no arguments and runs on Linux only, from a clean `main` in the main checkout, not a linked worktree, that is not behind `origin`: `scripts/release-preflight.sh` reads how make was started from `/proc`, and refuses any argument (`make -n release` is the dry run), and anything in the environment that would steer make, git, gh or docker. `Makefile.local` may set only `LUX_REGISTRY` and `HEAVY_*`, to plain words. It checks that every tracked file on disk matches `HEAD` byte for byte, so an eol setting, `autocrlf` or a filter must be off, that git would tag as the fleet account, because the tag publishes its tagger, and that nothing changes whom git or gh trust over TLS for github.com. A proxy is fine while TLS is untouched. Every line that talks to GitHub or makes the tag runs with only the environment `scripts/release-run.sh` names, so to pass another variable to git, gh or the pre-push hook, add it there. Origin must be https for both fetch and push, because `~/.ssh/config` can redirect ssh, and git is offered only gh's token: any credential helper in config is cleared for those lines, and a `~/.netrc` naming github.com, a `credential.*.username`, `core.askPass` or an `http.extraHeader` for github.com is refused, so `gh auth login` is what signs a release in, and gh must be signed in to github.com as `luxardolabs`. `VERSION` must be above the newest `v*` tag, and `hooks/pre-push` executable. The artifacts' checksums are recorded at the build, and before the tag they are copied to a private directory and checked there, so the upload is what was built. No refusal prints a value it was given. `core.hooksPath` must be `hooks`, which must hold only committed files. `TMPDIR`, if set, must be absolute. The gate runs in a fresh clone of the commit, holding its raw bytes (`scripts/release-clone.sh`), so no ignored file can steer it, and the artifacts are built from a raw export of the same commit. The clone also receives what the guards read from the checkout and no commit holds: origin's URL, `core.hooksPath`, the reflog, the hook heartbeat and `Makefile.local`. The ordered ritual is `.claude/skills/release/SKILL.md`; what shipped in each version is [`CHANGELOG.md`](../CHANGELOG.md).

## Contributing

1. Fork the repository
1. Create a feature branch
1. Add tests for new functionality
1. Run `make format`, then `make check` — both must be clean (they need the private guard registry; without access to it, say so in the pull request and a maintainer runs the gate)
1. Update the docs your change touches, and bump the "last grounded" marker on each page you edit
1. Submit a pull request
