---
name: release
description: Cut a brother_ql release the same way every time — SemVer bump, CHANGELOG entry, gate, annotated vX.Y.Z tag, build, GitHub Release, LuxPM mirror. Follow it end to end; never skip a step.
---

# Library release ritual (brother_ql)

brother_ql is a **library**, not a deployable app. `luxarch --doc FLEET-RELEASE-PROCESS` is explicit that the app runbook — per-version `change_logs/` + `release_notes/`, image build, deploy — does **not** apply here: *"Shipping a guard/library uses a root `CHANGELOG.md` holding the content itself + the guard `release` skill, not this doc."* luxarch emits only the app skill (`--emit release-skill`), so this one is repo-owned, following the same shape the guards use for themselves (`luxarch --doc MAINTAINING`, "Release flow").

Authorities, read them rather than this file when they disagree:

- `luxarch --doc FLEET-BUILD-DEPLOY-STANDARD` — version scheme (libraries are **SemVer**), the `VERSION` file as the only literal, `v<VERSION>` annotated tags, "a release is a tag PLUS a release object"
- `luxarch --doc FLEET-RELEASE-PROCESS` — §0 the release gate, §3 tracker reconciliation (both apply here)
- `luxarch --emit changelog-guide` — the section format this repo's `CHANGELOG.md` follows

## Non-negotiables

- **Commit and tag as the fleet identity** (global git config: `luxardolabs` + the GitHub noreply address). Never `-c user.email=…`; the committed `hooks/pre-commit` blocks it anyway. **No AI attribution** in any message.
- **The tag is `vX.Y.Z`**; everything else is bare — the `VERSION` file, the GitHub Release title, the LuxPM release version.
- **`VERSION` is the source of truth.** `pyproject` reads it via hatchling; `__version__` derives from installed metadata. Bump the file and nothing else.
- **Everything runs in Docker.** `make check` / `build` are `docker run`; no host `.venv`.

## Steps — do every one, in order

1. **Preconditions.** Clean tree, on `main`, `git fetch origin` done. If the local history is not a descendant of `origin/main`, resolve that first — never force-push over published history.

1. **Decide the version — SemVer, not CalVer.** MAJOR for a breaking API or a raised Python floor, MINOR for additive features, PATCH for fixes. Write it to `VERSION`.

1. **Gather the window.** `git fetch --tags`, then `git log --no-merges v<previous>..HEAD --pretty=format:'%h %s'` and `git diff --stat v<previous>..HEAD`. On the first tagged release the window is the whole history. Note the `BROTHERQL-NNN` ids referenced.

1. **Reconcile LuxPM (audit open → closed).** `luxpm_list_issues` for `todo` / `in_progress` / `on_hold`; for each, decide whether it shipped in this window. Close the shipped ones with a `close_summary` naming the commit; leave the rest open; reverse-check that every issue id in a commit resolves to a closed issue. The closed-this-window set is the **Issues Closed** material.

1. **Write the `CHANGELOG.md` entry — now, from the complete window.** A new `## X.Y.Z — YYYY-MM-DD` section at the top, following the existing sections (Breaking, Features, Fixes, Refactors, Infra / Ops, Notes). Reference `BROTHERQL-NNN` liberally. Lead with **Breaking**, and say what a consumer must do to upgrade.

1. **Meet the release gate** (`--doc FLEET-RELEASE-PROCESS` §0). `make check` green — or every remaining red is all four of: examined (you know why it is red), escalated (an open LuxPM issue: a guard escalation, or this repo's own issue), owner-approved to ship while red (ask the owner, one red per question, and record the answer on that issue), and recorded under a `### Known reds` heading of this version's changelog entry, one list item per red: the red in backticks, a dash, then the issue's `BROTHERQL-` key and why it is not fixable here:

   ```
   ### Known reds

   - `luxarch repo.some_rule` — BROTHERQL-61: waits on the luxarch fix for …
   ```

   Name each red exactly as `make release` reads it from the guards' status: `luxarch <rule>`, `luxlint <rule>`, `luxlint mypy`, `luxaudit vulnerable <package> <vuln_id>`, `luxaudit banned <package>` or `luxaudit not-audited <entry>` (`make release-reds`, then the `FAIL` rows and findings of the three `.lux*-reds.json` files it writes, list them; not `make status`, whose status-write luxarch run leaves `repo.guard_status_current` out). Before the release, read each named issue with `luxpm_get_context`: it is open and carries the owner's approval, or the red is not approved. Only the guard legs (`lint`, `mypy`, `arch`, `audit`) can be approved: a failing test, secret scan or `build-pins` is fixed, never recorded. A red that is merely deferred to green (`[rules.deferred]`, an XFAIL rule, a luxaudit `[[ignore]]` row) blocks the release, green gate or red: `make release` refuses it. With a green gate the entry has no `### Known reds`.

1. **Commit** the `VERSION` bump + changelog together: `git add -A && git commit`.

1. **Release**: `make release`, bare, on Linux: `scripts/release-preflight.sh` refuses any argument (`make -n release` is the dry run), anything in the environment that would steer make, git, gh or docker, a `Makefile.local` setting more than `LUX_REGISTRY` and `HEAVY_*`, a dirty tree, a branch other than `main`, a git identity other than the fleet account, and a missing changelog entry. It also stops if the checkout is behind `origin` or if the commit moves during the gate. It runs `make check` in a fresh clone of the commit, builds the sdist + wheel from a raw export of it, creates the annotated `v$(VERSION)` tag, pushes the branch and the tag, and creates the **GitHub Release** with that version's changelog section as the notes and the artifacts attached. When the clone's `make check` is red, it stops unless only the guard legs failed and every red the clone's guard status names is recorded under `### Known reds` of this version, with its issue and reason, and nothing recorded is not red (`scripts/release-known-reds.py`). It does not read LuxPM, so the owner's approval is the step above's. A tag with no Release is half a release.

1. **Mirror to LuxPM** (the fleet index): `luxpm_create_release(project_id=<BROTHERQL>, version="X.Y.Z", status="released", release_date=<today>, changelog_md=<the CHANGELOG section body>)`. A mirror of the GitHub Release, not a substitute for it.

1. **Log it.** A final activity on the issues this release shipped, carrying the tag and the gate numbers.

## Done when

`VERSION` bumped; the changelog entry written from the full window; every shipped issue closed in LuxPM (and none falsely); the gate met; `vX.Y.Z` pushed; the **GitHub Release** live on `github.com/luxardolabs/brother_ql/releases` with the notes and artifacts; and the LuxPM release mirrored. A pushed tag with an empty `/releases` page is not a release.
