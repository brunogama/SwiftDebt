#!/usr/bin/env python3
"""Calibrate the versioned R2 release performance scenarios with the real CLI."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from r2_benchmark_scenarios import (
    exhaustion_proof,
    measure_relative,
    measure_repository,
)
from r2_benchmark_support import (
    atomic_json,
    environment_metadata,
    generate_scale_corpus,
    sha256_file,
)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--manifest", required=True, type=Path)
    result.add_argument("--reference-binary", required=True, type=Path)
    result.add_argument("--reference-root", required=True, type=Path)
    result.add_argument("--candidate-binary", required=True, type=Path)
    result.add_argument("--candidate-root", required=True, type=Path)
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--work-directory", type=Path)
    return result


def git_output(root: Path, arguments: list[str]) -> str:
    completed = subprocess.run(
        ["git", "-C", str(root), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "git command failed")
    return completed.stdout.strip()


def validate_source(root: Path, commit: str) -> None:
    git_output(root, ["cat-file", "-e", f"{commit}^{{commit}}"])
    completed = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "diff",
            "--quiet",
            commit,
            "--",
            "Package.swift",
            "Package.resolved",
            "Sources",
        ],
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"{root} does not match source commit {commit}")
    untracked = git_output(
        root,
        [
            "ls-files",
            "--others",
            "--exclude-standard",
            "--",
            "Package.swift",
            "Package.resolved",
            "Sources",
        ],
    )
    if untracked:
        raise RuntimeError(f"{root} has untracked source inputs: {untracked}")


def validate_distinct_binaries(reference: Path, candidate: Path) -> None:
    if reference == candidate:
        raise RuntimeError("reference and candidate binaries must be distinct paths")


def validate_binary(root: Path, binary: Path) -> None:
    try:
        binary.relative_to(root.resolve())
    except ValueError as error:
        raise RuntimeError(
            f"benchmark binary {binary} is outside source root {root}"
        ) from error
    if not os.access(binary, os.X_OK):
        raise RuntimeError(f"benchmark binary is not executable: {binary}")


def validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("schemaVersion") != 1:
        raise RuntimeError("release benchmark manifest schemaVersion must be 1")
    measurement = manifest["measurement"]
    if measurement["warmupRuns"] < 5 or measurement["measuredRuns"] < 30:
        raise RuntimeError(
            "release calibration requires at least 5 warmups and 30 measured runs"
        )
    if measurement["inducedRegressionRuns"] <= 0:
        raise RuntimeError("induced regression proof requires measured samples")
    maximum_load = manifest["budgetPolicy"].get("maximumObservedOneMinuteLoad")
    expected_load = manifest["environment"]["physicalCPUCount"] * 1.5
    if maximum_load != expected_load:
        raise RuntimeError(
            "host load ceiling must equal 1.5 times the physical CPU count"
        )
    if measurement.get("crossVersionReportComparison") != (
        "Canonical JSON excluding only engineVersion; raw report SHA-256 and "
        "engineVersion remain recorded."
    ):
        raise RuntimeError("cross-version report comparison must remain explicit")
    build = manifest.get("binaryBuildProtocol", {})
    if build.get("appliesTo") != ["reference", "candidate"] or build.get("command") != (
        "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "
        "swift build -c release --jobs 2"
    ):
        raise RuntimeError(
            "reference and candidate must share the frozen build protocol"
        )
    identifiers = [scenario["id"] for scenario in manifest["scenarios"]]
    if len(identifiers) != len(set(identifiers)):
        raise RuntimeError("scenario identifiers must be unique")
    if not manifest.get("blockedScenarios"):
        raise RuntimeError("unimplemented release scenarios must remain explicit")
    expected_templates = {
        "similarityDisabled": [
            "{binary}",
            "analyze",
            "{corpus}",
            "--format",
            "json",
            "--jobs",
            "1",
            "--output",
            "{freshOutput}/analysis.json",
            "--profile-output",
            "{freshOutput}/profile.json",
        ],
        "repositoryEvidence": [
            "{binary}",
            "analyze",
            "{corpus}",
            "--format",
            "json",
            "--jobs",
            "1",
            "--output",
            "{freshOutput}/analysis.json",
            "--profile-output",
            "{freshOutput}/profile.json",
            "--repository-evidence",
            "{freshOutput}/repository-evidence.json",
        ],
    }
    if manifest.get("commandTemplates") != expected_templates:
        raise RuntimeError(
            "manifest command templates do not match the measured CLI commands"
        )


def validate_environment(expected: dict[str, Any], observed: dict[str, Any]) -> None:
    mismatches = [
        f"{key}: expected {value!r}, observed {observed.get(key)!r}"
        for key, value in expected.items()
        if observed.get(key) != value
    ]
    if mismatches:
        raise RuntimeError("benchmark environment mismatch: " + "; ".join(mismatches))


def calibrate(
    arguments: argparse.Namespace, manifest: dict[str, Any]
) -> dict[str, Any]:
    reference = arguments.reference_binary.resolve(strict=True)
    candidate = arguments.candidate_binary.resolve(strict=True)
    validate_distinct_binaries(reference, candidate)
    validate_binary(arguments.reference_root, reference)
    validate_binary(arguments.candidate_root, candidate)
    validate_source(
        arguments.reference_root, manifest["sources"]["referenceImplementationCommit"]
    )
    validate_source(
        arguments.candidate_root, manifest["sources"]["candidateImplementationCommit"]
    )
    observed_environment = environment_metadata()
    validate_environment(manifest["environment"], observed_environment)
    context = (
        tempfile.TemporaryDirectory(prefix="swiftdebt-r2-benchmark-")
        if arguments.work_directory is None
        else None
    )
    work = Path(context.name) if context else arguments.work_directory.resolve()
    work.mkdir(parents=True, exist_ok=True)
    try:
        corpora = generate_corpora(manifest, work)
        scenarios = []
        for scenario in manifest["scenarios"]:
            root = work / "samples" / scenario["id"]
            if scenario["comparison"] == "r1-r2-paired":
                result = measure_relative(
                    scenario,
                    corpora[scenario["sourceFileCount"]],
                    reference,
                    candidate,
                    root,
                    manifest["measurement"],
                    manifest["budgetPolicy"],
                )
            else:
                result = measure_repository(
                    scenario,
                    corpora[scenario["sourceFileCount"]],
                    candidate,
                    root,
                    manifest["measurement"],
                    manifest["budgetPolicy"],
                    manifest["repositoryConfiguration"],
                    manifest["providerIdentities"]["repositorySyntax"],
                    manifest["repositoryRules"],
                )
            scenarios.append(result)
        exhaustion = exhaustion_proof(
            manifest, candidate, work / "corpora" / "exhaustion", work / "samples"
        )
        measured_pass = (
            all(item["calibrationVerdict"] == "pass" for item in scenarios)
            and exhaustion["verdict"] == "pass"
        )
        return evidence(
            manifest,
            arguments.manifest,
            observed_environment,
            reference,
            candidate,
            scenarios,
            exhaustion,
            measured_pass,
        )
    finally:
        if context is not None:
            context.cleanup()


def generate_corpora(manifest: dict[str, Any], work: Path) -> dict[int, Path]:
    corpora = {}
    for source_files in sorted(
        {item["sourceFileCount"] for item in manifest["scenarios"]}
    ):
        corpus = work / "corpora" / f"scale-{source_files}"
        generated = generate_scale_corpus(corpus, source_files)
        expected = next(
            item
            for item in manifest["scenarios"]
            if item["sourceFileCount"] == source_files
        )
        for key in ("utf8ByteCount", "snapshotSHA256", "analysisUnitCounts"):
            if generated[key] != expected[key]:
                raise RuntimeError(
                    f"generated scale-{source_files} {key} does not match the manifest"
                )
        corpora[source_files] = corpus
    return corpora


def evidence(
    manifest: dict[str, Any],
    manifest_path: Path,
    environment: dict[str, Any],
    reference: Path,
    candidate: Path,
    scenarios: list[dict[str, Any]],
    exhaustion: dict[str, Any],
    measured_pass: bool,
) -> dict[str, Any]:
    reference_versions = sorted(
        {
            version
            for scenario in scenarios
            for version in scenario["outputValidation"].get(
                "referenceEngineVersions", []
            )
        }
    )
    candidate_versions = sorted(
        {
            version
            for scenario in scenarios
            for version in scenario["outputValidation"].get(
                "candidateEngineVersions", []
            )
        }
    )
    expected_versions = {
        "reference": manifest["sources"]["referenceEngineVersion"],
        "candidate": manifest["sources"]["candidateEngineVersion"],
    }
    observed_versions = {
        "reference": reference_versions,
        "candidate": candidate_versions,
    }
    mismatches = [
        f"{role}: expected {expected_versions[role]!r}, observed {versions!r}"
        for role, versions in observed_versions.items()
        if versions != [expected_versions[role]]
    ]
    if mismatches:
        raise RuntimeError(
            "benchmark engine version mismatch: " + "; ".join(mismatches)
        )
    return {
        "schemaVersion": 1,
        "manifestID": manifest["manifestID"],
        "manifestSHA256": sha256_file(manifest_path),
        "calibrationState": "measured-pass" if measured_pass else "measured-fail",
        "releaseQualification": "incomplete",
        "releaseQualificationReason": (
            "Warm cache, one-file edit, provider telemetry, SQVector exact-index, and ANN scenarios "
            "remain blocked or outside this source branch."
        ),
        "environment": environment,
        "binaryBuildProtocol": manifest["binaryBuildProtocol"],
        "binaries": {
            "reference": {
                "commit": manifest["sources"]["referenceImplementationCommit"],
                "engineVersion": reference_versions[0],
                "sha256": sha256_file(reference),
            },
            "candidate": {
                "commit": manifest["sources"]["candidateImplementationCommit"],
                "engineVersion": candidate_versions[0],
                "sha256": sha256_file(candidate),
            },
        },
        "measurement": manifest["measurement"],
        "providerIdentities": manifest["providerIdentities"],
        "scenarios": scenarios,
        "exhaustionProof": exhaustion,
        "blockedScenarios": manifest["blockedScenarios"],
        "observabilityGaps": manifest["observabilityGaps"],
    }


def main() -> int:
    arguments = parser().parse_args()
    manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
    validate_manifest(manifest)
    result = calibrate(arguments, manifest)
    atomic_json(arguments.output, result)
    return 0 if result["calibrationState"] == "measured-pass" else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"r2-release-benchmark: error: {error}", file=sys.stderr)
        raise SystemExit(2)
