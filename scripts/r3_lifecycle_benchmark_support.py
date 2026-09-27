"""Generated Git fixtures and artifact summaries for the R3 lifecycle benchmark."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

PADDING_LINES = 48


def _git(argv: list[str], repository: Path | None = None) -> str:
    result = subprocess.run(
        ["git", *argv], cwd=repository, env={**os.environ, "LC_ALL": "C"},
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"Git fixture command failed: {' '.join(argv)}\n"
                           + result.stderr.decode(errors="replace")[-4000:])
    return result.stdout.decode().strip()


def source(index: int, *, detected: bool) -> str:
    name = f"operation{index:05d}"
    body = f"func {name}(_ input: Int) throws -> Int {{ input + 1 }}\n"
    body += (f"func use{index:05d}(_ input: Int) -> Int {{ try! {name}(input) }}\n"
             if detected else f"func use{index:05d}(_ input: Int) -> Int {{ input }}\n")
    body += "".join(f"// Stable fixture line {line:02d} in {name}\n" for line in range(PADDING_LINES))
    return body


def commit(repository: Path, message: str, ordinal: int) -> str:
    environment = {**os.environ, "LC_ALL": "C", "GIT_AUTHOR_DATE": f"2026-01-{ordinal:02d}T12:00:00Z",
                   "GIT_COMMITTER_DATE": f"2026-01-{ordinal:02d}T12:00:00Z"}
    for argv in (["git", "add", "-A"], ["git", "commit", "-qm", message]):
        result = subprocess.run(argv, cwd=repository, env=environment,
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, check=False)
        if result.returncode:
            raise RuntimeError(f"Git fixture commit failed: {' '.join(argv)}\n"
                               + result.stderr.decode(errors="replace")[-4000:])
    return _git(["rev-parse", "HEAD"], repository)


def fixture(repository: Path, source_count: int) -> tuple[str, str]:
    _git(["init", "-q", "--initial-branch=main", str(repository)])
    for key, value in (("user.name", "SwiftDebt Benchmark"),
                       ("user.email", "benchmark@example.invalid"),
                       ("commit.gpgsign", "false"), ("core.autocrlf", "false")):
        _git(["config", key, value], repository)
    source_dir = repository / "Sources"
    source_dir.mkdir()
    for index in range(source_count):
        (source_dir / f"File{index:05d}.swift").write_text(source(index, detected=False))
    absent = commit(repository, "add clean benchmark sources", 1)
    for index in range(source_count):
        (source_dir / f"File{index:05d}.swift").write_text(source(index, detected=True))
    detected = commit(repository, "introduce benchmark debt", 2)
    return absent, detected


def artifact_info(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    document = json.loads(data)
    findings = document["findings"]
    events = [event for finding in findings for event in finding["events"]]
    kinds = {kind: sum(event["transition"]["kind"] == kind for event in events)
             for kind in ("opened", "observed", "resolved", "reopened", "unverified",
                          "continuity-ambiguous")}
    return {
        "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "snapshots": len(document["snapshots"]), "findings": len(findings),
        "events": len(events), "unresolvedDetections": len(document["unresolvedDetections"]),
        "introductionConclusions": len(document.get("introductionConclusions", [])),
        "eventKinds": kinds,
    }


def validate_inventory(output: str, findings: list[dict], snapshot_id: str) -> None:
    report = json.loads(output)
    expected_ids = {finding["id"] for finding in findings}
    reported = report.get("findings", [])
    if (report.get("reportKind") != "swiftdebt-lifecycle-inventory"
            or report.get("headSnapshotIDs") != [snapshot_id]
            or len(reported) != len(findings)
            or {finding.get("id") for finding in reported} != expected_ids
            or report.get("unresolvedDetections") != []
            or any(finding.get("lifecycleState") != "open"
                   or finding.get("evidenceState") != "observed" for finding in reported)):
        raise RuntimeError("inventory JSON did not describe the expected open Findings")


def validate_explanation(output: str, finding: dict, snapshot_id: str) -> None:
    report = json.loads(output)
    reported = report.get("finding", {})
    projections = report.get("projections", [])
    if (report.get("reportKind") != "swiftdebt-lifecycle-finding-explanation"
            or reported.get("id") != finding["id"]
            or reported.get("events") != finding["events"]
            or len(projections) != 1
            or projections[0].get("snapshotID") != snapshot_id
            or projections[0].get("finding", {}).get("id") != finding["id"]
            or {snapshot.get("id") for snapshot in report.get("supportingSnapshots", [])}
               != {snapshot_id}
            or report.get("unresolvedDetections") != []):
        raise RuntimeError("explanation JSON did not describe the selected Finding")


def validate_introduction_profile(
    profile_json: str,
    conclusion: dict,
    *,
    finding_id: str,
    maximum_revisions: int,
    maximum_file_bytes: int,
    recording_status: str,
) -> dict[str, int | str]:
    profile = json.loads(profile_json)
    evidence = conclusion.get("evidence", {})
    revisions = evidence.get("revisions")
    boundary = evidence.get("boundary", {})
    frontier = boundary.get("frontierRevisions")
    numeric_fields = (
        "evidenceRevisionCount",
        "analyzedRevisionCount",
        "reusedRevisionCount",
        "frontierRevisionCount",
        "operationElapsedNanoseconds",
    )
    if (
        profile.get("reportKind") != "swiftdebt-lifecycle-introduction-profile"
        or profile.get("schemaVersion") != 1
        or profile.get("findingID") != finding_id
        or conclusion.get("findingID") != finding_id
        or profile.get("maximumRevisions") != maximum_revisions
        or boundary.get("maximumRevisions") != maximum_revisions
        or profile.get("maximumFileBytes") != maximum_file_bytes
        or profile.get("recordingStatus") != recording_status
        or not isinstance(revisions, list)
        or not isinstance(frontier, list)
        or any(type(profile.get(field)) is not int for field in numeric_fields)
        or any(profile[field] < 0 for field in numeric_fields)
        or profile["operationElapsedNanoseconds"] == 0
        or profile["evidenceRevisionCount"] != len(revisions)
        or profile["frontierRevisionCount"] != len(frontier)
        or profile["evidenceRevisionCount"]
        != profile["analyzedRevisionCount"] + profile["reusedRevisionCount"]
        or profile["evidenceRevisionCount"] > maximum_revisions
    ):
        raise RuntimeError("introduction profile does not match persisted bounded history evidence")
    return {
        field: profile[field]
        for field in (
            "reportKind",
            "schemaVersion",
            "findingID",
            "maximumRevisions",
            "maximumFileBytes",
            *numeric_fields,
            "recordingStatus",
        )
    }


def validate_incremental_artifact(cold_bytes: bytes, incremental_bytes: bytes, source_count: int) -> None:
    cold = json.loads(cold_bytes)
    incremental = json.loads(incremental_bytes)
    old_findings = cold["findings"]
    findings = incremental["findings"]
    old_ids = {finding["id"] for finding in old_findings}
    new_ids = {finding["id"] for finding in findings}
    snapshots = incremental["snapshots"]
    if (len(old_findings) != source_count or len(findings) != source_count
            or len(new_ids) != source_count or new_ids != old_ids
            or len(snapshots) != 2
            or incremental["unresolvedDetections"] != []
            or any([event["transition"]["kind"] for event in finding["events"]]
                   != ["opened", "observed"] for finding in findings)):
        raise RuntimeError("incremental analysis did not preserve uniquely observed Finding continuity")
    shifted = [detection for detection in snapshots[-1]["detections"]
               if detection["location"]["sourcePath"] == "Sources/File00000.swift"
               and detection["rule"]["id"] == "force-try"]
    if len(shifted) != 1 or shifted[0]["location"]["line"] != 3:
        raise RuntimeError("incremental analysis did not observe the shifted ForceTry Detection")


def validate_incremental_profile(profile_json: str, incremental_bytes: bytes, source_count: int) -> dict[str, int]:
    """Bind the opt-in reconciliation measurements to the observed snapshot."""
    profile = json.loads(profile_json)
    artifact = json.loads(incremental_bytes)
    records = profile.get("lifecycleReconciliation")
    if profile.get("schemaVersion") != 1 or not isinstance(records, list) or len(records) != 1:
        raise RuntimeError("incremental profile must contain one reconciliation record")
    record = records[0]
    if not isinstance(record, dict):
        raise RuntimeError("incremental profile has an invalid reconciliation record")
    expected_snapshot_id = artifact["snapshots"][-1]["id"]
    if record.get("snapshotID") != expected_snapshot_id:
        raise RuntimeError("incremental profile describes a different Snapshot")
    fields = (
        "detections", "candidates", "evaluatedPairs", "crediblePairs",
        "uniqueContinuities", "newFindings", "unresolvedDetections",
        "ambiguousGroups", "processingElapsedNanoseconds",
        "reconciliationElapsedNanoseconds",
    )
    if any(type(record.get(field)) is not int or record[field] < 0 for field in fields):
        raise RuntimeError("incremental profile has invalid reconciliation measurements")
    if (record["detections"] != source_count
            or record["candidates"] != source_count
            or record["uniqueContinuities"] != source_count
            or record["newFindings"] != 0
            or record["unresolvedDetections"] != len(artifact["unresolvedDetections"])
            or record["ambiguousGroups"] != 0
            or record["evaluatedPairs"] != source_count * source_count
            or record["crediblePairs"] != source_count
            or not 0 < record["reconciliationElapsedNanoseconds"]
            <= record["processingElapsedNanoseconds"]):
        raise RuntimeError("incremental profile does not match observed Finding continuity")
    return {field: record[field] for field in fields}


def largest_artifact_bytes(tier: dict) -> int:
    return max(tier[name]["bytes"] for name in
               ("coldArtifact", "incrementalArtifact", "introductionArtifact"))
