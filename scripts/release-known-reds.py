"""Judge the release gate's reds against the version's `### Known reds` (FLEET-RELEASE-PROCESS 0).

Usage: release-known-reds.py <version> [failed leg ...] < <the gate's log>

Run by `make release` in the fresh clone of the judged commit, after its `make check`, with the legs
that check named as failed (none when it was green), the gate's own log on stdin and, when it was
red, the guards' `--json` of that clone (`make release-reds`: .lux*-reds.json, written the way the
gate's legs run, not in status-write mode, which hides repo.guard_status_current). A release may ship over a red only when the red is recorded in
the version's CHANGELOG.md entry, under `### Known reds`, as a list item naming the red, the issue
of this repo's LuxPM project (.luxpm-receipt) that tracks it, and why it cannot be fixed here:

    - `luxarch repo.some_rule` - BROTHERQL-61: waits on the luxarch fix for ...

Fails:
- when a guard leg reached no verdict in the gate (its make error is not `Error 1`: a guard that
  could not run, a container killed at its memory cap), whatever is recorded;
- when a leg failed that no record can approve: a test, the secret scan, build-pins, or anything
  but the guard legs lint, mypy, arch and audit;
- when a red is not recorded, or a record names no red (so the notes never list a red that shipped
  fixed), or a record has no issue key or no reason;
- when a guard leg failed and its guard's status names no red to record, when luxaudit could not
  audit a dependency set, or when a guard counts more failures than reds it names (a stale or
  expired ignore row is a deferral, which never ships);
- when the gate is green and the entry still records reds.
A red is named as `luxarch <rule>`, `luxlint <rule>`, `luxlint mypy`, `luxaudit vulnerable
<package> <vuln_id>`, `luxaudit banned <package>` or `luxaudit not-audited <entry>`.
"""

import json
import re
import sys
from pathlib import Path

APPROVABLE = {
    "lint": "luxlint",
    "mypy": "luxlint",
    "arch": "luxarch",
    "audit": "luxaudit",
}
RECORD = re.compile(r"^- `([^`]+)`\s*(?:-|—|–)\s*(.*)$")
# GNU make 4.2 and later name the target as `Makefile:N: leg`; earlier releases as `leg`.
LEG_ERROR = re.compile(
    r"^make\[\d+\]: \*\*\* \[(?:[^\]:]+:\d+: )?([\w-]+)\] Error (\d+)$"
)


def project_of(repo: Path) -> str:
    """This repo's LuxPM project, as its committed sync receipt names it."""
    receipt = repo / ".luxpm-receipt"
    if receipt.is_file():
        for line in receipt.read_text().splitlines():
            if line.startswith("project:"):
                return line.split(":", 1)[1].strip()
    return ""


def known_reds(
    changelog: str, version: str, project: str
) -> tuple[dict[str, str], list[str]]:
    """The records of the version's `### Known reds`, and the lines in it that are not records."""
    records: dict[str, str] = {}
    malformed: list[str] = []
    in_entry = in_reds = False
    for line in changelog.splitlines():
        if line.startswith("## "):
            in_entry = line.startswith(f"## {version} ")
            in_reds = False
            continue
        if not in_entry:
            continue
        if line.startswith("### "):
            in_reds = line.strip() == "### Known reds"
            continue
        if not in_reds or not line.strip():
            continue
        match = RECORD.match(line)
        if not match:
            malformed.append(f"not a record: {line}")
            continue
        red, rest = match.group(1).strip(), match.group(2)
        # The key opens the text after the dash and is an issue of this repo's project, where the
        # fleet files a Known red's escalation or ticket; an advisory id (CVE-2026-1) is no key.
        issue = re.match(rf"{re.escape(project)}-\d+\b", rest) if project else None
        reason = rest[issue.end() :].lstrip(" :—–-").strip() if issue else ""
        if not issue or not reason:
            malformed.append(
                f"needs an issue key of {project or 'this repo'} and why it is not fixable here: {line}"
            )
        records[red] = line
    return records, malformed


def leg_errors(log: str) -> dict[str, list[str]]:
    """Each leg's make error codes in the gate's log (make runs in the C locale there)."""
    errors: dict[str, list[str]] = {}
    for line in log.splitlines():
        match = LEG_ERROR.match(line.strip())
        if match:
            errors.setdefault(match.group(1), []).append(match.group(2))
    return errors


