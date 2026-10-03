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
# it ships no service and no container image. So this Makefile carries NO deploy targets
# (dev-build-push, prod-sync, prod-deploy), and `release` is the LIBRARY ritual — tag,
# artifacts, GitHub Release — not an image build+deploy. Its single version source of
# truth is the VERSION file: pyproject reads it via hatchling ([tool.hatch.version]) and
# `brother_ql.__version__` derives it from the installed metadata — no other file carries
# the literal (luxarch repo.version_single_source).
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
LUXARCH_VERSION  := 0.250.1
LUXLINT_VERSION  := 0.60.1
LUXAUDIT_VERSION := 0.13.0

LUXARCH_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxarch:$(LUXARCH_VERSION)
LUXLINT_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxlint:$(LUXLINT_VERSION)
LUXAUDIT_IMAGE ?= $(LUX_REGISTRY)/luxardolabs/luxaudit:$(LUXAUDIT_VERSION)

# The names the verbatim luxarch assets (gitleaks, guard-upgrade) reference.
REGISTRY = $(LUX_REGISTRY)
LUXLINT  = $(LUXLINT_IMAGE)

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

# FLEET-ONBOARDING-STANDARD §5: proves the repo is ONBOARDED (all three guards wired and
# honest, privacy wired, history clean). It never judges red/green: that is `check`.
onboard-check: ## Prove the repo is onboarded: all three guards on + honest + privacy wired (NOT green)
	@set +e; $(SKIP_NO_REGISTRY); fail=0; \
	$(GUARD_RUN) $(LUXARCH_IMAGE)  --version      >/dev/null || { echo "luxarch not wired"; fail=1; }; \
	$(GUARD_RUN) $(LUXARCH_IMAGE)  --assert-scans >/dev/null 2>&1 || { echo "luxarch: a rule family scanned NOTHING (hollow green)"; fail=1; }; \
	$(GUARD_RUN) $(LUXLINT_IMAGE)  --preflight    >/dev/null || { echo "mypy tail NOT honest (luxlint --preflight)"; fail=1; }; \
	$(GUARD_RUN) $(LUXAUDIT_IMAGE) 2>&1 | grep -q "scan could not run" && { echo "luxaudit can't scan — supply-chain blind"; fail=1; }; \
	$(GUARD_RUN) $(LUXLINT_IMAGE)  --version      >/dev/null || { echo "luxlint not wired"; fail=1; }; \
	$(GUARD_RUN) $(LUXAUDIT_IMAGE) --version      >/dev/null || { echo "luxaudit not wired"; fail=1; }; \
	[ -f hooks/pre-commit ] || { echo "secret git-hooks NOT wired (luxlint --emit-hooks | sh, commit hooks/)"; fail=1; }; \
	[ "$$(git config core.hooksPath)" = hooks ] || { echo "core.hooksPath is not hooks/ — the secret hooks never fire"; fail=1; }; \
	[ ! -d .github/workflows ] || { echo "public CI present — make check is the sole gate (remove .github/workflows)"; fail=1; }; \
	! sed 's/#.*//' Makefile | grep -qE '^[[:space:]]+[^#]*\bruff[[:space:]]+format\b' || { echo "Makefile runs a bare 'ruff format' — use 'luxlint --format'"; fail=1; }; \
	$(MAKE) -s gitleaks >/dev/null 2>&1 || { echo "gitleaks failed over FULL history (secrets or a non-fleet commit identity) — scrub before onboarding is complete"; fail=1; }; \
	[ $$fail -eq 0 ] && echo "onboard-check: all three guards on + honest + privacy wired + history clean ✓" || { echo "onboard-check FAILED"; exit 1; }

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

