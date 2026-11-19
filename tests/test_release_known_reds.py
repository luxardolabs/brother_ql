"""scripts/release-known-reds.py: a release ships over a red only when the red is a Known red.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import importlib.util
import json
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "release-known-reds.py"
spec = importlib.util.spec_from_file_location("release_known_reds", SCRIPT)
known = importlib.util.module_from_spec(spec)
spec.loader.exec_module(known)

ENTRY = """# Changelog

## 2.1.0 — 2026-11-20

### Fixes

- Something (BROTHERQL-60).
{reds}
## 2.0.3 — 2026-11-07

### Known reds

- `luxarch repo.older_rule` — BROTHERQL-9: an older release's record.
"""


def rule(name, status="PASS", **extra):
    return {"rule": name, "status": status, **extra}


def repo(tmp_path, reds="", arch=(), lint=(), vulnerable=()):
    """A clone as the release judges it: its CHANGELOG and the guard status `make status` wrote."""
    (tmp_path / "CHANGELOG.md").write_text(ENTRY.format(reds=reds))
    (tmp_path / ".luxarch-status.json").write_text(
        json.dumps(
            {
                "shared": {"rules": [rule("repo.fine"), *arch]},
                "targets": [{"kind": "library", "rules": [rule("library.layout")]}],
            }
        )
    )
    (tmp_path / ".luxlint-status.json").write_text(
        json.dumps({"rules": [rule("lint.ruff"), *lint]})
    )
    (tmp_path / ".luxaudit-status.json").write_text(
        json.dumps({"vulnerable": list(vulnerable), "banned": [], "not_audited": []})
    )
    return tmp_path


RECORDED = "\n### Known reds\n\n- `luxarch repo.new_rule` — BROTHERQL-61: waits on the luxarch fix.\n"


def test_a_green_gate_with_no_records_passes(tmp_path):
    assert known.judge(repo(tmp_path), "2.1.0", []) == []


def test_a_recorded_red_with_its_issue_and_reason_passes(tmp_path):
    clone = repo(tmp_path, RECORDED, arch=[rule("repo.new_rule", "FAIL")])
    assert known.judge(clone, "2.1.0", ["arch"]) == []


def test_an_unrecorded_red_stops_the_release(tmp_path):
    clone = repo(tmp_path, arch=[rule("repo.new_rule", "FAIL")])
    problems = known.judge(clone, "2.1.0", ["arch"])
    assert problems == [
        "red, and not recorded under ### Known reds of 2.1.0: `luxarch repo.new_rule`"
    ]


def test_a_record_of_a_red_that_is_not_red_stops_the_release(tmp_path):
    clone = repo(tmp_path, RECORDED, lint=[rule("lint.format", "FAIL")])
    problems = known.judge(clone, "2.1.0", ["lint"])
    assert (
        "red, and not recorded under ### Known reds of 2.1.0: `luxlint lint.format`"
        in problems
    )
    assert any("but not red" in p and "repo.new_rule" in p for p in problems)


def test_a_green_gate_that_still_records_reds_stops_the_release(tmp_path):
    problems = known.judge(repo(tmp_path, RECORDED), "2.1.0", [])
    assert len(problems) == 1
    assert problems[0].startswith("the gate is green, but 2.1.0 records a Known red")


def test_a_record_without_an_issue_or_a_reason_stops_the_release(tmp_path):
    for record in (
        "- `luxarch repo.new_rule` — waits on the fix.",
        "- `luxarch repo.new_rule` — BROTHERQL-61",
    ):
        clone = repo(
            tmp_path,
            f"\n### Known reds\n\n{record}\n",
            arch=[rule("repo.new_rule", "FAIL")],
        )
        problems = known.judge(clone, "2.1.0", ["arch"])
        assert any("needs an issue key and why" in p for p in problems), record


def test_a_failing_test_or_secret_scan_is_never_a_known_red(tmp_path):
    for leg in ("test", "gitleaks", "build-pins"):
        problems = known.judge(repo(tmp_path, RECORDED), "2.1.0", ["arch", leg])
        assert (
            problems[-1]
            == f"make check failed in {leg}, which no Known red can approve: fix it"
        )


def test_a_failed_guard_leg_whose_guard_names_no_red_stops_the_release(tmp_path):
    problems = known.judge(repo(tmp_path), "2.1.0", ["audit"])
    assert problems == [
        "make check failed in audit, but luxaudit's status names no red to record"
    ]


def test_audit_findings_and_mypy_are_recorded_by_name(tmp_path):
    reds = (
        "\n### Known reds\n\n"
        "- `luxaudit vulnerable pillow PYSEC-2026-1` — BROTHERQL-62: no fixed Pillow yet.\n"
        "- `luxlint mypy` — BROTHERQL-63: waits on a stub luxlint bakes.\n"
    )
    clone = repo(
        tmp_path, reds, vulnerable=[{"package": "pillow", "vuln_id": "PYSEC-2026-1"}]
    )
    assert known.judge(clone, "2.1.0", ["audit", "mypy"]) == []


def test_another_versions_records_are_not_this_ones(tmp_path):
    clone = repo(tmp_path, arch=[rule("repo.older_rule", "FAIL")])
    problems = known.judge(clone, "2.1.0", ["arch"])
    assert problems == [
        "red, and not recorded under ### Known reds of 2.1.0: `luxarch repo.older_rule`"
    ]


def test_an_audit_that_could_not_run_stops_the_release_whatever_is_recorded(tmp_path):
    reds = "\n### Known reds\n\n- `luxaudit vulnerable pillow PYSEC-2026-1` — BROTHERQL-62: no fix yet.\n"
    clone = repo(
        tmp_path, reds, vulnerable=[{"package": "pillow", "vuln_id": "PYSEC-2026-1"}]
    )
    status = json.loads((clone / ".luxaudit-status.json").read_text())
    status["error"] = "requirements/missing.txt: no such file"
    status["summary"] = {"FAIL": 1}
    (clone / ".luxaudit-status.json").write_text(json.dumps(status))
    problems = known.judge(clone, "2.1.0", ["audit"])
    assert any("luxaudit could not audit" in p for p in problems), problems


def test_a_failure_the_judge_cannot_name_stops_the_release(tmp_path):
    # A stale [[ignore]] row counts as a luxaudit failure but is no finding to record: a deferral blocks.
    reds = "\n### Known reds\n\n- `luxaudit vulnerable pillow PYSEC-2026-1` — BROTHERQL-62: no fix yet.\n"
    clone = repo(
        tmp_path, reds, vulnerable=[{"package": "pillow", "vuln_id": "PYSEC-2026-1"}]
    )
    status = json.loads((clone / ".luxaudit-status.json").read_text())
    status["summary"] = {"FAIL": 2}
    (clone / ".luxaudit-status.json").write_text(json.dumps(status))
    problems = known.judge(clone, "2.1.0", ["audit"])
    assert problems == [
        "luxaudit's status counts 2 failure(s) but names 1 red(s) a Known red can record: fix the rest"
    ]


def test_a_mypy_record_does_not_answer_a_failed_lint_leg(tmp_path):
    reds = "\n### Known reds\n\n- `luxlint mypy` — BROTHERQL-63: waits on a stub luxlint bakes.\n"
    problems = known.judge(repo(tmp_path, reds), "2.1.0", ["lint", "mypy"])
    assert (
        "make check failed in lint, but luxlint's status names no red to record"
        in problems
    )


def test_a_crashed_rule_is_a_red(tmp_path):
    clone = repo(tmp_path, arch=[rule("repo.flaky", "PASS", crashed=True)])
    problems = known.judge(clone, "2.1.0", ["arch"])
    assert problems == [
        "red, and not recorded under ### Known reds of 2.1.0: `luxarch repo.flaky`"
    ]
