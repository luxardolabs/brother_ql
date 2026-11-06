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
LUXARCH_VERSION  := 0.345.2
LUXLINT_VERSION  := 0.74.0
LUXAUDIT_VERSION := 0.16.0

LUXARCH_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxarch:$(LUXARCH_VERSION)
LUXLINT_IMAGE  ?= $(LUX_REGISTRY)/luxardolabs/luxlint:$(LUXLINT_VERSION)
LUXAUDIT_IMAGE ?= $(LUX_REGISTRY)/luxardolabs/luxaudit:$(LUXAUDIT_VERSION)

# The names the verbatim luxarch assets (gitleaks, guard-upgrade) reference.
REGISTRY = $(LUX_REGISTRY)
LUXLINT  = $(LUXLINT_IMAGE)

# luxarch:guard-run asset v7 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit guard-run`.
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
# The main checkout is mounted only from a linked worktree: git's own directory differs from the
# common one. A plain subdirectory of a checkout is not a worktree and gets no second mount. A
# worktree of a submodule or of a bare repository has a common directory not named `.git`: that
# directory itself is mounted. A git hook's GIT_DIR is not this checkout's, so it is ignored here.
override GUARD_MAIN := $(if $(filter command,$(origin GUARD_MAIN)),$(GUARD_MAIN),$(shell unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR; cd -P -- '$(subst ','\'',$(CURDIR))' 2>/dev/null && g=$$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) && d=$$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [ "$$g" != "$$d" ] && if [ "$$(basename "$$d")" = .git ]; then dirname "$$d"; else printf '%s\n' "$$d"; fi))
#
# Every emitted block mounts `$(CURDIR)` as this checkout, and a relative `-include Makefile.local`
# is read from it. Under `make -f <path>` started in another directory, `$(CURDIR)` is that other
# directory: the guards would judge the wrong tree, and Makefile.local would not be read. So a run
# whose first makefile is not in the directory make runs in is refused; `make -C <dir>` is the way to
# run it from elsewhere. The makefile is found by joining MAKEFILE_LIST's words until they name a
# file (a path may hold spaces), and its directory is compared, as a whole string, with the shell's
# real one and with CURDIR; the longest joining that names a file wins, so a stray file named like
# the path's first word does not. MAKEFILES (makefiles read first) is refused. A CURDIR given on the
# top make's command line names the tree deliberately and is honoured; a sub-make, which inherits
# it, is judged like any run, except under `make -n`, which runs no guard. v3: the dry runs luxarch and
# luxlint read a makefile with (`make -n`, in a copy of the tree, CURDIR naming the real one, each
# sub-make at its own MAKELEVEL) were refused at the first sub-make, so a correctly wired repo read
# red. The block's own variables are set with `override` and never
# exported, so neither `make -e` nor a parent's bare `export` can hand a sub-make other values.
# Stated limits, each refused rather than misread: a `-f` path holding two spaces in a row or a tab
# (MAKEFILE_LIST collapses them: run `make -C`), and a checkout path holding `:` (docker reads it
# as a mount option). Not refused: under `make -n`, a guard line that make runs anyway (a `+` line,
# or one naming `$(MAKE)`) in a sub-make that inherited a command-line CURDIR.
override guard_same = $(and $(findstring |$(1)|,|$(2)|),$(findstring |$(2)|,|$(1)|))
override guard_dry := $(findstring n,$(filter-out -% %=%,$(firstword $(MAKEFLAGS))))
$(if $(strip $(MAKEFILES)),$(error REFUSING: MAKEFILES ($(MAKEFILES)) reads other makefiles first, so the guards' tree is not this makefile's: unset it))
unexport CURDIR GUARD_MAIN GUARD_HERE GUARD_PWD GUARD_RUN guard_same guard_dry
override GUARD_HERE := $(shell set -- $(foreach w,$(MAKEFILE_LIST),'$(subst ','\'',$(w))'); p=; for w do p="$${p:+$$p }$$w"; if [ -f "$$p" ]; then h=$$(cd -P -- "$$(dirname -- "$$p")" && pwd -P); fi; done; printf '%s\n' "$$h")
override GUARD_PWD := $(shell pwd -P)
$(if $(and $(filter command,$(origin CURDIR)),$(or $(filter 0,$(MAKELEVEL)),$(guard_dry))),,$(if $(and $(GUARD_HERE),$(call guard_same,$(GUARD_HERE),$(GUARD_PWD)),$(call guard_same,$(GUARD_HERE),$(CURDIR))),,$(if $(filter environment%,$(origin GUARD_MAIN)),$(error REFUSING: GUARD_MAIN comes from the environment, so the caller chose a tree to mount: unset it))$(error REFUSING: make runs in $(GUARD_PWD) (CURDIR $(CURDIR)), not in this makefile's directory $(or $(GUARD_HERE),(not found)), so every guard would read the wrong tree: run make -C <the makefile's directory>)))
override GUARD_RUN = guard_slot_run() ( $(guard_slot_body) $(guard_capped) ); guard_slot_run $(guard_slot_vals) docker run --rm $(guard_caps) -v '$(subst ','\'',$(CURDIR))':/repo $(if $(GUARD_MAIN),$(if $(call guard_same,$(CURDIR),$(GUARD_MAIN)),,-v '$(subst ','\'',$(GUARD_MAIN))':'$(subst ','\'',$(GUARD_MAIN))':ro))
#
# ── Heavy-job slots (v5): at most HEAVY_SLOTS heavy jobs run on this machine at once ─────────────────
# A full guard scan, the full gate (`make check`) and the full test suite each hold one slot for as long
# as they run, counted across every checkout, session and user on the machine; the next one waits. Ten
# parallel full scans once held 40 GiB on one host, and its timing tests failed at load 60. A slot is a
# flock(2) lock on `<HEAVY_SLOT_DIR>/slot.<n>`, held on file descriptor 9 by the job's own processes:
# GUARD_RUN runs the guard's `docker run` through a shell function (`guard_slot_run`, a subshell that
# takes the slot and execs the client with it open), and the gate's and the suite's recipe shell
# opens it, so every command they start inherits it. The kernel releases it when the last of them
# exits, on a normal exit, Ctrl-C or kill -9 alike: there is no cleanup step and nothing goes stale.
# It is taken with flock(1), or where there is none (macOS) with python3's fcntl.flock on the same
# descriptor; with neither, the job is refused, naming both.
# The slot code runs in the recipe's own shell and holds under `set -e` there, as the fleet's
# recipes run: a held slot, a slot file another job made first or an ancestor that exits mid-walk
# moves the job on, never ends it.
#   - WAITING polls each second and, once it has waited a second, prints one line on stderr naming
#     the jobs that hold the slots (each holder writes `slot.<n>.who` as it takes one, a job nested
#     through an ancestor as its own lock is granted). A job never fails for want of a slot, and
#     never runs without one.
#   - TARGETED runs take none: a GUARD_RUN naming `--rule <id>` (a value holding more than blanks
#     and commas, which luxarch drops, so `--rule ' '` runs every rule), or a flag that scans nothing
#     (`--emit*`, `--doc`, `--docs`, `--playbook`, `--version`, `--list-rules`, `--changelog`,
#     `--new-rules`, `--coverage-ratchet`, `--help`), and `make test-fast PYTEST_ARGS=<…>`. Every
#     other guard run is a full scan and takes one: `--path <file>` alone too, which narrows only
#     what is shown while every rule still reads the whole repo.
#   - NESTED heavy jobs take no second slot: a job whose descriptor 9 is open on one of slots
#     1..HEAVY_SLOTS and holds its lock runs inside the job that took it (`check` running `test`
#     running a scan), so it starts at once, at HEAVY_SLOTS=1 too. So does a job one of whose
#     ancestor processes has descriptor 9 open on such a slot while it is locked (read from /proc),
#     which finds the holder through a process that closed the descriptors it inherited (Python's
#     subprocess does by default). That job opens the slot on
#     descriptor 9 itself and waits in the background to take the lock, so it keeps the slot
#     after its ancestor exits, for as long as it runs. No variable can claim either: the descriptor and the lock are the
#     proof.
#   - HEAVY_SLOTS and HEAVY_SLOT_DIR are machine settings: set them in Makefile.local (`HEAVY_SLOTS :=
#     2`, a whole number from 1 to 9999). From the environment, the command line or `--eval` they
#     are refused, as check refuses CHECK_LEGS: a value set in passing would let one caller choose
#     how many heavy jobs the whole machine runs. So is `-I <dir>` (outside `make -n`), from which
#     make reads a Makefile.local this checkout lacks.
#   - THE DIRECTORY is `/var/tmp/fleet-heavy-slots`, not under TMPDIR: TMPDIR is per user on macOS and
#     per session in some agent harnesses, which would give each its own slots. `/var/tmp` exists,
#     sticky and writable by every user, on Linux and macOS, and it is not where per-run scratch
#     goes (`repo.makefile_no_fixed_tmp` reds a fixed `/tmp` path: the slots are shared on purpose).
#     The directory is made 1777 (sticky and world-writable, as /tmp is) so every user can add a slot
#     file, and each slot file 644 so every user can open it read-only, which is all a lock needs: two
#     users on one machine share one cap. A slot directory or file that is a symlink, not a plain
#     file, or unreadable is refused, naming it.
# Stated limits: the cap counts slots 1..HEAVY_SLOTS of each caller, so a caller with a larger setting
# (or a second makefile given with `-f` that sets one) uses more slots than one with a smaller; a
# process a job starts that outlives it (a backgrounded daemon) keeps the descriptor, and so the slot,
# until it exits; where there is no /proc (macOS) a job started through a process that closed its
# descriptors is not seen as nested and waits for a slot of its own; and an ancestor shell that opens
# a held slot file on descriptor 9 by hand makes its children read as nested in that slot. Found by
# attack round 3 and not closed: a `--rule` substring that matches many rules (`--rule .`) is taken as
# targeted; a job nested through an ancestor runs unlocked from the moment it finds the ancestor's
# lock until its own background request reaches the kernel, so an ancestor that exits in that window
# (milliseconds; not hit unloaded in 50 tries) lets a new job share its slot; a slot file removed
# while held (`rm`; systemd-tmpfiles skips locked files) is made anew, and its next holder runs beside
# the old one; the ancestor walk cannot read another user's /proc entries, so a job started as
# another user through a process that closed its descriptors waits for a slot of its own (at
# HEAVY_SLOTS=1, on its own ancestor); a user who creates a slot file others cannot read makes their
# jobs refuse; a `slot.<n>.who` left by another user cannot be replaced, so waiters may name an
# earlier job; and a command that unlocks its inherited descriptor 9 (`flock -u 9`) frees its job's
# slot.
HEAVY_SLOTS ?= 3
HEAVY_SLOT_DIR ?= /var/tmp/fleet-heavy-slots
# ── Heavy-job caps: how much of the machine one guard or test container may take ────────────────────
# Every guard run (and the test block's suite) runs with `--memory=HEAVY_MEMORY` (swap included, so it
# cannot spill). Without it one run that grows (a full scan of a large repo reached 5-7 GB) shares the
# Docker VM's memory with the app and its database, and when the VM runs out the kernel's OOM killer
# picks whichever it likes: on one Mac it took the app and Postgres. Capped, a run that hits its own
# limit is the one killed, exit 137, and it says so. Machine configuration, like HEAVY_SLOTS, set in
# Makefile.local; unset, it is two thirds of the Docker VM's memory shared among HEAVY_SLOTS (`docker
# info`; 6 GiB on a 27 GiB Docker Desktop VM), or 6g where docker cannot say. HEAVY_CPUS, when set,
# adds `--cpus`; unset there is no CPU cap (a suite that sizes its workers from the host's cores, as
# pytest-xdist's `-n auto` does, would run them all inside the quota).
# Each also runs at `--oom-score-adj=500`, so when the VM runs out anyway the kernel kills a guard
# or test container before the app and its database, which compose ranks at -500
# (`repo.compose_oom_ranked`).
# (recursive, so `docker info` runs only when a capped run expands it, never on every parse)
HEAVY_MEMORY ?= $(or $(shell docker info --format '{{.MemTotal}}' 2>/dev/null | awk -v n='$(HEAVY_SLOTS)' '$$1 ~ /^[0-9]+$$/ { n += 0; if (n < 1) n = 3; m = int($$1 * 2 / 3 / n / 1048576); if (m < 1024) m = 1024; print m "m"; exit }'),6g)
HEAVY_CPUS ?=
unexport HEAVY_SLOTS HEAVY_SLOT_DIR HEAVY_MEMORY HEAVY_CPUS guard_slot guard_slot_vals guard_slot_body guard_caps guard_capped
override guard_caps = $(foreach v,HEAVY_MEMORY HEAVY_CPUS,$(if $(filter environment% command,$(origin $(v))),$(error REFUSING: $(v) comes from the $(origin $(v)), so the caller chose how much of this machine one heavy job may take: set it in Makefile.local)))--oom-score-adj=500 --memory='$(subst ','\'',$(HEAVY_MEMORY))' --memory-swap='$(subst ','\'',$(HEAVY_MEMORY))'$(if $(HEAVY_CPUS), --cpus='$(subst ','\'',$(HEAVY_CPUS))')
# the run, then its exit: 137 is a SIGKILL, which for a capped container is almost always its own limit
override guard_capped = gs_rc=0; "$$@" || gs_rc=$$?; [ "$$gs_rc" != 137 ] || echo "$$gs_job: the container was killed (exit 137), most likely at its memory cap (HEAVY_MEMORY $(HEAVY_MEMORY)): raise HEAVY_MEMORY in Makefile.local, or lower HEAVY_SLOTS so the machine has room" >&2; exit "$$gs_rc"
override guard_slot_vals = $(foreach v,HEAVY_SLOTS HEAVY_SLOT_DIR,$(if $(filter environment% command,$(origin $(v))),$(error REFUSING: $(v) comes from the $(origin $(v)), so the caller chose how many heavy jobs this machine runs at once: set it in Makefile.local)))$(if $(filter --eval=%,$(MAKEFLAGS)),$(error REFUSING: --eval adds makefile text from the command line, which could choose the heavy-job slots: put it in Makefile.local))$(if $(guard_dry),,$(if $(filter -I% --include-dir%,$(filter-out $(MAKEOVERRIDES),$(MAKEFLAGS))),$(error REFUSING: -I lets make read a Makefile.local from another directory, which could choose the heavy-job slots: run without it)))'$(subst ','\'',$(HEAVY_SLOT_DIR))' '$(subst ','\'',$(HEAVY_SLOTS))' '$(subst ','\'',make $@ in $(CURDIR))'
override guard_slot = $(if $(guard_dry),:,set -- $(guard_slot_vals); $(guard_slot_body) :)
override guard_slot_body = gs_d=$$1 gs_n=$$2 gs_job=$$3; shift 3; \
  case "$$gs_n" in (""|0*|*[!0-9]*|?????*) echo "REFUSING: HEAVY_SLOTS is \"$$gs_n\", not a whole number from 1 to 9999: set it in Makefile.local" >&2; exit 2;; esac; \
  gs_x=; gs_p=; for gs_a in "$$@"; do case "$$gs_p" in (--rule) case "$$gs_a" in (*[![:space:],]*) gs_x=1;; esac;; esac; \
    case "$$gs_a" in (--rule=*[![:space:],]*|--emit|--emit=?*|--emit-*|--doc|--doc=?*|--docs|--playbook|--playbook=?*|--version|--list-rules|--changelog|--new-rules|--coverage-ratchet|--help) gs_x=1;; esac; gs_p=$$gs_a; done; \
  gs_who() { gs_t=$$(mktemp "$$gs_d/.who.XXXXXX") && { printf "%s\n" "$$gs_job (shell pid $$$$, user $$(id -un 2>/dev/null))" > "$$gs_t"; chmod 644 "$$gs_t"; mv -f "$$gs_t" "$$gs_f.who" 2>/dev/null || rm -f "$$gs_t"; }; }; \
  gs_lock() { if command -v flock >/dev/null 2>&1; then flock -n -E 75 9; else python3 -I -c "import fcntl,os,sys; sys.excepthook=lambda t,v,b: os._exit(75 if t is BlockingIOError else 2); fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)"; fi; }; \
  gs_have=; if [ -z "$$gs_x" ]; then gs_i=1; while [ "$$gs_i" -le "$$gs_n" ]; do gs_f=$$gs_d/slot.$$gs_i; \
      if [ /dev/fd/9 -ef "$$gs_f" ] && gs_lock; then gs_have=1; break; fi; gs_i=$$((gs_i + 1)); done; \
    gs_a=$$PPID; while [ -z "$$gs_have" ] && [ "$$gs_a" -gt 1 ] 2>/dev/null && [ -d "/proc/$$gs_a/fd" ]; do gs_i=1; \
      while [ "$$gs_i" -le "$$gs_n" ]; do gs_f=$$gs_d/slot.$$gs_i; \
        if [ "/proc/$$gs_a/fd/9" -ef "$$gs_f" ] && { ( exec 9<"$$gs_f"; gs_lock ); [ $$? = 75 ]; }; then gs_have=1; gs_anc=1; break; fi; gs_i=$$((gs_i + 1)); done; \
      gs_a=$$(sed -e "s/.*) . //" -e "s/ .*//" "/proc/$$gs_a/stat" 2>/dev/null) || gs_a=; done; \
    if [ -n "$${gs_anc:-}" ]; then exec 9<"$$gs_f"; ( if command -v flock >/dev/null 2>&1; then flock 9; else python3 -I -c "import fcntl; fcntl.flock(9, fcntl.LOCK_EX)"; fi && gs_who ) >/dev/null 2>&1 & fi; fi; \
  if [ -z "$$gs_x$$gs_have" ]; then \
    if [ -L "$$gs_d" ] || { [ ! -d "$$gs_d" ] && ! mkdir -m 1777 "$$gs_d" 2>/dev/null && [ ! -d "$$gs_d" ]; }; then \
      echo "REFUSING: the heavy-job slot directory $$gs_d (HEAVY_SLOT_DIR) is not a directory this job can use" >&2; exit 2; fi; \
    gs_w=; gs_r=75; while :; do gs_i=1; \
      while [ "$$gs_i" -le "$$gs_n" ]; do gs_f=$$gs_d/slot.$$gs_i; \
        if [ ! -e "$$gs_f" ] && [ ! -L "$$gs_f" ]; then gs_t=$$(mktemp "$$gs_d/.slot.XXXXXX") && { chmod 644 "$$gs_t"; ln "$$gs_t" "$$gs_f" 2>/dev/null || :; rm -f "$$gs_t"; }; fi; \
        if [ -L "$$gs_f" ] || [ ! -f "$$gs_f" ] || [ ! -r "$$gs_f" ]; then \
          echo "REFUSING: $$gs_f is not a plain file this job can read, so the heavy-job slots cannot be counted: remove it" >&2; exit 2; fi; \
        exec 9<"$$gs_f"; gs_r=0; gs_lock || gs_r=$$?; [ "$$gs_r" = 75 ] || break 2; gs_i=$$((gs_i + 1)); done; \
      if [ -z "$$gs_w" ]; then gs_w=0; elif [ "$$gs_w" = 0 ]; then gs_w=1; gs_h=; gs_i=1; while [ "$$gs_i" -le "$$gs_n" ]; do gs_o=; gs_f=$$gs_d/slot.$$gs_i.who; \
          if [ -f "$$gs_f" ] && [ ! -L "$$gs_f" ]; then read -r gs_o < "$$gs_f" || :; fi; gs_h="$$gs_h$${gs_h:+; }$${gs_o:-slot $$gs_i: holder unknown}"; gs_i=$$((gs_i + 1)); done; \
        echo "$$gs_job: waiting for a heavy-job slot ($$gs_n in use in $$gs_d, held by: $$gs_h)" >&2; fi; \
      sleep 1; done; \
    [ "$$gs_r" = 0 ] || { echo "REFUSING: could not lock the heavy-job slot $$gs_f with flock(1) or python3 (exit $$gs_r)" >&2; exit 2; }; \
    gs_who; fi;