# The audit-only pinned set luxaudit scans (luxaudit --doc DEPENDENCY-DECLARATION, "A library
# with dependency RANGES and no lockfile"). brother_ql ships ranges on purpose — pinning is
# the consuming application's job — so this compiles today's resolution of those ranges.
# A REPORTING artifact, never an install or deploy input. Rerun whenever
# [project].dependencies changes: a stale compile is a stale audit.
#
# Runs as the repo owner (like format/build), so the compiled file is never root-owned;
# HOME=/tmp gives the user-level uv install and its cache somewhere writable.
audit-lock: ## Recompile requirements/audit.txt from the pyproject ranges (audit-only; rerun when deps change)
	docker run --rm --user $(REPO_UID):$(REPO_GID) -e HOME=/tmp -v $(PWD):/repo -w /repo $(TAIL_IMAGE) \
	  sh -c 'pip install -q --user --root-user-action=ignore uv >/dev/null \
	         && mkdir -p requirements \
	         && python -m uv pip compile pyproject.toml -o requirements/audit.txt'

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
# luxarch:gitleaks asset v9 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit gitleaks`.
# ── The privacy gate: BOTH surfaces ─────────────────────────────────────────────────────────────
# Emitted by `luxarch --emit gitleaks`. Drop in verbatim.
#
# `gitleaks` scans DIFF CONTENT. A commit's author/committer address lives in the commit object
# HEADER and never appears in a patch, so no content rule can ever match it — it is a surface the
# scanner does not read. A repo reported `no leaks found` over 963 commits while 29 of them carried a
# personal address in both the author and committer fields, and it would have reported exactly the
# same thing after the scrub: identical output, opposite truth. Measured across the fleet, EIGHT
# repos carry a personal address in history and two of them are PUBLIC (LUXTASTE-339).
#
# FLEET-ONBOARDING-STANDARD §2 uses one of those very addresses as its worked example of a leak the
# full-history scan exists to catch. The standard named the leak and the gate could not see it.

# Commit identities this repo accepts. The fleet account's `users.noreply.github.com` address, plus
# GitHub's own web-UI committer. Widen ONLY for a real outside contributor, with a comment saying who.
# NOT for the org account's real address: a role mailbox in commit metadata is published with every
# clone exactly like a personal one (six fleet repos carried it, one PUBLIC; OPENCLAIM-359). Its
# omission here is the policy, not an oversight: the answer is the scrub printed below, and the
# repo's agent performs it once the OWNER approves the force-push.
# Anchored on the CLOSING BRACKET, because the compared line is `Name <email>` — not a bare
# address. The first cut allowed `^noreply@github.com$$`, which can NEVER match a
# `Name <email>` line, so the GitHub web-UI identity was silently DENIED and the canonical
# recipe would have refused on any repo carrying a web-UI commit. Measured across the fleet: it
# denied 4 of 6 distinct identity lines instead of the 3 real offenders (LUXTRMNL-21).
# It was missed because the only repo it was tested on has no web-UI commits, so the broken
# branch never ran. The bracket also closes a substring hole: unanchored,
# `<x@users.noreply.github.com.attacker.test>` would have been allowed.
GIT_IDENTITY_OK ?= <[^>]*users\.noreply\.github\.com>$$|<noreply@github\.com>$$

# The secret scanner, PINNED and MIRRORED in the fleet registry (LUXASIF-29). The fleet bans a moving tag
# everywhere it can see one, and this used to ship `ghcr.io/gitleaks/gitleaks:latest` inside the asset every
# repo adopts verbatim: the privacy gate could not run with ghcr unreachable or the local copy pruned, and
# nothing recorded which scanner said "no leaks found". New detection rules still arrive, through the fleet's
# own mechanism: luxarch bumps this pin in a release, and `repo.emitted_assets_current` tells you to re-emit.
# v5: the HOST is never written here (LUXSTATS-115). v4 inlined the private registry, so dropping
# this asset in "verbatim" put the host into a committed Makefile, and on a public repo the fleet's
# own gitleaks disclosure tier refused the commit. The mirror lives beside the guards, so the ref is
# derived from wherever this repo already pulls luxlint (`$(LUXLINT)`, which the scan below needs
# anyway). It works whichever variable holds your guard registry (REGISTRY, LUXARCH_REGISTRY, …).
# Recursive `=` so it resolves at use, whatever order LUXLINT is defined in.
# v9: PINNED BY DIGEST, and buildable off-network. The digest is the scanner's identity; the registry is
# only where it is fetched from. Beside a registry-qualified `$(LUXLINT)` it pulls the fleet mirror; with
# a local guard build (`luxlint:local`, on a machine with no access to the fleet registry, such as the
# GTM laptop) it pulls the public image. v8 derived `./gitleaks:…` there, an unpullable reference, so the
# privacy gate could not run at all. The mirror and the public image share the digest, so both
# resolve to the same bits, and a tampered or re-tagged copy fails the pull instead of scanning.
GITLEAKS_IMAGE = $(if $(findstring /,$(LUXLINT)),$(dir $(LUXLINT)),zricethezav/)gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f

