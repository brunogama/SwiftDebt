#!/usr/bin/env python3
"""Measure real SwiftDebt source history through the public lifecycle CLI."""

from __future__ import annotations

import argparse
import json
import tempfile
import time
from pathlib import Path

from r3_representative_fixture import (
    CACHE_SOURCE_REVISION, SOURCE_REVISIONS, cache_source_states, commit, replace_sources,
    run, source_digest, source_snapshot,
)
from r3_representative_evidence_support import (
    conclusion_for, digest, introduction_profile, require_document, snapshot_metrics,
)

MAXIMUM_REVISIONS = 3
SMALL_FILE_BUDGET = 1_048_576
LARGE_FILE_BUDGET = 2_097_152


def validated_artifact(binary: Path, artifact: Path) -> dict:
    document = require_document(artifact, "swiftdebt-lifecycle", 3)
    exported = json.loads(run([str(binary), "lifecycle", "export", str(artifact)]))
    if exported != document:
        raise RuntimeError("public canonical export differs from persisted lifecycle artifact")
    return document


def query_introduction(binary: Path, artifact: Path, repository: Path, finding_id: str,
                       profile: Path, maximum_file_bytes: int) -> dict:
    profile.unlink(missing_ok=True)
    started = time.monotonic_ns()
    run([str(binary), "lifecycle", "infer-introduction", str(artifact), finding_id,
         "--repository", str(repository), "--max-revisions", str(MAXIMUM_REVISIONS),
         "--max-file-bytes", str(maximum_file_bytes), "--profile-output", str(profile),
         "--format", "json"])
    wall = time.monotonic_ns() - started
    document = validated_artifact(binary, artifact)
    conclusion = conclusion_for(document, finding_id)
    measured = introduction_profile(profile, conclusion, finding_id=finding_id,
                                    maximum_revisions=MAXIMUM_REVISIONS,
                                    maximum_file_bytes=maximum_file_bytes)
    return {"wallNanoseconds": wall, "profile": measured, "conclusion": conclusion,
            "artifactSHA256": digest(artifact.read_bytes())}


def run_cache_probe(binary: Path, checkout: Path, root: Path) -> dict:
    repository = root / "cache-repository"
    repository.mkdir()
    run(["git", "init", "-q", "--initial-branch=main", str(repository)])
    artifact = root / "cache-lifecycle.json"
    revisions = []
    documents = []
    for ordinal, sources in enumerate(cache_source_states(checkout), start=1):
        replace_sources(repository, sources)
        revision = commit(repository, ordinal)
        run([str(binary), "analyze", str(repository), "--format", "json", "--jobs", "1",
             "--lifecycle-artifact", str(artifact)])
        document = validated_artifact(binary, artifact)
        revisions.append({"fixtureRevision": revision, "sourceSHA256": source_digest(sources),
                          "sourceFiles": len(sources)})
        documents.append(document)
    if documents[0]["snapshots"][0]["detections"]:
        raise RuntimeError("real-source cache parent is not a zero-Detection snapshot")
    final_snapshot = documents[-1]["snapshots"][-1]
    selected = [item["id"] for item in final_snapshot["detections"]
                if item["rule"]["id"] == "unchecked-sendable"]
    if len(selected) != 1:
        raise RuntimeError("actual AnalysisProfiler source did not produce one unchecked-Sendable Detection")
    findings = [item["id"] for item in documents[-1]["findings"]
                if any(event["transition"].get("detection", {}).get("detectionID") == selected[0]
                       for event in item["events"])]
    if len(findings) != 1:
        raise RuntimeError("actual unchecked-Sendable Detection did not open one Finding")
    finding_id = findings[0]
    original = artifact.read_bytes()
    profile = root / "introduction-profile.json"
    cold = query_introduction(binary, artifact, repository, finding_id, profile, SMALL_FILE_BUDGET)
    warm = query_introduction(binary, artifact, repository, finding_id, profile, SMALL_FILE_BUDGET)
    if (cold["profile"]["recordingStatus"] != "accepted"
            or cold["profile"]["reusedRevisionCount"] != 0
            or warm["profile"]["recordingStatus"] != "already-present"
            or warm["profile"]["reusedRevisionCount"] < 1
            or warm["profile"]["analyzedRevisionCount"] < 1
            or warm["artifactSHA256"] != cold["artifactSHA256"]):
        raise RuntimeError("identical Introduction query did not prove mixed reuse and byte-identical replay")
    invalidated = query_introduction(binary, artifact, repository, finding_id, profile, LARGE_FILE_BUDGET)
    if (invalidated["profile"]["recordingStatus"] != "accepted"
            or invalidated["profile"]["reusedRevisionCount"] != 0):
        raise RuntimeError("changed file-size budget reused stale Introduction history")
    oracle_artifact = root / "forced-cold-lifecycle.json"
    oracle_artifact.write_bytes(original)
    forced_cold = query_introduction(binary, oracle_artifact, repository, finding_id,
                                     root / "forced-cold-profile.json", LARGE_FILE_BUDGET)
    if (forced_cold["profile"]["recordingStatus"] != "accepted"
            or forced_cold["profile"]["reusedRevisionCount"] != 0):
        raise RuntimeError("forced-cold Introduction oracle did not analyze all revisions")
    expected = {key: value for key, value in forced_cold["conclusion"].items() if key != "attempt"}
    observed = {key: value for key, value in invalidated["conclusion"].items() if key != "attempt"}
    if expected != observed:
        raise RuntimeError("invalidated Introduction differs from forced-cold conclusion")
    for sample in (cold, warm, invalidated, forced_cold):
        del sample["conclusion"]
    return {"sourceRevision": CACHE_SOURCE_REVISION, "sourceStates": revisions,
            "findingID": finding_id, "maximumRevisions": MAXIMUM_REVISIONS,
            "cold": cold, "mixedWarm": warm, "invalidated": invalidated,
            "forcedCold": forced_cold}