# The test/build base. Matches requires-python (>=3.14) and .luxlint.toml [python].target,
# so the suite runs on the interpreter the code targets (luxarch repo.python_version_consistent).
TAIL_IMAGE ?= python:3.14-slim

# Keep files written by containers owned by the repo owner, not root.
REPO_UID := $(shell id -u)
REPO_GID := $(shell id -g)

# A clean clone without registry access still has a working Makefile: each guard-backed
# target run on its own skips with a message instead of failing on an unreachable pull.
# `gitleaks` and `gitleaks-staged` do not skip: with no registry they fail on the image name.
# A skip is not a pass, so `check` and `release` refuse an empty registry, as make reads this file:
# a prerequisite could be skipped with `-o`. A registry given on the command line is refused too,
# because the gate keeps command-line variables from its legs, which would then skip. Dry runs are
# how the guards read this makefile, so they pass.
$(if $(filter command environment%,$(origin MAKECMDGOALS)),$(error REFUSING: MAKECMDGOALS comes from the $(origin MAKECMDGOALS), so make cannot tell which goals are running: unset it))
$(if $(and $(filter check release,$(MAKECMDGOALS)),$(if $(guard_dry),,1)),$(if $(strip $(LUX_REGISTRY)),,$(error REFUSING: LUX_REGISTRY is unset, so every guard would skip and nothing would be judged: copy Makefile.local.example to Makefile.local))$(if $(filter command,$(origin LUX_REGISTRY)),$(error REFUSING: LUX_REGISTRY on the command line never reaches the gate's legs, so they would skip: set it in Makefile.local)))
SKIP_NO_REGISTRY = if [ -z "$(LUX_REGISTRY)" ]; then echo "$@: LUX_REGISTRY unset (see Makefile.local.example) — skipping"; exit 0; fi

# This checkout as a bind-mount source, quoted so a directory name holding shell syntax stays a name.
override CHECKOUT = '$(subst ','\'',$(CURDIR))'

# A CURDIR on the command line is how GUARD_RUN is told to judge another tree. `status` and `release`
# act in this tree (stamp its commit, tag it), so they refuse one. Dry runs are how the guards read
# this makefile, so they pass.
override REFUSE_OTHER_TREE = $(if $(and $(filter command,$(origin CURDIR)),$(if $(guard_dry),,1)),$(if $(call guard_same,$(CURDIR),$(GUARD_PWD)),,$(error REFUSING: CURDIR on the command line names another tree, so $@ would read it and act in this one: run make -C <that tree>)))

# Refused as make expands a recipe's first line, a `+` line that `-t` runs too: an expansion $(error)
# stops make under `-i`, and a recipe's own refusal in a sub-make is discarded by a parent's `-i`.
override REFUSE_IGNORED = $(if $(or $(findstring i,$(filter-out -%,$(firstword $(MAKEFLAGS)))),$(findstring t,$(filter-out -%,$(firstword $(MAKEFLAGS)))),$(findstring e,$(filter-out -%,$(firstword $(MAKEFLAGS))))),$(error REFUSING: make -i ignores failures, -t touches what it should run and -e lets the environment override the makefile, so make $@ could report what never passed: run it without them))

# The ways check-gate lists for a caller to change how a recipe runs, for the one recipe that
# publishes. Stated limit, as check-gate states it: a second makefile given with `-f` is part of the
# makefile as far as make can tell, and a variable set with `?=` takes a value from the environment.
override REFUSE_OUTSIDE_TEXT = $(if $(guard_dry),,$(if $(filter --eval=% -I% --include-dir%,$(filter-out $(MAKEOVERRIDES),$(MAKEFLAGS))),$(error REFUSING: --eval or -I adds makefile text from outside, which could change what make $@ runs: run it without them))$(if $(strip $(MAKEFILES)),$(error REFUSING: MAKEFILES ($(MAKEFILES)) reads other makefiles first: unset it))$(foreach v,MAKE MAKE_COMMAND SHELL .SHELLFLAGS,$(if $(filter environment% command,$(origin $(v))),$(error REFUSING: $(v) comes from the $(origin $(v)), so the caller chose how make $@ runs: set it in the makefile))))

##@ Gates

# luxarch:check-gate asset v3 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit check-gate`.
# ── The fleet gate: every leg runs, then the gate fails naming each red leg ───────────────────────
# Emitted by `luxarch --emit check-gate`; it replaces a hand-written `check:` line. A gate written as a
# prerequisite list (`check: … lint mypy test arch …`) stops at the FIRST failing leg: one ruff finding
# hid a 4,700-test suite, every hidden red cost one more fix-and-rerun cycle, and agents reached for
# `make -k`, which keeps going but also throws away the fatal steps' fatality.
#
# `guard-version-check` and `honest` stay PREREQUISITES and stay fatal: they run first, and a stale
# guard or a rule family that scanned nothing makes every later verdict meaningless. Every other leg
# then runs in order. A leg that fails is recorded, never skipped, and the gate exits non-zero naming
# each one. `repo.makefile_canonical` credits CHECK_LEGS only when this recipe is the asset's own, so
# a hand-written loop that drops an exit code earns nothing.
#
# The recipe refuses, as make expands it, every way found for a caller to end the gate in a pass over
# a red leg. An expansion `$(error)` stops make even under `make -i` (which throws away every exit
# status, the gate's own included), and it is reached wherever `check` runs in this make, as a goal or
# as a prerequisite. A parent recipe that runs `$(MAKE) check` under its own `-i` still discards it.
#   - make's flags `-i` (errors ignored), `-t` (legs touched, not run) and `-e` (the environment
#     overrides the makefile's tool settings), in any spelling: MAKEFLAGS, GNUMAKEFLAGS, `+=`;
#   - `--eval`, `-I` (it can supply an included file such as Makefile.local) and MAKEFILES: each adds
#     makefile text from outside to this make and every leg, so the caller would choose what the
#     legs run, or which legs count;
#   - CHECK_LEGS, MAKE, MAKE_COMMAND, SHELL or .SHELLFLAGS from the environment or the command line,
#     and an empty CHECK_LEGS.
# A variable given on the command line never reaches a leg: `check` empties MAKEOVERRIDES for its
# sub-makes and unsets each such variable in the shell that starts them (make exports it there
# too; never PATH or a name the shell owns, like PPID or OPTIND), so each leg runs with the makefile's
# settings and `make release ALLOW_RETAG=1` still runs
# the gate. It does reach `check`'s two prerequisites, which run in this make. MAKEFLAGS or
# GNUMAKEFLAGS given as a command-line variable is refused, and MAKE and SHELL are checked as the
# recipe runs: make's own MAKE, and a POSIX shell.
# Under `make -n` the legs dry-run (each sub-make prints its commands) and the gate exits 1 with no
# verdict: nothing ran, so nothing passed. Stated limits: a second makefile given with `-f` is part
# of the makefile as far as make can tell, and a variable a leg runs that the makefile sets with `?=`
# or never sets (an image, a tool, its arguments) takes a value from the environment; the gate can
# tell neither from your own.
# v3: the gate holds one of the machine's heavy-job slots (the guard-run block's `guard_slot`, v4) while
# its legs run, so a full gate counts once against HEAVY_SLOTS and every scan and suite it starts runs
# inside that slot instead of waiting for a second one. Its two prerequisites run before the recipe,
# so each of their full scans takes a slot of its own for as long as it runs.

# Setting: the legs, in order, set in the makefile. An app repo's are exactly these; a repo with more
# legs (a guard's own parity suite) appends them. Removing one reds repo.makefile_canonical ----------
CHECK_LEGS ?= lint mypy test arch audit gitleaks

check: override MAKEOVERRIDES :=
check: guard-version-check honest ## THE fleet gate: runs every leg, then fails naming each red one
	@$(foreach v,MAKEFLAGS GNUMAKEFLAGS,$(if $(filter command,$(origin $(v))),$(error REFUSING: $(v) is given as a command-line variable, so every leg would inherit flags this gate never saw: pass make's flags as flags)))$(if $(filter-out default,$(origin MAKE_COMMAND)),$(error REFUSING: MAKE_COMMAND is set by the $(origin MAKE_COMMAND), so a leg would not be make))$(if $(filter-out override,$(origin MAKEOVERRIDES)),$(error REFUSING: check's own `override MAKEOVERRIDES :=` is missing or changed, so a command-line variable would reach the legs: re-emit the gate))$(if $(subst $$(MAKE_COMMAND),,$(value MAKE)),$(error REFUSING: MAKE is $(value MAKE), not make's own $$(MAKE_COMMAND), so a leg would not be make))$(if $(and $(filter 1,$(words $(SHELL))),$(filter /bin/sh /usr/bin/sh /bin/bash /usr/bin/bash /bin/dash /usr/bin/dash /bin/zsh /usr/bin/zsh,$(SHELL))),,$(error REFUSING: SHELL is $(SHELL), not a POSIX shell that returns each leg's status))$(if $(or $(findstring i,$(filter-out -%,$(firstword $(MAKEFLAGS)))),$(findstring t,$(filter-out -%,$(firstword $(MAKEFLAGS)))),$(findstring e,$(filter-out -%,$(firstword $(MAKEFLAGS))))),$(error REFUSING: make -i ignores every failure, -t touches the legs instead of running them, and -e lets the environment override the makefile's tools (flags: $(filter-out -%,$(firstword $(MAKEFLAGS)))), so a red leg could pass: run make check without them))$(if $(findstring n,$(filter-out -%,$(firstword $(MAKEFLAGS)))),,$(if $(filter -I% --include-dir%,$(MAKEFLAGS)),$(error REFUSING: -I lets an included file (Makefile.local) come from another directory, into every leg: run make check without it))$(if $(filter --eval=%,$(MAKEFLAGS)),$(error REFUSING: --eval adds makefile text from the command line to every leg: put it in the makefile))$(if $(strip $(MAKEFILES)),$(error REFUSING: MAKEFILES ($(MAKEFILES)) reads other makefiles into every leg: unset it))$(foreach v,CHECK_LEGS MAKE MAKE_COMMAND SHELL .SHELLFLAGS,$(if $(filter environment% command,$(origin $(v))),$(error REFUSING: $(v) comes from the $(origin $(v)), so the caller chose how the legs run: set it in the makefile))))$(if $(strip $(CHECK_LEGS)),,$(error REFUSING: CHECK_LEGS is empty, so no leg would run))$(foreach v,$(filter-out PATH PPID SHELLOPTS BASHOPTS OPTIND UID EUID BASH_VERSINFO,$(.VARIABLES)),$(if $(filter command,$(origin $(v))),case '$(subst ','\'',$(v))' in ([0-9]*|*[!A-Za-z0-9_]*) ;; (*) unset '$(subst ','\'',$(v))';; esac; )) \
	$(if $(value guard_slot),,$(error REFUSING: the gate holds a heavy-job slot from the guard-run block (v4), which this makefile does not define: paste luxarch --emit guard-run above it))$(guard_slot); \
	failed=; for leg in $(CHECK_LEGS); do \
	  printf '\n── make %s\n' "$$leg"; \
	  $(MAKE) --no-print-directory "$$leg" || failed="$$failed $$leg"; \
	done; \
	if [ -n "$$failed" ]; then printf '\n✗ make check FAILED:%s (every leg ran; each one is above)\n' "$$failed"; exit 1; fi; \
	case '$(filter-out -%,$(firstword $(MAKEFLAGS)))' in *n*) printf '\nmake -n: the legs above were printed, not run, so make check gives no verdict\n'; exit 1;; esac; \
	printf '\n✓ make check: every leg passed (%s)\n' '$(CHECK_LEGS)'

# FLEET-ONBOARDING-STANDARD §5: proves the repo is ONBOARDED (all three guards wired and
# honest, privacy wired, history clean). It never judges red/green: that is `check`, so a
# luxaudit exit of 1 (findings) is fine here and anything above it means no verdict.
# make EXECUTES any line naming `$(MAKE)`, even under `make -n`, so the guards sit in a sub-make,
# which dry-runs them, and a dry run prints no verdict.
onboard-check: ## Prove the repo is onboarded: all three guards on + honest + privacy wired (NOT green)
	+@$(REFUSE_IGNORED)true
	@$(SKIP_NO_REGISTRY); fail=0; \
	$(MAKE) --no-print-directory onboard-guards || fail=1; \
	$(MAKE) -s gitleaks >/dev/null 2>&1 || { echo "gitleaks failed over FULL history (secrets or a non-fleet commit identity) — scrub before onboarding is complete"; fail=1; }; \
	case '$(filter-out -%,$(firstword $(MAKEFLAGS)))' in *n*) exit 0;; esac; \
	[ $$fail -eq 0 ] && echo "onboard-check: all three guards on + honest + privacy wired + history clean ✓" || { echo "onboard-check FAILED"; exit 1; }

onboard-guards:
	@set +e; fail=0; A=$$(mktemp); trap 'rm -f "$$A"' EXIT INT TERM; \
	$(GUARD_RUN) $(LUXARCH_IMAGE)  --version      >/dev/null || { echo "luxarch not wired"; fail=1; }; \
	$(GUARD_RUN) $(LUXARCH_IMAGE)  --assert-scans >/dev/null 2>&1 || { echo "luxarch: a rule family scanned NOTHING (hollow green)"; fail=1; }; \
	$(GUARD_RUN) $(LUXLINT_IMAGE)  --preflight    >/dev/null || { echo "mypy tail NOT honest (luxlint --preflight)"; fail=1; }; \
	a=0; $(GUARD_RUN) $(LUXAUDIT_IMAGE) >"$$A" 2>&1 || a=$$?; \
	grep -q "scan could not run" "$$A" && { echo "luxaudit can't scan — supply-chain blind"; fail=1; }; \
	[ "$$a" -le 1 ] || { echo "luxaudit exited $$a without a verdict — supply-chain blind"; fail=1; }; \
	$(GUARD_RUN) $(LUXLINT_IMAGE)  --version      >/dev/null || { echo "luxlint not wired"; fail=1; }; \
	$(GUARD_RUN) $(LUXAUDIT_IMAGE) --version      >/dev/null || { echo "luxaudit not wired"; fail=1; }; \
	[ -f hooks/pre-commit ] || { echo "secret git-hooks NOT wired (luxlint --emit-hooks | sh, commit hooks/)"; fail=1; }; \
	[ "$$(git config core.hooksPath)" = hooks ] || { echo "core.hooksPath is not hooks/ — the secret hooks never fire"; fail=1; }; \
	[ ! -d .github/workflows ] || { echo "public CI present — make check is the sole gate (remove .github/workflows)"; fail=1; }; \
	! sed 's/#.*//' Makefile | grep -qE '^[[:space:]]+[^#]*\bruff[[:space:]]+format\b' || { echo "Makefile runs a bare 'ruff format' — use 'luxlint --format'"; fail=1; }; \
	exit $$fail

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
audit-lock: ## Recompile requirements/audit.txt from the pyproject ranges (audit-only; rerun when deps change or before trusting make audit)
	docker run --rm --user $(REPO_UID):$(REPO_GID) -e HOME=/tmp -v $(CHECKOUT):/repo -w /repo $(TAIL_IMAGE) \
	  sh -c 'pip install -q --user --root-user-action=ignore uv >/dev/null \
	         && mkdir -p requirements \
	         && python -m uv pip compile --upgrade pyproject.toml -o requirements/audit.txt'

# The canonical fixer (FLEET-ONBOARDING-STANDARD §2.1): ruff safe fixes + ruff format with
# the CHECKED config, and mdformat-gfm for Markdown (GFM tables survive). It prints which
# rules it applied, so any surprising rewrite is attributable. Never a bare `ruff format`
# or `mdformat` — either one formats with a config the gate does not check.
format: ## Apply every canonical formatter in place (luxlint --format) — writes to host
	@$(SKIP_NO_REGISTRY); \
	docker run --rm --user $(REPO_UID):$(REPO_GID) -v $(CHECKOUT):/repo $(LUXLINT_IMAGE) --format

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
#   passes a floor of 90;
# - a run alone holds one of the machine's heavy-job slots, and inside `check` shares the gate's;
#   the suite's container is capped like every guard run (guard_slot, guard_caps).
test: ## pytest against the INSTALLED package (canonical config), then the coverage ratchet
	@set +e; $(SKIP_NO_REGISTRY); $(guard_slot); D=$$(mktemp -d); trap 'rm -rf "$$D"' EXIT INT TERM; \
	$(GUARD_RUN) $(LUXLINT_IMAGE) --emit-config pytest > "$$D/pytest.ini" || exit 2; \
	docker run --rm $(guard_caps) -v $(CHECKOUT):/repo:ro -w /repo -v "$$D":/out -e PYTHONDONTWRITEBYTECODE=1 $(TAIL_IMAGE) \
	  sh -c 'pip install -q --root-user-action=ignore pytest pytest-asyncio coverage >/dev/null \
	         && pip install -q --root-user-action=ignore . >/dev/null \
	         && export COVERAGE_CORE=sysmon COVERAGE_FILE=/out/.coverage \
	         && python -m coverage run --branch --source=brother_ql -m pytest -c /out/pytest.ini --rootdir=/repo -p no:cacheprovider \
	         && python -m coverage report --precision=2 > /out/coverage.txt'; rc=$$?; \
	[ $$rc -ne 137 ] || echo "$@: the suite's container was killed (exit 137), most likely at its memory cap (HEAVY_MEMORY $(HEAVY_MEMORY)): raise HEAVY_MEMORY in Makefile.local, or lower HEAVY_SLOTS" >&2; \
	[ $$rc -eq 0 ] || exit $$rc; \
	c=0; docker run --rm -i -v $(CHECKOUT):/repo $(LUXLINT_IMAGE) --coverage-ratchet < "$$D/coverage.txt" > "$$D/ratchet.txt" || c=$$?; \
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
# luxarch:gitleaks asset v20 - DO NOT edit this marker line; it is how repo.emitted_assets_current knows your copy is current. Re-emit with `luxarch --emit gitleaks`.
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

# The fleet's makefiles need GNU make 4 or later. macOS ships GNU make 3.81, which cannot read this
# block (nor some others) and would stop every target with a parse error. make reads lines in order,
# so this refusal comes first and says what to do: `brew install make`, then run `gmake` (or put
# "$(brew --prefix)/opt/make/libexec/gnubin" first on PATH, so `make` is GNU make 4).
$(if $(filter 3.%,$(MAKE_VERSION)),$(error REFUSING: GNU make $(MAKE_VERSION) is too old for this Makefile; it needs GNU make 4 or later. On macOS: brew install make; then run gmake))

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
# The allowance is read from the makefile only: set it there, above this block, to add an identity.
# The identity pass refuses one from the environment or the command line, where a value left in
# the shell (`GIT_IDENTITY_OK=.`) would match every author and pass any identity. It is never
# exported, so a bare `export` in the makefile does not hand it to a sub-make as such a value.
GIT_IDENTITY_OK ?= <214140984\+luxardolabs@users\.noreply\.github\.com>$$|<noreply@github\.com>$$
unexport GIT_IDENTITY_OK

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
# Every pass reads this checkout's repository, never one a caller's GIT_DIR (or a git hook's) names:
# the variables that point git elsewhere or change what it reads are unset for each pass.
# Every pass reads the commits a push publishes, never a local `git replace` that shows git another
# commit (another identity, message, path or content) in their place.
# The repository's own config cannot change what a pass reads either: each pass, the history scan's
# container included, runs git with these settings as command-line config, which outranks every config
# file. `core.useReplaceRefs=false`: git 2.39 (the git macOS ships) lets a repository's `true` turn
# replace refs back on over GIT_NO_REPLACE_OBJECTS. `i18n.logOutputEncoding=UTF-8`: a repository set to
# UTF-16 or UTF-32 output re-encodes every record git prints, the passes' header lines included, and
# the message and identity passes then read nothing. `core.bigFileThreshold=512m` (git's default): a
# lower one makes git treat every file as binary and print no patch. `diff.relative=false`: a relative
# diff drops every path outside the directory git runs in. `log.follow=false`: the binary pass reads
# one path per `git log`, which `log.follow` turns into following a rename to another file.
override GITLEAKS_GIT_CONFIG := GIT_CONFIG_COUNT=5 GIT_CONFIG_KEY_0=core.useReplaceRefs GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=i18n.logOutputEncoding GIT_CONFIG_VALUE_1=UTF-8 GIT_CONFIG_KEY_2=core.bigFileThreshold GIT_CONFIG_VALUE_2=512m GIT_CONFIG_KEY_3=diff.relative GIT_CONFIG_VALUE_3=false GIT_CONFIG_KEY_4=log.follow GIT_CONFIG_VALUE_4=false
override GITLEAKS_HISTORY_ENV := unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_GRAFT_FILE GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM; export $(GITLEAKS_GIT_CONFIG);
gitleaks: override export GIT_NO_REPLACE_OBJECTS := 1
gitleaks: ## secret scan over FULL HISTORY + the commit-identity pass (the hooks cover commit/push)
	+@$(if $(or $(findstring i,$(filter-out -%,$(firstword $(MAKEFLAGS)))),$(findstring t,$(filter-out -%,$(firstword $(MAKEFLAGS))))),$(error REFUSING: make -i or -t would let a finding pass: run make gitleaks without it))$(if $(filter --eval=% -I% --include-dir%,$(filter-out $(MAKEOVERRIDES),$(MAKEFLAGS))),$(error REFUSING: --eval or -I adds makefile text from outside, which could set the identity allowance: run make gitleaks without it))$(if $(strip $(MAKEFILES)),$(error REFUSING: MAKEFILES ($(MAKEFILES)) reads other makefiles before this one: unset it))$(foreach v,SHELL .SHELLFLAGS,$(if $(filter environment% command,$(origin $(v))),$(error REFUSING: $(v) comes from the $(origin $(v)), so the scan would run in another shell)))true
	@# A caller cannot change what this scan reads or how its failures count: make's -i and -t, makefile
	@# text from --eval, -I or MAKEFILES (each could set the identity allowance), and a SHELL or
	@# .SHELLFLAGS from outside are refused before any pass runs, on the first line, a `+` line: make runs
	@# it under -t too, and under .ONESHELL the first line's prefix is the recipe's.
	@# A shallow clone and a graft file each make git (and so every pass) read part of the history,
	@# and the scanned-nothing check below agrees with them: both are refused before any pass. A
	@# merge commit's own changes are read against its first parent (`--diff-merges=first-parent`), in
	@# this scan and the binary and path passes: git shows a merge no diff by default, so a secret
	@# only a merge added passed every pass. A partial clone (blobs fetched on demand, which the scan
	@# container cannot do) is refused like a shallow one, and so is a scan whose git log failed partway
	@# (gitleaks reports `ERR` and still exits 0). Every log reads the root commit (`--root`), without
	@# the repository's textconv drivers or display settings, which could hide a file or the output.
	@# The scan reads the repository's git directory, never the checkout: gitleaks runs in an empty
	@# directory with `GIT_DIR` naming that git directory and that empty directory as the work tree, so
	@# no `core.worktree` the repository sets (a submodule's points outside the mounts) and no
	@# `.gitattributes` in the checkout applies. gitleaks reads a `.gitleaksignore` from the
	@# directory it scans and from its ignore path, and both are that empty directory, so no file in the
	@# checkout (tracked, untracked or excluded) waives a finding. A leak that reached history is
	@# removed from it, never waived.
	@set -e; $(GITLEAKS_HISTORY_ENV) C=$$(mktemp); O=$$(mktemp); E=$$(mktemp -d); trap 'rm -rf "$$C" "$$O" "$$E"' EXIT INT TERM; \
	[ "$$(git rev-parse --is-shallow-repository)" = false ] || { echo "REFUSING: this clone is shallow, so the scan would read only part of the published history: run git fetch --unshallow first."; exit 1; }; \
	if [ -n "$$(git config --get extensions.partialClone)" ] || git config --type=bool --get-regexp '^remote\..*\.promisor$$' | grep -q ' true$$'; then \
	  echo "REFUSING: this is a partial clone, so the scan cannot read the blobs it lacks: clone the repository in full first."; exit 1; fi; \
	gf=$$(git rev-parse --path-format=absolute --git-path info/grafts); [ ! -e "$$gf" ] || { echo "REFUSING: $$gf rewrites history's parents, so the scan would skip the commits it hides: remove it (git replace --convert-graft-file) first."; exit 1; }; \
	G=$$(git -C "$(CURDIR)" rev-parse --path-format=absolute --git-common-dir); \
	A=$$(git -C "$(CURDIR)" rev-parse --absolute-git-dir); \
	n=$$(git -C "$(CURDIR)" rev-list --count --all); \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	rc=0; docker run --rm -e GIT_NO_REPLACE_OBJECTS=1 $(foreach kv,$(GITLEAKS_GIT_CONFIG),-e $(kv)) -e GIT_DIR="$$A" -e GIT_WORK_TREE=/scan -v "$$G":"$$G":ro -v "$$C":/gl.toml:ro -v "$$E":/scan:ro -w /scan \
	  $(GITLEAKS_IMAGE) git /scan -c /gl.toml --redact -v --ignore-gitleaks-allow --gitleaks-ignore-path /scan \
	  --log-opts='--all --full-history --root --diff-merges=first-parent --no-textconv --no-ext-diff --no-color --pretty=medium --date=default --no-abbrev-commit' > "$$O" 2>&1 || rc=$$?; \
	cat "$$O"; [ "$$rc" -eq 0 ] || exit "$$rc"; \
	if LC_ALL=C grep -Eq 'stderr is not empty|ERR[^A-Za-z]*\[git\]' "$$O"; then \
	  echo "REFUSING: git failed partway through the history scan (ERR above), so what it had not read yet was never scanned."; exit 1; \
	fi; \
	if [ "$$n" -gt 0 ] && ! grep -Eq '(^|[^0-9])[1-9][0-9]* commits scanned' "$$O"; then \
	  echo "REFUSING: gitleaks scanned no commit of a history holding $$n: the history scan read nothing (above)."; exit 1; \
	fi
	@# v12: what `gitleaks git` never reads. It scans git's PATCHES, and git prints no patch for a file it
	@# treats as binary: a NUL byte, UTF-16 (a `Localizable.strings`), or a `binary` / `-diff` attribute.
	@# A token in any of them reached the remote with "no leaks found". So every path git ever showed as
	@# binary is re-read as text, NULs stripped, and scanned by path (the config's path allowlists hold).
	@# Which paths are binary is read from an empty work tree, run there, as the history scan reads
	@# them, so a `.gitattributes` in the checkout (committed or not) calls no file text here that the
	@# scan saw no patch for.
	@set -e; $(GITLEAKS_HISTORY_ENV) C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	mkdir "$$D/t" "$$D/none"; \
	git log --branches --tags HEAD --format= --name-only -z --root --diff-merges=first-parent > "$$D/names"; \
	nl=$$(LC_ALL=C tr -cd '\n' < "$$D/names" | wc -c); \
	[ "$$nl" -eq 0 ] || { echo "REFUSING: a path in history holds a newline, which this scan cannot name: rename it."; exit 1; }; \
	A=$$(git -C "$(CURDIR)" rev-parse --absolute-git-dir); \
	git -C "$$D/none" --git-dir="$$A" --work-tree="$$D/none" -c color.ui=never log --branches --tags HEAD --format= --numstat -z --no-renames --root \
	  --diff-merges=first-parent --no-ext-diff --no-textconv > "$$D/numstat"; \
	T=$$(printf '\t'); LC_ALL=C tr '\000' '\n' < "$$D/numstat" | LC_ALL=C sed -n "s/^-$$T-$$T//p" \
	  | LC_ALL=C sort -u > "$$D/binary"; \
	if [ -s "$$D/binary" ]; then \
	  while IFS= read -r f; do \
	    mkdir -p "$$D/t/$$(dirname "$$f")"; \
	    git -c color.ui=never -c diff.noprefix=false --literal-pathspecs log --branches --tags HEAD \
	      --format= -p --text --no-color --src-prefix=a/ --dst-prefix=b/ --root --diff-merges=first-parent \
	      --no-ext-diff --no-textconv -- "$$f" > "$$D/p"; \
	    LC_ALL=C grep -a '^+' "$$D/p" | LC_ALL=C tr -d '\000' > "$$D/t/$$f"; \
	  done < "$$D/binary"; \
	  docker run --rm -v "$$D/t":/scan:ro -w /scan -v "$$D/none":/none:ro -v "$$C":/gl.toml:ro \
	    $(GITLEAKS_IMAGE) dir . -c /gl.toml --redact -v --ignore-gitleaks-allow \
	    --gitleaks-ignore-path /none; \
	fi
	@# v13: every commit and annotated-tag MESSAGE, scanned as a file with the same config (credential
	@# rules and the denylist). One `git log` and one `for-each-ref`, split on a header line carrying a
	@# per-run nonce, so a message cannot forge a header and steer its own lines out of the scan.
	@set -e; $(GITLEAKS_HISTORY_ENV) C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
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
	@set -e; $(GITLEAKS_HISTORY_ENV) C=$$(mktemp); D=$$(mktemp -d); trap 'rm -rf "$$C" "$$D"' EXIT INT TERM; \
	docker run --rm -v "$(CURDIR)":/repo $(LUXLINT) --emit-config gitleaks > "$$C"; \
	mkdir -p "$$D/t" "$$D/none"; \
	git -c core.quotePath=false -c color.ui=never log --branches --tags HEAD --format= --name-only \
	  --root --diff-merges=first-parent > "$$D/names"; LC_ALL=C sort -u < "$$D/names" > "$$D/t/paths"; \
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
	@$(if $(filter environment% command,$(origin GIT_IDENTITY_OK)),$(error REFUSING: GIT_IDENTITY_OK comes from the $(origin GIT_IDENTITY_OK), so the caller chose which authors pass the identity pass: set it in the makefile))$(GITLEAKS_HISTORY_ENV) bad=$$(git log --branches --tags HEAD --pretty='%an <%ae>%n%cn <%ce>' 2>/dev/null | LC_ALL=C sort -u \
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
# leak. No pass reads a `.gitleaksignore`: neither new content nor history gets a waiver.
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
# publish on a dry run. Under `make -n` the gate exits 1 with no verdict, which ends the dry run
# there, so it prints neither the tag nor the publish.
release: ## Tag, push, build and publish the GitHub Release for the VERSION file's version
	+@$(REFUSE_IGNORED)$(REFUSE_OUTSIDE_TEXT)$(REFUSE_OTHER_TREE)true
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
	docker run --rm --user $(REPO_UID):$(REPO_GID) -v $(CHECKOUT):/repo -w /repo $(TAIL_IMAGE) \
	  sh -c 'pip install -q --root-user-action=ignore build >/dev/null && python -m build --outdir dist'

##@ Meta

# FLEET-STATUS: the fleet reads these committed files instead of re-running every guard.
# The guards stay read-only on /repo, so this RECIPE stamps the commit + time and writes.
# `|| true` because --json exits non-zero on a red repo (the verdict is IN the JSON);
# `set -e` so a failed stamp (empty/invalid --json) aborts instead of claiming "wrote".
STAMP = python3 -c 'import json,sys,os; d=json.load(open(sys.argv[1])); d["commit"]=os.environ["SHA"]; d["generated_at"]=os.environ["TS"]; json.dump(d,open(sys.argv[2],"w"),indent=2)'

status: ## Regenerate committed guard-status files (.lux*-status.json) — commit them
	@$(REFUSE_OTHER_TREE)$(SKIP_NO_REGISTRY); \
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
	  docker pull -q $$img:latest >/dev/null 2>&1 || { printf '✗ %s: could not pull %s:latest, so the pin %s was not judged\n' "$$g" "$$img" "$$pin"; rc=1; continue; }; \
	  latest=$$(docker run --rm $$img:latest --version 2>/dev/null | awk '{print $$2}'); \
	  if [ -z "$$latest" ]; then \
	    printf '✗ %s: could not read %s:latest, so the pin %s was not judged\n' "$$g" "$$img" "$$pin"; rc=1; \
	  elif [ "$$latest" != "$$pin" ]; then \
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

.PHONY: check onboard-check onboard-guards honest lint mypy arch audit audit-lock format test gitleaks gitleaks-staged gitleaks-commit-msg release build status guard-version-check guard-upgrade help
