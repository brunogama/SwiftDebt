"""Strict readers for public lifecycle artifacts and introduction profiles."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require_document(path: Path, kind: str, schema: int) -> dict:
    document = json.loads(path.read_bytes())
    if not isinstance(document, dict) or document.get("reportKind") != kind or document.get("schemaVersion") != schema:
        raise RuntimeError(f"{path}: unexpected report kind or schema")
    return document


def snapshot_metrics(artifact: dict, snapshot_id: str) -> dict:
    snapshots = artifact.get("snapshots")
    findings = artifact.get("findings")
    unresolved = artifact.get("unresolvedDetections")
    if not all(isinstance(value, list) for value in (snapshots, findings, unresolved)):
        raise RuntimeError("lifecycle artifact omits snapshot, Finding, or unresolved evidence")
    matching = [item for item in snapshots if item.get("id") == snapshot_id]
    if len(matching) != 1:
        raise RuntimeError("expected exactly one matching Observation Snapshot")
    snapshot = matching[0]
    detections = snapshot.get("detections")
    rules = snapshot.get("rules")
    if not isinstance(detections, list) or not isinstance(rules, list):
        raise RuntimeError("Observation Snapshot omits rule or Detection evidence")
    events = [event for finding in findings for event in finding.get("events", [])
              if event.get("snapshotID") == snapshot_id]
    kinds = [event.get("transition", {}).get("kind") for event in events]
    if any(kind not in {"opened", "observed", "reopened", "resolved", "unverified", "continuity-ambiguous"}
           for kind in kinds):
        raise RuntimeError("unknown Lifecycle Event kind")
    unresolved_here = [item for item in unresolved if item.get("snapshotID") == snapshot_id]
    unique = kinds.count("observed") + kinds.count("reopened")
    opened = kinds.count("opened")
    if unique + opened + len(unresolved_here) != len(detections):
        raise RuntimeError("Detection outcomes do not account for every canonical Detection")
    by_rule: dict[str, int] = {}
    for detection in detections:
        rule = detection.get("rule", {})
        name = f"{rule.get('namespace')}.{rule.get('id')}@{rule.get('semanticRevision')}"
        if "None" in name or not isinstance(rule.get("semanticRevision"), int):
            raise RuntimeError("Detection has incomplete Rule Identity")
        by_rule[name] = by_rule.get(name, 0) + 1
    denominator = len(detections)
    return {
        "snapshotID": snapshot_id,
        "detections": denominator,
        "rulesSelected": len(rules),
        "detectionCountsByRule": dict(sorted(by_rule.items())),
        "uniqueContinuity": unique,
        "newFindings": opened,
        "unresolvedDetections": len(unresolved_here),
        "continuityAmbiguities": kinds.count("continuity-ambiguous"),
        "rates": {
            "uniqueContinuity": unique / denominator if denominator else None,
            "newFindings": opened / denominator if denominator else None,
            "unresolvedDetections": len(unresolved_here) / denominator if denominator else None,
            "continuityAmbiguitiesPerDetection": kinds.count("continuity-ambiguous") / denominator if denominator else None,
        },
    }


def introduction_profile(path: Path, conclusion: dict, *, finding_id: str,
                         maximum_revisions: int, maximum_file_bytes: int) -> dict:
    profile = require_document(path, "swiftdebt-lifecycle-introduction-profile", 1)
    evidence = conclusion.get("evidence", {})
    revisions = evidence.get("revisions")
    frontier = evidence.get("boundary", {}).get("frontierRevisions")
    fields = ("evidenceRevisionCount", "analyzedRevisionCount", "reusedRevisionCount",
              "frontierRevisionCount", "operationElapsedNanoseconds")
    if (profile.get("findingID") != finding_id or conclusion.get("findingID") != finding_id
            or profile.get("maximumRevisions") != maximum_revisions
            or profile.get("maximumFileBytes") != maximum_file_bytes
            or profile.get("recordingStatus") not in {"accepted", "already-present"}
            or not isinstance(revisions, list) or not isinstance(frontier, list)
            or any(type(profile.get(field)) is not int or profile[field] < 0 for field in fields)
            or profile["operationElapsedNanoseconds"] == 0
            or profile["evidenceRevisionCount"] != len(revisions)
            or profile["frontierRevisionCount"] != len(frontier)
            or profile["evidenceRevisionCount"] != profile["analyzedRevisionCount"] + profile["reusedRevisionCount"]
            or profile["evidenceRevisionCount"] > maximum_revisions):
        raise RuntimeError("introduction profile does not match persisted evidence")
    return profile


def conclusion_for(artifact: dict, finding_id: str) -> dict:
    matches = [item for item in artifact.get("introductionConclusions", [])
               if item.get("findingID") == finding_id]
    if not matches:
        raise RuntimeError("bounded Introduction Conclusion is absent")
    return max(matches, key=lambda item: item["attempt"])
