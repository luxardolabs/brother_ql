# =============================================================================
# brother_ql — Brother QL label-printer library (a luxardolabs fork of pklaus/brother_ql)
#
# Fleet quality Makefile. See:
#   luxarch --doc FLEET-MAKEFILE-STANDARD       (gate composition, pins, guard-upgrade)
#   luxarch --doc FLEET-ONBOARDING-STANDARD     (what "onboarded" means — all three guards)
#   luxarch --doc FLEET-BUILD-DEPLOY-STANDARD   (everything in Docker, Makefile.local, VERSION)
#   luxarch --doc FLEET-STATUS                  (make status — the committed guard-status files)
#   luxarch --doc FLEET-LAYOUT-STANDARD         (library = src/<package>/)
#   luxlint --doc ONBOARDING · luxaudit --doc ONBOARDING
#
# HARD RULE — everything runs in Docker, no local .venv. Lint, type-check, test, audit and
# build are every one a `docker run`. A .venv is at most an editor convenience; it is
# gitignored and is NEVER how a check passes.
#
# brother_ql is a LIBRARY, not a deployed application: it is pip-installed and imported,
# it ships no service and no container image. So this Makefile deliberately carries NO
# deploy targets (dev-build-push, release, prod-sync, prod-deploy). Its single version
# source of truth is the VERSION file: pyproject reads it via hatchling
# ([tool.hatch.version]) and `brother_ql.__version__` derives it from the installed
# metadata — no other file carries the literal (luxarch repo.version_single_source).
# =============================================================================

.DEFAULT_GOAL := help

# ── Site-local config (FLEET-BUILD-DEPLOY-STANDARD, "Per-repo Makefile convention") ──
# The UNIVERSAL rule, public or private, no per-repo branching: every site/internal
# value — the private registry host above all — lives in a GITIGNORED Makefile.local.
# The committed Makefile references only the variable. Makefile.local.example is the
# committed template. This keeps the internal registry hostname out of git permanently,
# so this repo flipping public later needs no scrub.
# ORDER MATTERS: include FIRST, then default. `LUX_REGISTRY ?=` *defines* the variable
# (as empty), after which a `?=` inside Makefile.local is a silent no-op and the host
# never arrives — the skip branch then fires even though Makefile.local is present.
# Including first leaves it genuinely undefined, so Makefile.local's `?=` binds and this
# line is the fallback for a clean clone that has no Makefile.local at all.
-include Makefile.local
LUX_REGISTRY ?=

# ── Guard pins ───────────────────────────────────────────────────────────────────────
# Each guard is pinned to a SPECIFIC version (FLEET-MAKEFILE-STANDARD): reproducible, and
# you know which `--new-rules --since` to read. `make guard-version-check` FAILS when a pin
# trails the published :latest (it is the first step of `make check`), and
# `make guard-upgrade` bumps every pin and prints what newly bites. Keep the `:=` form —
# guard-upgrade's sed rewrites exactly these three lines.
LUXARCH_VERSION  := 0.172.1
LUXLINT_VERSION  := 0.52.1
LUXAUDIT_VERSION := 0.6.1

LUXARCH_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxarch:$(LUXARCH_VERSION)
LUXLINT_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxlint:$(LUXLINT_VERSION)
LUXAUDIT_IMAGE ?= $(LUX_REGISTRY)/luxardolabs/luxaudit:$(LUXAUDIT_VERSION)

# Every guard is mount-only and read-only on /repo.
GUARD_RUN := docker run --rm -v $(PWD):/repo

# The test/build base. Matches requires-python (>=3.14) and .luxlint.toml [python].target,
# so the suite runs on the interpreter the code targets (luxarch repo.python_version_consistent).
TAIL_IMAGE ?= python:3.14-slim

# Keep files written by containers owned by the repo owner, not root.
REPO_UID := $(shell id -u)
REPO_GID := $(shell id -g)

# A clean clone without registry access still has a working Makefile: every guard-backed
# target skips with a message instead of failing on an unreachable pull.
SKIP_NO_REGISTRY = if [ -z "$(LUX_REGISTRY)" ]; then echo "$@: LUX_REGISTRY unset (see Makefile.local.example) — skipping"; exit 0; fi

##@ Gates

# THE fleet gate, in the canonical order (FLEET-MAKEFILE-STANDARD): pin drift → honesty →
# ruff → types → tests → architecture → dependency CVEs → secrets. It is a prerequisite
# list, so make stops at the FIRST failing step — loudly, never silently. To see every
# step's verdict past a red, run `make -k check`; for the full phase-ordered red board,
# `docker run --rm -v $(PWD):/repo $(LUXARCH_IMAGE) --plan`.
check: guard-version-check honest lint mypy test arch audit gitleaks ## THE fleet gate — every guard, in order

##@ Quality

honest: ## HONESTY gate — fails iff a rule family scanned nothing or the mypy run is dishonest (never on reds)
	@set +e; $(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXARCH_IMAGE) --assert-scans >/dev/null; scans=$$?; \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --preflight; preflight=$$?; \
	if [ $$scans -ne 0 ] || [ $$preflight -ne 0 ]; then \
	  echo "honest FAILED (luxarch --assert-scans=$$scans luxlint --preflight=$$preflight)"; exit 1; \
	fi

