"""Judge the release gate's reds against the version's `### Known reds` (FLEET-RELEASE-PROCESS 0).

Usage: release-known-reds.py <version> [failed leg ...]

Run by `make release` in the fresh clone of the judged commit, after its `make check`, with the legs
that check named as failed (none when it was green) and, when it was red, the guard status files a
`make status` of that clone wrote. A release may ship over a red only when the red is recorded in
the version's CHANGELOG.md entry, under `### Known reds`, as a list item naming the red, the issue
that tracks it and why it cannot be fixed here:

    - `luxarch repo.some_rule` - BROTHERQL-61: waits on the luxarch fix for ...

Fails:
- when a leg failed that no record can approve: a test, the secret scan, build-pins, or anything
  but the guard legs lint, mypy, arch and audit;
- when a red is not recorded, or a record names no red (so the notes never list a red that shipped
  fixed), or a record has no issue key or no reason;
- when a guard leg failed and its guard's status names no red to record;
- when the gate is green and the entry still records reds.
A red is named as `luxarch <rule>`, `luxlint <rule>`, `luxlint mypy`, `luxaudit vulnerable
<package> <vuln_id>`, `luxaudit banned <package>` or `luxaudit not-audited <entry>`.
"""

import json
import re
import sys
from pathlib import Path

APPROVABLE = {"lint": "luxlint", "mypy": "luxlint", "arch": "luxarch", "audit": "luxaudit"}
ISSUE = re.compile(r"\b[A-Z][A-Z0-9]+-\d+\b")
RECORD = re.compile(r"^- `([^`]+)`\s*(?:-|—|–)\s*(.*)$")


def known_reds(changelog, version):
    """The records of the version's `### Known reds`, and the lines in it that are not records."""
    records, malformed = {}, []
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
        issue = ISSUE.search(rest)
        reason = rest[issue.end() :].lstrip(" :—–-").strip() if issue else ""
        if not issue or not reason:
            malformed.append(f"needs an issue key and why it is not fixable here: {line}")
        records[red] = line
    return records, malformed


def guard_reds(repo):
    """Every red the three guards' status files name, keyed as the records name them."""
    reds = {}
    arch = json.loads((repo / ".luxarch-status.json").read_text())
    for rule in arch["shared"]["rules"] + [r for t in arch["targets"] for r in t["rules"]]:
        if rule["status"] == "FAIL" or rule.get("crashed"):
            reds[f"luxarch {rule['rule']}"] = "luxarch"
    lint = json.loads((repo / ".luxlint-status.json").read_text())
    for rule in lint["rules"]:
        if rule["status"] == "FAIL":
            reds[f"luxlint {rule['rule']}"] = "luxlint"
    audit = json.loads((repo / ".luxaudit-status.json").read_text())
    for finding in audit["vulnerable"]:
        reds[f"luxaudit vulnerable {finding['package']} {finding['vuln_id']}"] = "luxaudit"
    for finding in audit["banned"]:
        name = finding["package"] if isinstance(finding, dict) else finding
        reds[f"luxaudit banned {name}"] = "luxaudit"
    for entry in audit["not_audited"]:
        name = entry.get("entry", json.dumps(entry, sort_keys=True)) if isinstance(entry, dict) else entry
        reds[f"luxaudit not-audited {name}"] = "luxaudit"
    return reds


def judge(repo, version, legs):
    """The problems that stop the release; none means the gate is met."""
    records, problems = known_reds((repo / "CHANGELOG.md").read_text(), version)
    if not legs:
        problems += [f"the gate is green, but {version} records a Known red: {r}" for r in records]
        return problems
    blocking = [leg for leg in legs if leg not in APPROVABLE]
    if blocking:
        return problems + [
            f"make check failed in {' '.join(blocking)}, which no Known red can approve: fix it"
        ]
    reds = guard_reds(repo)
    if "mypy" in legs:
        reds["luxlint mypy"] = "luxlint"
    for leg in legs:
        if APPROVABLE[leg] not in reds.values():
            problems.append(f"make check failed in {leg}, but {APPROVABLE[leg]}'s status names no red to record")
    problems += [f"red, and not recorded under ### Known reds of {version}: `{r}`" for r in sorted(reds) if r not in records]
    problems += [f"recorded under ### Known reds of {version}, but not red: {records[r]}" for r in sorted(records) if r not in reds]
    return problems


def main(argv):
    version, legs = argv[1], argv[2:]
    problems = judge(Path.cwd(), version, legs)
    for problem in problems:
        print(f"release: {problem}", file=sys.stderr)
    if problems:
        return 1
    if legs:
        print(f"release: every red is a Known red of {version}, each with its issue and reason")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