def run_evidence(binary: Path, checkout: Path) -> dict:
    with tempfile.TemporaryDirectory(prefix="swiftdebt-r3-real-source-") as temporary:
        root = Path(temporary)
        repository = root / "repository"
        repository.mkdir()
        run(["git", "init", "-q", "--initial-branch=main", str(repository)])
        artifact = root / "lifecycle.json"
        revisions = []
        snapshots = []
        for ordinal, revision in enumerate(SOURCE_REVISIONS, start=1):
            sources = source_snapshot(checkout, revision)
            replace_sources(repository, sources)
            fixture_revision = commit(repository, ordinal)
            started = time.monotonic_ns()
            run([str(binary), "analyze", str(repository), "--format", "json", "--jobs", "1",
                 "--lifecycle-artifact", str(artifact)])
            wall = time.monotonic_ns() - started
            document = validated_artifact(binary, artifact)
            if len(document["snapshots"]) != ordinal:
                raise RuntimeError("analysis did not append exactly one Observation Snapshot")
            snapshot_id = document["snapshots"][-1]["id"]
            revisions.append({"sourceRevision": revision, "sourceFiles": len(sources),
                              "sourceSHA256": source_digest(sources), "fixtureRevision": fixture_revision})
            snapshots.append({**snapshot_metrics(document, snapshot_id),
                              "ingestionWallNanoseconds": wall,
                              "artifactBytes": artifact.stat().st_size,
                              "artifactSHA256": digest(artifact.read_bytes())})
        if len({name for item in snapshots for name in item["detectionCountsByRule"]}) < 2:
            raise RuntimeError("fixed real-source corpus exercised fewer than two real rules")
        introduction = run_cache_probe(binary, checkout, root)
        return {"reportKind": "swiftdebt-r3-real-source-evidence", "schemaVersion": 1,
                "runnerCommit": run(["git", "rev-parse", "HEAD"], cwd=checkout).decode().strip(),
                "runnerDirty": bool(run(["git", "status", "--porcelain"], cwd=checkout)),
                "runnerSHA256": digest(Path(__file__).read_bytes()),
                "supportSHA256": digest(Path(__file__).with_name("r3_representative_evidence_support.py").read_bytes()),
                "fixtureSHA256": digest(Path(__file__).with_name("r3_representative_fixture.py").read_bytes()),
                "swiftDebtBinarySHA256": digest(binary.read_bytes()),
                "sourceRevisions": revisions, "snapshots": snapshots,
                "introduction": introduction}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-debt", type=Path, required=True)
    parser.add_argument("--checkout", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    binary = arguments.swift_debt.resolve(strict=True)
    checkout = arguments.checkout.resolve(strict=True)
    output = arguments.output.resolve()
    output.unlink(missing_ok=True)
    evidence = run_evidence(binary, checkout)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
