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
LUXARCH_VERSION  := 0.327.0
LUXLINT_VERSION  := 0.70.0
LUXAUDIT_VERSION := 0.15.0

LUXARCH_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxarch:$(LUXARCH_VERSION)
LUXLINT_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxlint:$(LUXLINT_VERSION)
LUXAUDIT_IMAGE ?= $(LUX_REGISTRY)/luxardolabs/luxaudit:$(LUXAUDIT_VERSION)

# The names the verbatim luxarch assets (gitleaks, guard-upgrade) reference.
REGISTRY = $(LUX_REGISTRY)
LUXLINT  = $(LUXLINT_IMAGE)

# luxarch:guard-run asset v1 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit guard-run`.
# ── GUARD_RUN: how every guard sees this checkout ───────────────────────────────────────────────────
# Emitted by `luxarch --emit guard-run`; paste it above the targets that run the guards (`status:`, and
# `arch:` / `lint:` / `audit:` where they run a guard image).
#
# Agents work in linked worktrees (`.claude/worktrees/<ISSUE-KEY>`). A worktree's `.git` is a file
# pointing into the MAIN checkout's `.git`, and the hooks keep their session state (the heartbeat) in
# the main checkout's `.claude/`. A guard that mounts only the worktree at /repo can read neither:
# every rule that reads git or the heartbeat goes INERT there, and `make status` run in a worktree
# commits those INERT verdicts as the repo's record. So GUARD_RUN also mounts the main checkout,
# read-only, at its own path, where the worktree's `.git` file points. In the main checkout itself
# there is nothing more to mount. Not covered: a worktree whose `.git` names its gitdir by a RELATIVE
# path (`worktree.useRelativePaths`), which resolves from /repo to somewhere else; its git-reading
# rules stay INERT. Claude Code writes absolute pointers.
GUARD_MAIN := $(shell d=$$(git -C "$(CURDIR)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [ "$$(basename "$$d")" = .git ] && dirname "$$d")
GUARD_RUN = docker run --rm -v "$(CURDIR)":/repo $(if $(filter-out $(CURDIR),$(GUARD_MAIN)),-v "$(GUARD_MAIN)":"$(GUARD_MAIN)":ro)

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
# [project].dependencies changes: a stale compile is a stale audit. `--upgrade` because uv
# otherwise keeps the pins already in the output file, so a rerun never picks up a fixed release.
#
# Runs as the repo owner (like format/build), so the compiled file is never root-owned;
# HOME=/tmp gives the user-level uv install and its cache somewhere writable.
audit-lock: ## Recompile requirements/audit.txt from the pyproject ranges (audit-only; rerun when deps change)
	docker run --rm --user $(REPO_UID):$(REPO_GID) -e HOME=/tmp -v $(PWD):/repo -w /repo $(TAIL_IMAGE) \
	  sh -c 'pip install -q --user --root-user-action=ignore uv >/dev/null \
	         && mkdir -p requirements \
	         && python -m uv pip compile --upgrade pyproject.toml -o requirements/audit.txt'

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
#
# Coverage is the library recipe from `luxlint --playbook test-suite`: measure (branch
# coverage under sysmon, --source the installed package), then feed `coverage report` to
# `--coverage-ratchet` against [test].coverage_min in a SECOND step. Never a pipe: under
# /bin/sh the pipe's status is the ratchet's, so a failing suite would exit 0. A failing
# suite exits with its own status before the ratchet runs; otherwise the ratchet's wins.
#
# Hardened by an adversarial pass, matching `luxarch --emit test-block`:
# - the emitted config must arrive (`|| exit 2`), or pytest silently runs WITHOUT it
#   (no --strict-config, no filterwarnings=error) and passes;
# - the config lives in the run's own temp dir, never the repo root, so two runs in one
#   tree cannot delete each other's config mid-run;
# - the source is mounted read-only with PYTHONDONTWRITEBYTECODE, so nothing lands in it;
# - `coverage report --precision=2`: a whole-percent report rounds 89.5% up to "90%" and
#   passes a floor of 90.
test: ## pytest against the INSTALLED package (canonical config), then the coverage ratchet
	@set +e; $(SKIP_NO_REGISTRY); D=$$(mktemp -d); trap 'rm -rf "$$D"' EXIT INT TERM; \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --emit-config pytest > "$$D/pytest.ini" || exit 2; \
	docker run --rm -v $(PWD):/repo:ro -w /repo -v "$$D":/out -e PYTHONDONTWRITEBYTECODE=1 $(TAIL_IMAGE) \
	  sh -c 'pip install -q --root-user-action=ignore pytest pytest-asyncio coverage >/dev/null \
	         && pip install -q --root-user-action=ignore . >/dev/null \
	         && export COVERAGE_CORE=sysmon COVERAGE_FILE=/out/.coverage \
	         && python -m coverage run --branch --source=brother_ql -m pytest -c /out/pytest.ini --rootdir=/repo -p no:cacheprovider \
	         && python -m coverage report --precision=2 > /out/coverage.txt'; rc=$$?; \
	[ $$rc -eq 0 ] || exit $$rc; \
	c=0; docker run --rm -i -v $(PWD):/repo $(LUXLINT_IMAGE) --coverage-ratchet < "$$D/coverage.txt" > "$$D/ratchet.txt" || c=$$?; \
	sed -n '/coverage ratchet/,$$p' "$$D/ratchet.txt"; exit $$c

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
# luxarch:gitleaks asset v17 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit gitleaks`.
# ── The privacy gate: EVERY surface a commit publishes ──────────────────────────────────────────
# Emitted by `luxarch --emit gitleaks`. Drop in verbatim.
#
# `gitleaks` scans DIFF CONTENT. A commit's author/committer address lives in the commit object
# HEADER and never appears in a patch, so no content rule can ever match it — it is a surface the
# scanner does not read. A repo reported `no leaks found` over 963 commits while 29 of them carried a
# personal address in both the author and committer fields, and it would have reported exactly the
# same thing after the scrub: identical output, opposite truth. Measured across the fleet, EIGHT
# repos carry a personal address in history and two of them are PUBLIC.
#
# v13: the commit MESSAGE is a third surface, and through v12 nothing read it. It is neither a patch
# nor the header, so a message naming an org-denylisted host passed the staged scan, the full-history
# scan and the push hook: seven commits in one public repo, found only when a file repeated the name.
# Every commit and annotated-tag message in history is now scanned with the same config as file
# content, and `gitleaks-commit-msg` scans the message being written (run by hooks/commit-msg).

# Commit identities this repo accepts. The fleet account's `users.noreply.github.com` address, plus
# GitHub's own web-UI committer. Widen ONLY for a real outside contributor, with a comment saying who.
# NOT for the org account's real address: a role mailbox in commit metadata is published with every
# clone exactly like a personal one (six fleet repos carried it, one PUBLIC). Its
# omission here is the policy, not an oversight: the answer is the scrub printed below, and the
# repo's agent performs it once the OWNER approves the force-push.
# Anchored on the CLOSING BRACKET, because the compared line is `Name <email>` — not a bare
# address. The first cut allowed `^noreply@github.com$$`, which can NEVER match a
# `Name <email>` line, so the GitHub web-UI identity was silently DENIED and the canonical
# recipe would have refused on any repo carrying a web-UI commit. Measured across the fleet: it
# denied 4 of 6 distinct identity lines instead of the 3 real offenders.
# It was missed because the only repo it was tested on has no web-UI commits, so the broken
# branch never ran. The bracket also closes a substring hole: unanchored,
# `<x@users.noreply.github.com.attacker.test>` would have been allowed.
# v11: the noreply address is `<local@users.noreply.github.com>`, and the local part has no `@`. v10's
# `<[^>]*users…` admitted `<dev.real@gmail.com.users.noreply.github.com>`, a real address in the clear.
# v12: the fleet ACCOUNT, not any noreply address. v11 accepted `<anyone@users.noreply.github.com>`, so a
# stranger's (or a second account's) noreply committer passed. Measured: the fleet's whole history holds
# exactly two noreply identities, the fleet account and GitHub's web-UI committer.
GIT_IDENTITY_OK ?= <214140984\+luxardolabs@users\.noreply\.github\.com>$$|<noreply@github\.com>$$

# The secret scanner, PINNED and MIRRORED in the fleet registry. The fleet bans a moving tag
# everywhere it can see one, and this used to ship `ghcr.io/gitleaks/gitleaks:latest` inside the asset every
# repo adopts verbatim: the privacy gate could not run with ghcr unreachable or the local copy pruned, and
# nothing recorded which scanner said "no leaks found". New detection rules still arrive, through the fleet's
# own mechanism: luxarch bumps this pin in a release, and `repo.emitted_assets_current` tells you to re-emit.
# v5: the HOST is never written here. v4 inlined the private registry, so dropping
# this asset in "verbatim" put the host into a committed Makefile, and on a public repo the fleet's
# own gitleaks disclosure tier refused the commit. The mirror lives beside the guards, so the ref is
# derived from wherever this repo already pulls luxlint (`$(LUXLINT)`, which the scan below needs
# anyway). It works whichever variable holds your guard registry (REGISTRY, LUXARCH_REGISTRY, …).
# Recursive `=` so it resolves at use, whatever order LUXLINT is defined in.
# v9: PINNED BY DIGEST, and buildable off-network. The digest is the scanner's identity; the registry is
# only where it is fetched from. Beside a registry-qualified `$(LUXLINT)` it pulls the fleet mirror; with
# a local guard build (`luxlint:local`, on a machine with no access to the fleet registry, such as an
# airgapped laptop) it pulls the public image. v8 derived `./gitleaks:…` there, an unpullable reference, so the
# privacy gate could not run at all. The mirror and the public image share the digest, so both
# resolve to the same bits, and a tampered or re-tagged copy fails the pull instead of scanning.
GITLEAKS_IMAGE = $(if $(findstring /,$(LUXLINT)),$(dir $(LUXLINT)),zricethezav/)gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f

# v13: `/repo` is `$(CURDIR)`, this makefile's directory. v1-v12 mounted `$(PWD)`, the CALLER's shell
# directory, so `make -C <repo> gitleaks` run from another repo scanned THAT repo's history with THAT
# repo's config while the identity pass read this one: two repos' answers, reported as this one's.
# v15: a WORKTREE's `.git` is a file naming `<main>/.git/worktrees/<name>`, outside the `/repo` mount, so
# git failed in the container and gitleaks logged "not a git repository", scanned 0 commits and passed:
# from every agent worktree, the history scan before a push read nothing. git's common directory is now
# mounted at its own absolute path, where that pointer leads, and a scan that reports no commit scanned
# while the repo has commits is refused, whatever the cause.
# v16: every `tr` that reads history bytes runs under `LC_ALL=C`, as the `awk` beside it does. BSD/macOS
# `tr` checks its input against the locale and aborts ("Illegal byte sequence") on a non-UTF-8 byte, so
# on a Mac the commit-message pass died before gitleaks ran, and a credential in a commit message was
# never reported.
# v17: the same for every `sed`, `sort` and `grep` that reads history bytes. BSD `grep` erroring on a
# non-UTF-8 author name inside `|| true` left the identity pass empty, so it PASSED having read nothing.
gitleaks: ## secret scan over FULL HISTORY + the commit-identity pass (the hooks cover commit/push)
	@set -e; C=$$(mktemp); O=$$(mktemp); trap 'rm -f "$$C" "$$O"' EXIT INT TERM; \
	G=$$(git -C "$(CURDIR)" rev-parse --path-format=absolute --git-common-dir); \
	n=$$(git -C "$(CURDIR)" rev-list --count --all); \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	rc=0; docker run --rm -v "$(CURDIR)":/repo -v "$$G":"$$G":ro -v "$$C":/gl.toml:ro -w /repo \
	  $(GITLEAKS_IMAGE) git /repo -c /gl.toml --redact -v --ignore-gitleaks-allow > "$$O" 2>&1 || rc=$$?; \
	cat "$$O"; [ "$$rc" -eq 0 ] || exit "$$rc"; \
	if [ "$$n" -gt 0 ] && ! grep -Eq '(^|[^0-9])[1-9][0-9]* commits scanned' "$$O"; then \
	  echo "REFUSING: gitleaks scanned no commit of a history holding $$n: the history scan read nothing (above)."; exit 1; \
	fi
	@# v12: what `gitleaks git` never reads. It scans git's PATCHES, and git prints no patch for a file it
	@# treats as binary: a NUL byte, UTF-16 (a `Localizable.strings`), or a `binary` / `-diff` attribute.
	@# A token in any of them reached the remote with "no leaks found". So every path git ever showed as
	@# binary is re-read as text, NULs stripped, and scanned by path (the config's path allowlists hold).
	@set -e; C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	git -c core.quotePath=false log --branches --tags HEAD --format= -p --no-ext-diff --no-textconv \
	  > "$$D/patches"; \
	LC_ALL=C sed -n 's|^Binary files .* and b/\(.*\) differ$$|\1|p' "$$D/patches" | LC_ALL=C sort -u > "$$D/binary"; \
	if [ -s "$$D/binary" ]; then \
	  mkdir "$$D/t" "$$D/none"; \
	  while IFS= read -r f; do \
	    mkdir -p "$$D/t/$$(dirname "$$f")"; \
	    git -c core.quotePath=false log --branches --tags HEAD --format= -p --text --no-ext-diff \
	      --no-textconv -- "$$f" > "$$D/p"; \
	    LC_ALL=C grep -a '^+' "$$D/p" | LC_ALL=C tr -d '\000' > "$$D/t/$$f"; \
	  done < "$$D/binary"; \
	  docker run --rm -v "$$D/t":/scan:ro -w /scan -v "$$D/none":/none:ro -v "$$C":/gl.toml:ro \
	    $(GITLEAKS_IMAGE) dir . -c /gl.toml --redact -v --ignore-gitleaks-allow \
	    --gitleaks-ignore-path /none; \
	fi
	@# v13: every commit and annotated-tag MESSAGE, scanned as a file with the same config (credential
	@# rules and the denylist). One `git log` and one `for-each-ref`, split on a header line carrying a
	@# per-run nonce, so a message cannot forge a header and steer its own lines out of the scan.
	@set -e; C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	N=$$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); [ $${#N} -eq 32 ]; \
	mkdir -p "$$D/t/commit-message" "$$D/t/tag-message" "$$D/none"; \
	git log --branches --tags HEAD --format="$$N commit-message/%H%n%B" > "$$D/raw"; \
	git for-each-ref refs/tags --format="$$N tag-message/%(objectname)%0a%(contents)" >> "$$D/raw"; \
	LC_ALL=C tr -d '\000' < "$$D/raw" > "$$D/msgs"; \
	LC_ALL=C awk -v n="$$N" -v d="$$D/t" \
	  '$$1 == n && NF == 2 { if (f != "") close(f); f = d "/" $$2; printf "" > f; next } \
	   f != "" { print > f }' "$$D/msgs"; \
	docker run --rm -v "$$D/t":/scan:ro -w /scan -v "$$D/none":/none:ro -v "$$C":/gl.toml:ro \
	  $(GITLEAKS_IMAGE) dir . -c /gl.toml --redact -v --ignore-gitleaks-allow \
	  --gitleaks-ignore-path /none || { \
	  echo "REFUSING: a commit or tag MESSAGE carries a finding (the File above names it:"; \
	  echo "  commit-message/<sha> or tag-message/<object>). A message is published with its commit"; \
	  echo "  forever. Reword it (git rebase -i, or git filter-repo --message-callback for older"; \
	  echo "  history), re-run, and ask the OWNER to approve the force-push. Never force-push unapproved."; \
	  exit 1; }
	@# v14: what a push publishes besides content and messages: every file PATH in history and every
	@# branch and tag NAME. A path is not a patch line, so `gitleaks git` never read one, and a file or
	@# a branch named for an internal host passed every gate into a public remote.
	@set -e; C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	mkdir -p "$$D/t" "$$D/none"; \
	git -c core.quotePath=false log --branches --tags HEAD --format= --name-only | LC_ALL=C sort -u > "$$D/t/paths"; \
	git for-each-ref --format='%(refname:short)' refs/heads refs/tags > "$$D/t/ref-names"; \
	docker run --rm -v "$$D/t":/scan:ro -w /scan -v "$$D/none":/none:ro -v "$$C":/gl.toml:ro \
	  $(GITLEAKS_IMAGE) dir . -c /gl.toml --redact -v --ignore-gitleaks-allow \
	  --gitleaks-ignore-path /none || { \
	  echo "REFUSING: a file PATH or a branch/tag NAME carries a finding (File: paths or ref-names above)."; \
	  echo "  A name is published with the history it is in. Rename it (git mv; git branch -m; for older"; \
	  echo "  history git filter-repo --path-rename), re-run, and ask the OWNER to approve the force-push."; \
	  exit 1; }
	@# The identity pass — the half gitleaks structurally cannot do. Cheap: one `git log`.
	@# Walks what THIS repo publishes (branches, tags, HEAD), NOT `--all`: a remote-tracking ref caches the
	@# remote's state, which during a scrub is by definition the un-rewritten history you are about to
	@# force-push over — `--all` refused the verified fix, and any `git fetch` re-armed it.
	@bad=$$(git log --branches --tags HEAD --pretty='%an <%ae>%n%cn <%ce>' 2>/dev/null | LC_ALL=C sort -u \
	  | LC_ALL=C grep -vE '$(GIT_IDENTITY_OK)' || true); \
	if [ -n "$$bad" ]; then \
	  echo "REFUSING: a non-fleet identity appears in commit METADATA (author/committer):"; \
	  echo "$$bad" | LC_ALL=C sed 's/^/    /'; \
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
# v8: the denylist goes to a PER-RUN `mktemp` file, removed on exit. v7 wrote a fixed
# `/tmp/gl.toml` that outlived the run: on a host where commit and push run as different users, the
# next user's redirect was refused (`fs.protected_regular=1`, the Fedora default, blocks O_CREAT on
# another user's file in sticky /tmp even for root), so the privacy gate failed every commit or push
# after a user switch (2 of 2 measured). Two repos scanning at once also shared one file, so one could
# scan with the other's carve-outs. The full-history scan now also passes `-w /repo`, like the staged one.
# v12: the staged bytes are read on the HOST and scanned as files, by path. v11 ran `protect --staged`
# inside the container, which read `.git/index`, not the temporary index git hands the hook in
# `$$GIT_INDEX_FILE`: `git commit -a` and `git commit <path>` were never scanned. It also read git's
# patches, which skip binary, NUL, UTF-16 and `-diff` files, and it honoured a `# gitleaks:allow` on
# the secret's own line and a committed `.gitleaksignore`, so a commit's author could waive their own
# leak. New content gets no waiver: `.gitleaksignore` stays a ledger for the full-history scan only.
gitleaks-staged: ## secret scan of the STAGED changes (run by hooks/pre-commit)
	@set -e; C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	mkdir "$$D/t" "$$D/none"; \
	git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMR -z > "$$D/names"; \
	LC_ALL=C tr '\000' '\n' < "$$D/names" | while IFS= read -r f; do \
	  [ -n "$$f" ] || continue; \
	  mkdir -p "$$D/t/$$(dirname "$$f")"; \
	  git -c core.quotePath=false diff --cached --text --no-ext-diff --no-textconv -U0 -- "$$f" \
	    > "$$D/p"; \
	  LC_ALL=C grep -a '^+' "$$D/p" | LC_ALL=C tr -d '\000' > "$$D/t/$$f"; \
	done; \
	docker run --rm -v "$$D/t":/scan:ro -w /scan -v "$$D/none":/none:ro -v "$$C":/gl.toml:ro \
	  $(GITLEAKS_IMAGE) dir . -c /gl.toml --redact -v --ignore-gitleaks-allow \
	  --gitleaks-ignore-path /none

# v13: the message being WRITTEN, run by hooks/commit-msg (pre-commit cannot see it: git writes the
# message after that hook runs). The hook passes the file in `GITLEAKS_COMMIT_MSG`. The WHOLE file is
# scanned, comment lines included: `--cleanup=verbatim` publishes them, and a cut at the scissors line
# would let a verbatim message hide everything below one. No file to read is a refusal, never a pass.
gitleaks-commit-msg: ## secret + denylist scan of the commit MESSAGE being written (run by hooks/commit-msg)
	@set -e; M="$${GITLEAKS_COMMIT_MSG:-}"; \
	if [ -z "$$M" ] || [ ! -f "$$M" ] || [ ! -r "$$M" ]; then \
	  echo "REFUSING: no commit message to scan (GITLEAKS_COMMIT_MSG='$$M'). hooks/commit-msg" >&2; \
	  echo "  passes the file git hands it; re-emit the hooks with luxlint --emit-hooks." >&2; \
	  exit 1; \
	fi; \
	C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	mkdir -p "$$D/t/commit-message" "$$D/none"; \
	LC_ALL=C tr -d '\000' < "$$M" > "$$D/t/commit-message/COMMIT_EDITMSG"; \
	docker run --rm -v "$$D/t":/scan:ro -w /scan -v "$$D/none":/none:ro -v "$$C":/gl.toml:ro \
	  $(GITLEAKS_IMAGE) dir . -c /gl.toml --redact -v --ignore-gitleaks-allow \
	  --gitleaks-ignore-path /none || { \
	  echo "REFUSING: this commit's MESSAGE carries a finding. A message is published with the" >&2; \
	  echo "  commit forever: reword it and commit again. Never --no-verify." >&2; \
	  exit 1; }

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

# luxarch:guard-upgrade asset v4 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit guard-upgrade`.
# Bumps each guard pin to its latest release and prints the rules the new luxarch adds (`--new-rules`).
# The preview mounts `$(CURDIR)`, this makefile's directory, whatever directory `make -C` ran from.
# Latest is the registry's `:latest`, or with REGISTRY empty (guards loaded from the release tarball)
# the highest released `<guard>:X.Y.Z` on this machine, never `:local`. The pin is rewritten with `sed`
# into a temporary file beside the Makefile (its mode copied first), renamed over it (`mv`, one atomic
# step: a failed write leaves the Makefile as it was), then read back: the same on macOS and Linux.
# A guard whose latest cannot be read is named and fails the run: "all pins already at latest" is
# printed only when every guard was read.
guard-upgrade:  ## Bump every guard pin to the published latest (prints what newly bites)
	@unread=; checked=; bumped=; for g in luxarch luxlint luxaudit; do \
	  if [ -n "$(REGISTRY)" ]; then \
	    img=$(REGISTRY)/luxardolabs/$$g; src="$$img:latest"; \
	    docker pull -q $$img:latest >/dev/null 2>&1 || true; \
	    latest=$$(docker run --rm $$img:latest --version 2>/dev/null | awk '{print $$2}'); \
	  else \
	    img=$$g; src="a released $$g:X.Y.Z image on this machine (REGISTRY is empty)"; \
	    latest=$$(docker images --format '{{.Tag}}' $$g 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1); \
	  fi; \
	  var=$$(echo $$g | tr a-z A-Z)_VERSION; \
	  old=$$(sed -n -E "s/^$$var[[:space:]]*:=[[:space:]]*//p" Makefile); \
	  if [ -z "$$old" ]; then echo "!! no $$var pin found in Makefile — NOT bumped"; unread="$$unread $$g"; continue; fi; \
	  if [ -z "$$latest" ]; then echo "!! could not read $$src — $$var left at $$old"; unread="$$unread $$g"; continue; fi; \
	  checked=1; \
	  tmp=$$(mktemp ./.guard-upgrade.XXXXXX) && cp -p Makefile "$$tmp" && sed -E "s|^($$var[[:space:]]*:=[[:space:]]*).*|\\1$$latest|" Makefile > "$$tmp" && mv -f "$$tmp" Makefile; rc=$$?; \
	  if [ "$$rc" != 0 ]; then rm -f "$$tmp"; echo "!! could not rewrite Makefile (it is unchanged) — $$var NOT bumped"; exit 1; fi; \
	  new=$$(sed -n -E "s/^$$var[[:space:]]*:=[[:space:]]*//p" Makefile); \
	  if [ "$$new" != "$$latest" ]; then echo "!! $$var did NOT change (still $$new)"; exit 1; fi; \
	  if [ "$$old" != "$$latest" ]; then echo "$$var $$old -> $$latest"; bumped=1; fi; \
	  [ "$$g" = luxarch ] && [ "$$old" != "$$latest" ] && docker run --rm -v "$(CURDIR)":/repo $$img:$$latest --new-rules --since $$old || true; \
	done; \
	if [ -n "$$bumped" ]; then echo "pins bumped — re-run make check"; fi; \
	if [ -z "$$checked" ]; then echo "!! could not read any guard's latest (the registry, or with REGISTRY empty this machine's released images) — NO pin was checked; currency NOT established"; exit 1; fi; \
	if [ -n "$$unread" ]; then echo "!! NOT checked:$$unread (no pin, or its latest could not be read) — currency NOT established"; exit 1; fi; \
	if [ -z "$$bumped" ]; then echo "all pins already at latest"; fi

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nbrother_ql — make targets\n"} \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

.PHONY: check onboard-check honest lint mypy arch audit audit-lock format test gitleaks gitleaks-staged release build status guard-version-check guard-upgrade help
