#!/usr/bin/env python3
"""Real SwiftDebt CLI sampling for the R2 release benchmark."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

from r2_benchmark_support import sha256_file, summary, timed_command, tree_sha256


def comparable_report_sha256(report: dict[str, Any]) -> str:
    """Hash report behavior while retaining version provenance separately."""
    projected = dict(report)
    projected.pop("engineVersion", None)
    canonical = json.dumps(
        projected, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def run_cli_sample(
    binary: Path,
    corpus: Path,
    destination: Path,
    repository_evidence: bool,
    accepted_statuses: set[int] = {0},
) -> dict[str, Any]:
    shutil.rmtree(destination, ignore_errors=True)
    destination.mkdir(parents=True)
    report = destination / "analysis.json"
    profile = destination / "profile.json"
    sidecar = destination / "repository-evidence.json"
    command = [
        str(binary),
        "analyze",
        str(corpus),
        "--format",
        "json",
        "--jobs",
        "1",
        "--output",
        str(report),
        "--profile-output",
        str(profile),
    ]
    if repository_evidence:
        command += ["--repository-evidence", str(sidecar)]
    corpus_before = tree_sha256(corpus)
    measured = timed_command(command, accepted_statuses, destination)
    corpus_after = tree_sha256(corpus)
    if corpus_after != corpus_before:
        raise RuntimeError("benchmark command modified its frozen source corpus")
    measured["sourceSnapshotSHA256"] = corpus_after
    measured["reportSHA256"] = sha256_file(report)
    report_data = json.loads(report.read_text(encoding="utf-8"))
    measured["reportEngineVersion"] = report_data.get("engineVersion", "unavailable")
    measured["comparableReportSHA256"] = comparable_report_sha256(report_data)
    profile_data = json.loads(profile.read_text(encoding="utf-8"))
    measured["phaseWallClockNanoseconds"] = {
        phase["phase"]: phase["elapsedNanoseconds"] for phase in profile_data["phases"]
    }
    measured["createdFiles"] = sorted(
        path.relative_to(destination).as_posix()
        for path in destination.rglob("*")
        if path.is_file()
    )
    expected_files = {"analysis.json", "profile.json"}
    if repository_evidence:
        expected_files.add("repository-evidence.json")
    measured["unexpectedFiles"] = sorted(set(measured["createdFiles"]) - expected_files)
    if repository_evidence:
        repository = json.loads(sidecar.read_text(encoding="utf-8"))
        measured["repositoryEvidenceSHA256"] = sha256_file(sidecar)
        measured["repositoryEvidence"] = {
            "sourceFileCount": repository["summary"]["sourceFileCount"],
            "detectionCount": repository["summary"]["detectionCount"],
            "completeRuleCount": repository["summary"]["completeRuleCount"],
            "incompleteRuleCount": repository["summary"]["incompleteRuleCount"],
            "ruleDetectionCounts": {
                rule["ruleIdentity"]: len(rule["detections"])
                for rule in repository["rules"]
            },
            "issueCodes": sorted(
                issue["code"]
                for rule in repository["rules"]
                for issue in rule["issues"]
            ),
            "snapshotContentDigest": repository["snapshot"]["contentDigest"],
            "configuration": repository["snapshot"]["configuration"],
            "ruleSemanticRevisions": {
                rule["ruleIdentity"]: rule["semanticRevision"]
                for rule in repository["rules"]
            },
            "providers": sorted(
                {
                    (
                        capability["provider"]["name"],
                        capability["provider"]["version"],
                    )
                    for rule in repository["rules"]
                    for capability in rule["capabilities"]
                }
            ),
        }
    return measured


def validate_sample(
    sample: dict[str, Any],
    scenario: dict[str, Any],
    expected_configuration: dict[str, Any] | None = None,
    expected_provider: dict[str, Any] | None = None,
    expected_rules: dict[str, Any] | None = None,
) -> None:
    if sample["unexpectedFiles"]:
        raise RuntimeError(
            f"{scenario['id']} created unexpected files: {sample['unexpectedFiles']}"
        )
    if sample["sourceSnapshotSHA256"] != scenario["snapshotSHA256"]:
        raise RuntimeError(f"{scenario['id']} measured an unexpected source snapshot")
    if not scenario["repositoryEvidence"]:
        return
    evidence = sample["repositoryEvidence"]
    if evidence["sourceFileCount"] != scenario["sourceFileCount"]:
        raise RuntimeError(f"{scenario['id']} selected an unexpected source count")
    if evidence["ruleDetectionCounts"] != scenario["expectedDetectionCounts"]:
        raise RuntimeError(
            f"{scenario['id']} produced unexpected repository detections"
        )
    if evidence["incompleteRuleCount"] != 0 or evidence["issueCodes"]:
        raise RuntimeError(f"{scenario['id']} produced incomplete repository evidence")
    if (
        expected_configuration is not None
        and evidence["configuration"] != expected_configuration
    ):
        raise RuntimeError(
            f"{scenario['id']} used an unexpected repository configuration"
        )
    if expected_provider is not None:
        provider = [(expected_provider["name"], expected_provider["version"])]
        if evidence["providers"] != provider:
            raise RuntimeError(
                f"{scenario['id']} used an unexpected repository provider"
            )
    if expected_rules is not None:
        revisions = {
            identity: contract["semanticRevision"]
            for identity, contract in expected_rules.items()
        }
        if evidence["ruleSemanticRevisions"] != revisions:
            raise RuntimeError(
                f"{scenario['id']} used unexpected rule semantic revisions"
            )


def aggregate(samples: list[dict[str, Any]]) -> dict[str, Any]:
    phase_names = sorted(
        {name for sample in samples for name in sample["phaseWallClockNanoseconds"]}
    )
    return {
        "wallClockMilliseconds": summary(
            [sample["wallClockMilliseconds"] for sample in samples]
        ),
        "peakResidentMemoryBytes": summary(
            [sample["peakResidentMemoryBytes"] for sample in samples]
        ),
        "hostLoadAverageOneMinute": summary(
            [
                load
                for sample in samples
                for load in (
                    sample["hostLoadAverage"]["before"]["oneMinute"],
                    sample["hostLoadAverage"]["after"]["oneMinute"],
                )
            ]
        ),
        "phaseWallClockNanoseconds": {
            phase: summary(
                [
                    sample["phaseWallClockNanoseconds"][phase]
                    for sample in samples
                    if phase in sample["phaseWallClockNanoseconds"]
                ]
            )
            for phase in phase_names
        },
    }


def induced_samples(
    binary: Path,
    corpus: Path,
    root: Path,
    repository_evidence: bool,
    count: int,
) -> list[dict[str, Any]]:
    samples = []
    for index in range(count):
        components = [
            run_cli_sample(
                binary,
                corpus,
                root / f"induced-{index}-{component}",
                repository_evidence,
            )
            for component in range(2)
        ]
        unexpected = [
            item["unexpectedFiles"] for item in components if item["unexpectedFiles"]
        ]
        if unexpected:
            raise RuntimeError(f"induced sample created unexpected files: {unexpected}")
        samples.append(
            {
                "sampleIndex": index,
                "wallClockMilliseconds": sum(
                    item["wallClockMilliseconds"] for item in components
                ),
                "peakResidentMemoryBytes": max(
                    item["peakResidentMemoryBytes"] for item in components
                ),
                "componentWallClockMilliseconds": [
                    item["wallClockMilliseconds"] for item in components
                ],
                "componentHostLoadAverage": [
                    item["hostLoadAverage"] for item in components
                ],
            }
        )
    return samples
