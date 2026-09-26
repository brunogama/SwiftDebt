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


def comparable_cache_report_sha256(report: dict[str, Any]) -> str:
    """Hash cache activity while preserving its machine-local path separately."""
    projected = json.loads(json.dumps(report))
    projected.get("storage", {}).pop("location", None)
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
    cache_state: str = "not-applicable",
    cache_path: Path | None = None,
) -> dict[str, Any]:
    shutil.rmtree(destination, ignore_errors=True)
    destination.mkdir(parents=True)
    report = destination / "analysis.json"
    profile = destination / "profile.json"
    sidecar = destination / "repository-evidence.json"
    cache_report = destination / "repository-cache-report.json"
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
        if cache_state == "disabled":
            if cache_path is not None:
                raise RuntimeError("cache-disabled samples cannot provide a cache path")
            command += [
                "--repository-cache-report",
                str(cache_report),
                "--no-repository-cache",
            ]
        elif cache_state in {"cold", "warm", "one-file-edit"}:
            if cache_path is None:
                raise RuntimeError(f"{cache_state} samples require an explicit cache path")
            command += [
                "--repository-cache",
                str(cache_path),
                "--repository-cache-report",
                str(cache_report),
            ]
        else:
            raise RuntimeError(
                "repository evidence samples require an explicit cache state"
            )
    elif cache_state != "not-applicable" or cache_path is not None:
        raise RuntimeError("cache state requires repository evidence")
    corpus_before = tree_sha256(corpus)
    measured = timed_command(command, accepted_statuses, destination)
    measured["command"] = command
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
        expected_files.update(
            {"repository-evidence.json", "repository-cache-report.json"}
        )
    measured["unexpectedFiles"] = sorted(set(measured["createdFiles"]) - expected_files)
    if repository_evidence:
        repository = json.loads(sidecar.read_text(encoding="utf-8"))
        rules = repository["rules"]
        rule_identities = [rule["ruleIdentity"] for rule in rules]
        if (
            rule_identities != sorted(rule_identities)
            or len(rule_identities) != len(set(rule_identities))
        ):
            raise RuntimeError(
                "repository evidence rules must have unique canonical identities"
            )
        measured["repositoryEvidenceSHA256"] = sha256_file(sidecar)
        measured["repositoryEvidence"] = {
            "sourceFileCount": repository["summary"]["sourceFileCount"],
            "detectionCount": repository["summary"]["detectionCount"],
            "completeRuleCount": repository["summary"]["completeRuleCount"],
            "incompleteRuleCount": repository["summary"]["incompleteRuleCount"],
            "ruleDetectionCounts": {
                rule["ruleIdentity"]: len(rule["detections"])
                for rule in rules
            },
            "issueCodes": sorted(
                issue["code"]
                for rule in rules
                for issue in rule["issues"]
            ),
            "snapshotContentDigest": repository["snapshot"]["contentDigest"],
            "configuration": repository["snapshot"]["configuration"],
            "ruleSemanticRevisions": {
                rule["ruleIdentity"]: rule["semanticRevision"]
                for rule in rules
            },
            "ruleCompletionStates": {
                rule["ruleIdentity"]: rule["completionState"] for rule in rules
            },
            "ruleProviders": {
                rule["ruleIdentity"]: sorted(
                    (
                        capability["provider"]["name"],
                        capability["provider"]["version"],
                    )
                    for capability in rule["capabilities"]
                )
                for rule in rules
            },
            "providers": sorted(
                {
                    (
                        capability["provider"]["name"],
                        capability["provider"]["version"],
                    )
                    for rule in rules
                    for capability in rule["capabilities"]
                }
            ),
        }
        activity = json.loads(cache_report.read_text(encoding="utf-8"))
        invalidations = activity["invalidations"]
        invalidation_reasons = [item["reason"] for item in invalidations]
        if (
            invalidation_reasons != sorted(invalidation_reasons)
            or len(invalidation_reasons) != len(set(invalidation_reasons))
        ):
            raise RuntimeError(
                "repository cache report invalidations must be unique and canonical"
            )
        measured["repositoryCacheReportSHA256"] = sha256_file(cache_report)
        measured["comparableRepositoryCacheReportSHA256"] = (
            comparable_cache_report_sha256(activity)
        )
        measured["repositoryCacheActivity"] = {
            "reportKind": activity["reportKind"],
            "schemaVersion": activity["schemaVersion"],
            "sourceSnapshotDigest": activity["sourceSnapshotDigest"],
            "mode": activity["mode"],
            "disposition": activity["disposition"],
            "compatibility": activity["compatibility"],
            "storage": activity["storage"],
            "selectedSourceCount": activity["selectedSourceCount"],
            "reusedSourceCount": activity["reusedSourceCount"],
            "recomputedSourceCount": activity["recomputedSourceCount"],
            "removedSourceCount": activity["removedSourceCount"],
            "invalidations": {
                invalidation["reason"]: invalidation["sourceCount"]
                for invalidation in invalidations
            },
            "networkRequestCount": activity["networkRequestCount"],
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
    expected_detection_count = sum(scenario["expectedDetectionCounts"].values())
    expected_rule_count = len(scenario["expectedDetectionCounts"])
    if (
        evidence["detectionCount"] != expected_detection_count
        or evidence["completeRuleCount"] != expected_rule_count
        or evidence["incompleteRuleCount"] != 0
        or set(evidence["ruleCompletionStates"].values()) != {"complete"}
        or evidence["issueCodes"]
    ):
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
        expected_rule_providers = {
            identity: provider for identity in scenario["expectedDetectionCounts"]
        }
        if (
            evidence["providers"] != provider
            or evidence["ruleProviders"] != expected_rule_providers
        ):
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