gitleaks: ## secret scan over FULL HISTORY + the commit-identity pass (the hooks cover commit/push)
	@set -e; C=$$(mktemp); trap 'rm -f "$$C"' EXIT INT TERM; \
	docker run --rm -v $(PWD):/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	docker run --rm -v $(PWD):/repo -v "$$C":/gl.toml:ro -w /repo \
	  $(GITLEAKS_IMAGE) git /repo -c /gl.toml --redact -v
	@# The identity pass — the half gitleaks structurally cannot do. Cheap: one `git log`.
	@# Walks what THIS repo publishes (branches, tags, HEAD), NOT `--all`: a remote-tracking ref caches the
	@# remote's state, which during a scrub is by definition the un-rewritten history you are about to
	@# force-push over — `--all` refused the verified fix, and any `git fetch` re-armed it (BOUTIQUE-577).
	@bad=$$(git log --branches --tags HEAD --pretty='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort -u \
	  | grep -vE '$(GIT_IDENTITY_OK)' || true); \
	if [ -n "$$bad" ]; then \
	  echo "REFUSING: a non-fleet identity appears in commit METADATA (author/committer):"; \
	  echo "$$bad" | sed 's/^/    /'; \
	  echo "gitleaks cannot see this — it scans diffs, not commit headers, so it reported no leaks."; \
	  echo "An address here is attached to every affected commit forever, not to one line of one file."; \
	  echo "Scrub per FLEET-ONBOARDING-STANDARD §2: mirror backup -> git filter-repo -> re-verify with"; \
	  echo "  git log --branches --tags HEAD --pretty='%an <%ae>%n%cn <%ce>' | sort -u"; \
	  echo "-> ask the OWNER to approve the force-push, then do it yourself. Never force-push unapproved."; \
	  exit 1; \
	fi

# v6: the STAGED scan the commit hook calls (`hooks/pre-commit` → `make gitleaks-staged`) is part of the
# asset now. v5 shipped only the full-history half, so 9 of 10 adopting repos hand-wrote this target
# and the tenth had none, leaving its pre-commit hook pointing at a missing recipe. If your Makefile
# carries its own `gitleaks-staged`, delete it when you re-emit: this one replaces it.
# v7: `-w /repo` is LOAD-BEARING. Without it git runs outside the repo, falls back to `git diff
# --no-index`, rejects `--staged`, and gitleaks EXITS 0: v6 let a staged secret through while printing
# a git error (measured on a planted GitHub token: v6 exit 0, v7 "leaks found: 1" exit 1).
# v8: the denylist goes to a PER-RUN `mktemp` file, removed on exit (LUXHELIX-128). v7 wrote a fixed
# `/tmp/gl.toml` that outlived the run: on a host where commit and push run as different users, the
# next user's redirect was refused (`fs.protected_regular=1`, the Fedora default, blocks O_CREAT on
# another user's file in sticky /tmp even for root), so the privacy gate failed every commit or push
# after a user switch (2 of 2 measured). Two repos scanning at once also shared one file, so one could
# scan with the other's carve-outs. The full-history scan now also passes `-w /repo`, like the staged one.
gitleaks-staged: ## secret scan of the STAGED changes (run by hooks/pre-commit)
	@set -e; C=$$(mktemp); trap 'rm -f "$$C"' EXIT INT TERM; \
	docker run --rm -v $(PWD):/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	docker run --rm -v $(PWD):/repo -v "$$C":/gl.toml:ro -w /repo \
	  $(GITLEAKS_IMAGE) protect --staged /repo -c /gl.toml --redact -v

##@ Release

# brother_ql is a LIBRARY, so it releases the library way (luxarch --doc
# FLEET-RELEASE-PROCESS's carve-out, --doc FLEET-BUILD-DEPLOY-STANDARD "Version scheme"):
# SemVer in the VERSION file, a root CHANGELOG.md holding the content, an annotated
# v$(VERSION) tag, and a GitHub Release carrying that version's notes. A release is a TAG
# PLUS A RELEASE OBJECT — a bare tag leaves /releases empty and the notes unused. The
# ordered ritual (including the LuxPM mirror) is .claude/skills/release/SKILL.md.
RELEASE_VERSION := $(shell cat VERSION 2>/dev/null)

# One shell per step, and `$(MAKE)` on lines of its own: make EXECUTES any line that
# mentions $(MAKE) even under `make -n`, so a single-line recipe would really tag, push and
# publish on a dry run (and luxarch, which judges the recipe by `make -n`, could not read it).
release: ## Tag, push, build and publish the GitHub Release for the VERSION file's version
	@set -e; \
	[ -n "$(RELEASE_VERSION)" ] || { echo "release: VERSION is empty"; exit 1; }; \
	[ -z "$$(git status --porcelain)" ] || { echo "release: working tree is dirty — commit first"; exit 1; }; \
	grep -q "^## $(RELEASE_VERSION) " CHANGELOG.md || { echo "release: CHANGELOG.md has no '## $(RELEASE_VERSION)' section"; exit 1; }; \
	if git rev-parse -q --verify refs/tags/v$(RELEASE_VERSION) >/dev/null; then echo "release: tag v$(RELEASE_VERSION) already exists"; exit 1; fi
	@$(MAKE) --no-print-directory check
	@rm -rf dist
	@$(MAKE) --no-print-directory build
	@set -e; N=$$(mktemp); trap 'rm -f "$$N"' EXIT INT TERM; \
	awk '/^## $(RELEASE_VERSION) /{f=1;next} /^## /{f=0} f' CHANGELOG.md > "$$N"; \
	git tag -a v$(RELEASE_VERSION) -m "v$(RELEASE_VERSION)"; \
	git push origin HEAD; \
	git push origin v$(RELEASE_VERSION); \
	gh release create v$(RELEASE_VERSION) --title "$(RELEASE_VERSION)" --notes-file "$$N" dist/*; \
	echo "released v$(RELEASE_VERSION) — now mirror it to LuxPM (see .claude/skills/release/SKILL.md)"

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
	set -e; C=$$(mktemp); trap 'rm -f "$$C"' EXIT INT TERM; \
	export SHA=$$(git rev-parse HEAD) TS=$$(date -u +%FT%TZ); \
	$(GUARD_RUN) $(LUXLINT_IMAGE)  --json > "$$C" || true; $(STAMP) "$$C" .luxlint-status.json; \
	$(GUARD_RUN) -e LUXARCH_STATUS_WRITE=1 $(LUXARCH_IMAGE) --json > "$$C" || true; $(STAMP) "$$C" .luxarch-status.json; \
	$(GUARD_RUN) $(LUXAUDIT_IMAGE) --json > "$$C" || true; $(STAMP) "$$C" .luxaudit-status.json; \
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

# luxarch:guard-upgrade asset v1 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit guard-upgrade`.
guard-upgrade:  ## Bump every guard pin to the published latest (prints what newly bites)
	@for g in luxarch luxlint luxaudit; do \
	  docker pull -q $(REGISTRY)/luxardolabs/$$g:latest >/dev/null 2>&1 || true; \
	  latest=$$(docker run --rm $(REGISTRY)/luxardolabs/$$g:latest --version 2>/dev/null | awk '{print $$2}'); \
	  var=$$(echo $$g | tr a-z A-Z)_VERSION; \
	  old=$$(sed -n -E "s/^$$var[[:space:]]*:=[[:space:]]*//p" Makefile); \
	  if [ -z "$$old" ]; then echo "!! no $$var pin found in Makefile — NOT bumped"; continue; fi; \
	  if [ -z "$$latest" ]; then echo "!! could not read $$g:latest — $$var left at $$old"; continue; fi; \
	  checked=1; \
	  sed -i -E "s|^($$var[[:space:]]*:=[[:space:]]*).*|\\1$$latest|" Makefile; \
	  new=$$(sed -n -E "s/^$$var[[:space:]]*:=[[:space:]]*//p" Makefile); \
	  if [ "$$new" != "$$latest" ]; then echo "!! $$var did NOT change (still $$new)"; exit 1; fi; \
	  if [ "$$old" != "$$latest" ]; then echo "$$var $$old -> $$latest"; bumped=1; fi; \
	  [ "$$g" = luxarch ] && [ "$$old" != "$$latest" ] && docker run --rm -v $(PWD):/repo $(REGISTRY)/luxardolabs/luxarch:$$latest --new-rules --since $$old || true; \
	done; \
	if [ -n "$$bumped" ]; then echo "pins bumped — re-run make check"; \
	elif [ -n "$$checked" ]; then echo "all pins already at latest"; \
	else echo "!! could not reach the registry — NO pin was checked; currency NOT established"; exit 1; fi

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nbrother_ql — make targets\n"} \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

.PHONY: check onboard-check honest lint mypy arch audit audit-lock format test gitleaks gitleaks-staged release build status guard-version-check guard-upgrade help