def guard_reds(repo: Path) -> tuple[dict[str, str], list[str]]:
    """Every red the three guards' status files name, keyed as the records name them, and the
    problems that leave a red no record can approve: a scan that could not run, or a failure the
    guard counts but names nothing for (a stale or expired ignore row is a deferral, and blocks)."""
    reds: dict[str, str] = {}
    rows = {"luxarch": 0, "luxlint": 0, "luxaudit": 0}
    problems: list[str] = []
    arch = json.loads((repo / ".luxarch-reds.json").read_text())
    for rule in arch["shared"]["rules"] + [
        r for t in arch["targets"] for r in t["rules"]
    ]:
        if rule["status"] == "FAIL" or rule.get("crashed"):
            reds[f"luxarch {rule['rule']}"] = "luxarch"
            rows["luxarch"] += 1
    lint = json.loads((repo / ".luxlint-reds.json").read_text())
    for rule in lint["rules"]:
        if rule["status"] == "FAIL":
            reds[f"luxlint {rule['rule']}"] = "luxlint"
            rows["luxlint"] += 1
    audit = json.loads((repo / ".luxaudit-reds.json").read_text())
    if audit.get("error") or audit.get("errors"):
        problems.append(
            "luxaudit could not audit every dependency set, so no record can approve its leg: "
            f"{audit.get('error') or audit.get('errors')}"
        )
    for finding in audit["vulnerable"]:
        reds[f"luxaudit vulnerable {finding['package']} {finding['vuln_id']}"] = (
            "luxaudit"
        )
        rows["luxaudit"] += 1
    for finding in audit["banned"]:
        name = finding["package"] if isinstance(finding, dict) else finding
        reds[f"luxaudit banned {name}"] = "luxaudit"
        rows["luxaudit"] += 1
    for entry in audit["not_audited"]:
        name = (
            entry.get("entry", json.dumps(entry, sort_keys=True))
            if isinstance(entry, dict)
            else entry
        )
        reds[f"luxaudit not-audited {name}"] = "luxaudit"
    for guard, status in (("luxarch", arch), ("luxlint", lint), ("luxaudit", audit)):
        counted = status.get("summary", {}).get("FAIL", 0)
        named = rows[guard]
        if counted > named:
            problems.append(
                f"{guard}'s status counts {counted} failure(s) but names {named} red(s) "
                "a Known red can record: fix the rest"
            )
    return reds, problems


def leg_reds(leg: str, reds: dict[str, str]) -> list[str]:
    """The reds a failed leg answers to: mypy's is its own, lint's are luxlint's rules."""
    if leg == "mypy":
        return [r for r in reds if r == "luxlint mypy"]
    if leg == "lint":
        return [r for r, g in reds.items() if g == "luxlint" and r != "luxlint mypy"]
    return [r for r, g in reds.items() if g == APPROVABLE[leg]]


def judge(repo: Path, version: str, legs: list[str], log: str) -> list[str]:
    """The problems that stop the release; none means the gate is met."""
    records, problems = known_reds(
        (repo / "CHANGELOG.md").read_text(), version, project_of(repo)
    )
    if not legs:
        problems += [
            f"the gate is green, but {version} records a Known red: {r}"
            for r in records
        ]
        return problems
    blocking = [leg for leg in legs if leg not in APPROVABLE]
    if blocking:
        return problems + [
            f"make check failed in {' '.join(blocking)}, which no Known red can approve: fix it"
        ]
    errors = leg_errors(log)
    for leg in legs:
        if errors.get(leg) != ["1"]:
            problems.append(
                f"make check's {leg} leg reached no verdict (make error {' '.join(errors.get(leg, [])) or 'not found'}, "
                "not Error 1), so no record can approve it: make the guard run"
            )
    if problems:
        return problems
    reds, unnamed = guard_reds(repo)
    problems += unnamed
    if "mypy" in legs:
        reds["luxlint mypy"] = "luxlint"
    for leg in legs:
        if not leg_reds(leg, reds):
            problems.append(
                f"make check failed in {leg}, but {APPROVABLE[leg]}'s status names no red to record"
            )
    problems += [
        f"red, and not recorded under ### Known reds of {version}: `{r}`"
        for r in sorted(reds)
        if r not in records
    ]
    problems += [
        f"recorded under ### Known reds of {version}, but not red: {records[r]}"
        for r in sorted(records)
        if r not in reds
    ]
    return problems


def main(argv: list[str]) -> int:
    version, legs = argv[1], argv[2:]
    problems = judge(Path.cwd(), version, legs, sys.stdin.read())
    for problem in problems:
        print(f"release: {problem}", file=sys.stderr)
    if problems:
        return 1
    if legs:
        print(
            f"release: every red is a Known red of {version}, each with its issue and reason"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