lint: ## luxlint — canonical ruff + format + markdown + repo rules (mount-only)
	@$(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXLINT_IMAGE)

# The type leg is mount-only: the fleet's typed dependency set is baked into the luxlint
# image, so there is no in-repo tail and nothing is pip-installed (luxlint --doc ONBOARDING §3).
mypy: ## luxlint --mypy — canonical mypy config + [mypy].baseline ratchet (mount-only)
	@$(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --mypy

# TAIL AUDIT (luxarch --doc ONBOARDING, "Required in-repo tails"): brother_ql has NO
# required in-repo tail. It does not use import-linter, and the `library` rule pack is
# entirely static, so luxarch's mount-only run covers it.
arch: ## Architecture conformance via luxarch (pinned; mount-only; reads .luxarch.toml)
	@$(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXARCH_IMAGE)

audit: ## Dependency CVEs via luxaudit (pinned; mount-only; live advisory feed; reads .luxaudit.toml)
	@$(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXAUDIT_IMAGE)

# The canonical fixer (FLEET-ONBOARDING-STANDARD §2.1): ruff safe fixes + ruff format with
# the CHECKED config, and mdformat-gfm for Markdown (GFM tables survive). It prints which
# rules it applied, so any surprising rewrite is attributable. Never a bare `ruff format`
# or `mdformat` — either one formats with a config the gate does not check.
format: ## Apply every canonical formatter in place (luxlint --format) — writes to host
	@$(SKIP_NO_REGISTRY); \
	docker run --rm --user $(REPO_UID):$(REPO_GID) -v $(PWD):/repo $(LUXLINT_IMAGE) --format

# The canonical pytest config is emitted by luxlint and run in the tail image — a local
# pytest config is a red (test.no_local_pytest_config).
#
# src-layout discipline, and the whole reason a library uses src/: the package is
# installed NON-editable first, so `import brother_ql` resolves to site-packages. The
# repo root carries no importable `brother_ql/` directory to shadow it, so the suite is
# provably exercising the INSTALLED artifact — a packaging bug (a missing module, absent
# package-data) fails the tests instead of hiding behind a repo-relative import.
#
# pytest-asyncio is required, not optional: the canonical config sets `asyncio_mode =
# auto` under `--strict-config`, so without the plugin pytest aborts on an unknown ini
# key (exit 4, "no tests ran") — which reads as a pass in a careless tail.
test: ## pytest against the INSTALLED package, with luxlint's canonical pytest config
	@set +e; $(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --emit-config pytest > .luxlint.pytest.ini; \
	docker run --rm -v $(PWD):/repo -w /repo $(TAIL_IMAGE) \
	  sh -c 'pip install -q --root-user-action=ignore pytest pytest-asyncio >/dev/null \
	         && pip install -q --root-user-action=ignore . >/dev/null \
	         && pytest -c .luxlint.pytest.ini'; rc=$$?; \
	rm -f .luxlint.pytest.ini; \
	exit $$rc

##@ Secrets

# gitleaks (luxlint --doc ONBOARDING §4a). The config is FLEET-OWNED and emitted at scan
# time, NEVER committed — it carries the org denylist (internal infra domain / retired
# identity), so a committed copy would print the very strings it forbids.
# `secret.no_local_gitleaks_config` reds a repo that carries its own .gitleaks.toml.
# Per-repo known-non-secret carve-outs belong in .luxlint.toml [gitleaks].allow.
#
# Both targets fire on their own via the committed git hooks in hooks/ (core.hooksPath,
# installed by `luxlint --emit-hooks | sh`): pre-commit runs gitleaks-staged, pre-push runs
# gitleaks. That is the belt; `make check` is the braces.
GITLEAKS_IMAGE ?= ghcr.io/gitleaks/gitleaks:latest

gitleaks: ## Scan the full history for secrets + org-denylist strings (emitted fleet config)
	@set +e; $(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --emit-config gitleaks > .luxlint.gitleaks.toml; \
	docker run --rm -v $(PWD):/repo -w /repo $(GITLEAKS_IMAGE) \
	  detect --source /repo --config /repo/.luxlint.gitleaks.toml --redact -v; rc=$$?; \
	rm -f .luxlint.gitleaks.toml; \
	exit $$rc

gitleaks-staged: ## Pre-commit scan of STAGED changes (the pre-commit hook runs this)
	@set +e; $(SKIP_NO_REGISTRY); \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --emit-config gitleaks > .luxlint.gitleaks.toml; \
	docker run --rm -v $(PWD):/repo -w /repo $(GITLEAKS_IMAGE) \
	  protect --staged --source /repo --config /repo/.luxlint.gitleaks.toml --redact -v; rc=$$?; \
	rm -f .luxlint.gitleaks.toml; \
	exit $$rc

##@ Build

build: ## Build the sdist + wheel in Docker (hatchling; version from VERSION)
	docker run --rm --user $(REPO_UID):$(REPO_GID) -v $(PWD):/repo -w /repo $(TAIL_IMAGE) \
	  sh -c 'pip install -q --root-user-action=ignore build >/dev/null && python -m build --outdir dist'

##@ Meta

# FLEET-STATUS: the fleet reads these committed files instead of re-running every guard.
# The guards stay read-only on /repo, so this RECIPE stamps the commit + time and writes.
# `|| true` because --json exits non-zero on a red repo (the verdict is IN the JSON);
# `set -e` so a failed stamp (empty/invalid --json) aborts instead of claiming "wrote".
STAMP = python3 -c 'import json,sys,os; d=json.load(open(sys.argv[1])); d["commit"]=os.environ["SHA"]; d["generated_at"]=os.environ["TS"]; json.dump(d,open(sys.argv[2],"w"),indent=2)'

status: ## Regenerate committed guard-status files (.lux*-status.json) — commit them
	@$(SKIP_NO_REGISTRY); \
	set -e; export SHA=$$(git rev-parse HEAD) TS=$$(date -u +%FT%TZ); \
	$(GUARD_RUN) $(LUXLINT_IMAGE)  --json > /tmp/lux.json || true; $(STAMP) /tmp/lux.json .luxlint-status.json; \
	$(GUARD_RUN) $(LUXARCH_IMAGE)  --json > /tmp/lux.json || true; $(STAMP) /tmp/lux.json .luxarch-status.json; \
	$(GUARD_RUN) $(LUXAUDIT_IMAGE) --json > /tmp/lux.json || true; $(STAMP) /tmp/lux.json .luxaudit-status.json; \
	echo "wrote .lux*-status.json at $$SHA — commit them"

# `docker pull` FIRST (per every guard's ONBOARDING): `docker run …:latest --version` alone
# reads the LOCALLY-CACHED :latest, so a box that pulled weeks ago "confirms latest" while
# actually behind. Pulling re-points the local tag at the registry's current one.
guard-version-check: ## FATAL: fail if any guard pin is behind the published :latest (pulls :latest FIRST)
	@$(SKIP_NO_REGISTRY); rc=0; \
	for pair in "luxarch $(LUXARCH_VERSION)" "luxlint $(LUXLINT_VERSION)" "luxaudit $(LUXAUDIT_VERSION)"; do \
	  set -- $$pair; g=$$1; pin=$$2; img=$(LUX_REGISTRY)/luxardolabs/$$g; \
	  docker pull -q $$img:latest >/dev/null 2>&1 || true; \
	  latest=$$(docker run --rm $$img:latest --version 2>/dev/null | awk '{print $$2}'); \
	  if [ -n "$$latest" ] && [ "$$latest" != "$$pin" ]; then \
	    printf '✗ %s pinned %s, latest %s — behind. Preview: --new-rules --since %s; then make guard-upgrade\n' "$$g" "$$pin" "$$latest" "$$pin"; rc=1; \
	  fi; \
	done; exit $$rc

# The sed is whitespace-tolerant (the pin block aligns names with two spaces) and every
# substitution is re-read: a pin that did not move exits 1 rather than claiming "bumped".
guard-upgrade: ## Bump every guard pin to the published :latest (prints what newly bites)
	@$(SKIP_NO_REGISTRY); \
	for g in luxarch luxlint luxaudit; do \
	  docker pull -q $(LUX_REGISTRY)/luxardolabs/$$g:latest >/dev/null 2>&1 || true; \
	  latest=$$(docker run --rm $(LUX_REGISTRY)/luxardolabs/$$g:latest --version 2>/dev/null | awk '{print $$2}'); \
	  var=$$(echo $$g | tr a-z A-Z)_VERSION; \
	  old=$$(sed -n -E "s/^$$var[[:space:]]*:=[[:space:]]*//p" Makefile); \
	  if [ -z "$$old" ]; then echo "!! no $$var pin found in Makefile — NOT bumped"; continue; fi; \
	  if [ -z "$$latest" ]; then echo "!! could not read $$g:latest — $$var left at $$old"; continue; fi; \
	  sed -i -E "s|^($$var[[:space:]]*:=[[:space:]]*).*|\\1$$latest|" Makefile; \
	  new=$$(sed -n -E "s/^$$var[[:space:]]*:=[[:space:]]*//p" Makefile); \
	  if [ "$$new" != "$$latest" ]; then echo "!! $$var did NOT change (still $$new)"; exit 1; fi; \
	  if [ "$$old" != "$$latest" ]; then echo "$$var $$old -> $$latest"; bumped=1; fi; \
	  [ "$$g" = luxarch ] && [ "$$old" != "$$latest" ] && $(GUARD_RUN) $(LUX_REGISTRY)/luxardolabs/luxarch:$$latest --new-rules --since $$old || true; \
	done; [ -n "$$bumped" ] && echo "pins bumped — re-run make check" || echo "all pins already at latest"

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nbrother_ql — make targets\n"} \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

.PHONY: check honest lint mypy arch audit format test gitleaks gitleaks-staged build status guard-version-check guard-upgrade help
