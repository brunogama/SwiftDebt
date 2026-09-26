#!/usr/bin/env python3
"""Validate checked-in R2 calibration evidence without rerunning benchmarks."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from r2_benchmark_cache import validate_cache_sample
from r2_benchmark_cli import aggregate, validate_sample
from r2_benchmark_evidence import validate_portable_path_presentation
from r2_benchmark_scenarios import (
    enforce_induced_load,
    enforce_sample_load,
    limits_and_proof,
    relative_output_validation,
    repository_output_validation,
    scenario_result,
    validate_exhaustion_sample,
)
from r2_benchmark_support import evaluate_preflight, paired_roles, sha256_file
from run_r2_release_benchmarks import validate_manifest


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--manifest", required=True, type=Path)
    result.add_argument("--artifact", required=True, type=Path)
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def validate_calibration(
    manifest: dict[str, Any], manifest_path: Path, artifact: dict[str, Any]
) -> None:
    validate_manifest(manifest)
    require(artifact.get("schemaVersion") == 1, "calibration schema must be 1")
    require(
        artifact.get("manifestID") == manifest["manifestID"],
        "calibration manifest identity mismatch",
    )
    require(
        artifact.get("manifestSHA256") == sha256_file(manifest_path),
        "calibration manifest digest mismatch",
    )
    require(
        artifact.get("calibrationState") == "measured-pass",
        "checked-in calibration must be a measured pass",
    )
    require(
        artifact.get("releaseQualification") == "incomplete",
        "deterministic cache calibration cannot claim complete R2 qualification",
    )
    validate_portable_path_presentation(artifact)
    for key in (
        "environment",
        "binaryBuildProtocol",
        "measurement",
        "providerIdentities",
        "blockedScenarios",
        "observabilityGaps",
    ):
        expected_key = "environment" if key == "environment" else key
        require(
            artifact.get(key) == manifest.get(expected_key),
            f"calibration {key} does not match the manifest",
        )
    validate_binary_identity(manifest, artifact)
    validate_preflight(manifest, artifact["quietHostPreflight"])

    scenarios = artifact.get("scenarios", [])
    require(
        [item.get("id") for item in scenarios]
        == [item["id"] for item in manifest["scenarios"]],
        "calibration scenarios do not match manifest order and identity",
    )
    for expected, observed in zip(manifest["scenarios"], scenarios):
        validate_scenario(manifest, expected, observed)

    validate_exhaustion(manifest, artifact["exhaustionProof"])


def validate_binary_identity(
    manifest: dict[str, Any], artifact: dict[str, Any]
) -> None:
    expected = {
        "reference": (
            manifest["sources"]["referenceImplementationCommit"],
            manifest["sources"]["referenceEngineVersion"],
        ),
        "candidate": (
            manifest["sources"]["candidateImplementationCommit"],
            manifest["sources"]["candidateEngineVersion"],
        ),
    }
    binaries = artifact.get("binaries", {})
    for role, (commit, version) in expected.items():
        observed = binaries.get(role, {})
        require(observed.get("commit") == commit, f"{role} commit mismatch")
        require(observed.get("engineVersion") == version, f"{role} version mismatch")
        require(
            re.fullmatch(r"[0-9a-f]{64}", observed.get("sha256", "")) is not None,
            f"{role} binary digest is invalid",
        )


def validate_preflight(
    manifest: dict[str, Any], preflight: dict[str, Any]
) -> None:
    policy = manifest["preflightPolicy"]
    expected_count = policy["durationSeconds"] // policy["sampleIntervalSeconds"]
    samples = preflight.get("samples", [])
    require(len(samples) == expected_count, "quiet-host preflight sample count mismatch")
    recomputed = evaluate_preflight(samples, policy)
    for key in ("samples", "observed", "limits", "checks", "verdict"):
        require(
            preflight.get(key) == recomputed[key],
            f"quiet-host preflight {key} mismatch",
        )
    require(
        preflight.get("elapsedSeconds", 0) >= policy["durationSeconds"],
        "quiet-host preflight did not span its frozen duration",
    )
    require(preflight["verdict"] == "pass", "quiet-host preflight did not pass")


def validate_scenario(
    manifest: dict[str, Any], expected: dict[str, Any], observed: dict[str, Any]
) -> None:
    measurement = manifest["measurement"]
    policy = manifest["budgetPolicy"]
    raw = observed.get("rawSamples", [])
    induced = observed.get("budget", {}).get("inducedRegressionProof", {}).get(
        "samples", []
    )
    require(
        len(induced) == measurement["inducedRegressionRuns"],
        f"{expected['id']} induced sample count mismatch",
    )
    enforce_induced_load(induced, policy)

    if expected["comparison"] == "r1-r2-paired":
        reference, candidate = validate_paired_samples(
            expected, raw, measurement, policy
        )
        baseline = aggregate(reference)
        candidate_aggregate = aggregate(candidate)
        evaluations = limits_and_proof(
            baseline,
            candidate_aggregate,
            reference,
            candidate,
            induced,
            policy,
            True,
        )
        output_validation = relative_output_validation(reference, candidate)
        deterministic = output_validation["referenceReportByteStable"] and output_validation[
            "candidateReportByteStable"
        ]
        comparable = output_validation["crossImplementationComparable"]
        sampling = {
            "warmupRunsCompleted": measurement["warmupRuns"],
            "measuredPairsCompleted": len(reference),
            "inducedRegressionRunsCompleted": len(induced),
        }
    else:
        validate_repository_samples(manifest, expected, raw, measurement, policy)
        baseline = aggregate(raw)
        candidate_aggregate = baseline
        evaluations = limits_and_proof(
            baseline, baseline, raw, raw, induced, policy, False
        )
        output_validation = repository_output_validation(raw)
        deterministic = all(
            output_validation[key]
            for key in (
                "candidateReportByteStable",
                "candidateRepositorySidecarByteStable",
                "candidateCacheActivityCanonicalByteStable",
                "candidateCacheStoreByteStable",
            )
        )
        comparable = True
        sampling = {
            "warmupRunsCompleted": measurement["warmupRuns"],
            "measuredSamplesCompleted": len(raw),
            "inducedRegressionRunsCompleted": len(induced),
        }

    recomputed = scenario_result(
        expected,
        raw,
        baseline,
        candidate_aggregate,
        evaluations,
        deterministic,
        comparable,
        output_validation,
        sampling,
    )
    require(
        observed == recomputed,
        f"{expected['id']} aggregate, budget, or verdict does not recompute",
    )
    require(
        observed["budget"]["fixedLimits"]["approvalState"]
        == "proposed-for-review",
        f"{expected['id']} limits cannot claim approval",
    )


def validate_paired_samples(
    scenario: dict[str, Any],
    raw: list[dict[str, Any]],
    measurement: dict[str, Any],
    policy: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    measured_runs = measurement["measuredRuns"]
    require(
        len(raw) == measured_runs * 2,
        f"{scenario['id']} paired raw sample count mismatch",
    )
    for pair_index in range(measured_runs):
        pair = [sample for sample in raw if sample.get("pairIndex") == pair_index]
        require(len(pair) == 2, f"{scenario['id']} pair {pair_index} is incomplete")
        pair.sort(key=lambda item: item["orderInPair"])
        require(
            [item["role"] for item in pair] == paired_roles(pair_index),
            f"{scenario['id']} pair {pair_index} order mismatch",
        )
    for sample in raw:
        validate_sample(sample, scenario)
        enforce_sample_load(sample, policy)
    reference = sorted(
        (sample for sample in raw if sample["role"] == "reference"),
        key=lambda item: item["pairIndex"],
    )
    candidate = sorted(
        (sample for sample in raw if sample["role"] == "candidate"),
        key=lambda item: item["pairIndex"],
    )
    return reference, candidate


def validate_repository_samples(
    manifest: dict[str, Any],
    scenario: dict[str, Any],
    raw: list[dict[str, Any]],
    measurement: dict[str, Any],
    policy: dict[str, Any],
) -> None:
    require(
        len(raw) == measurement["measuredRuns"],
        f"{scenario['id']} repository raw sample count mismatch",
    )
    require(
        [sample.get("sampleIndex") for sample in raw]
        == list(range(measurement["measuredRuns"])),
        f"{scenario['id']} repository sample indices mismatch",
    )
    for sample in raw:
        validate_cache_sample(
            sample,
            scenario,
            manifest["repositoryConfiguration"],
            manifest["providerIdentities"]["repositorySyntax"],
            manifest["repositoryRules"],
            manifest["repositoryCacheCompatibility"],
        )
        enforce_sample_load(sample, policy)
        setup_load = sample.get("cacheSetup", {}).get("setupHostLoadAverage")
        if setup_load is not None:
            enforce_sample_load({"hostLoadAverage": setup_load}, policy)


def validate_exhaustion(
    manifest: dict[str, Any], proof: dict[str, Any]
) -> None:
    scenario = manifest["exhaustionScenario"]
    require(proof.get("id") == scenario["id"], "exhaustion proof identity mismatch")
    source = proof["sourceSnapshot"]
    for key in ("sourceFileCount", "utf8ByteCount", "snapshotSHA256", "analysisUnitCounts"):
        require(source.get(key) == scenario[key], f"exhaustion {key} mismatch")
    sample = proof["sample"]
    validate_exhaustion_sample(manifest, sample, source)
    enforce_sample_load(sample, manifest["budgetPolicy"])
    maximum_load = max(
        sample["hostLoadAverage"]["before"]["oneMinute"],
        sample["hostLoadAverage"]["after"]["oneMinute"],
    )
    require(
        proof.get("expectedExitStatus") == scenario["expectedExitStatus"]
        and proof.get("expectedIssueCode") == scenario["expectedIssueCode"]
        and proof.get("hostLoad")
        == {
            "maximumObservedOneMinute": maximum_load,
            "maximumAllowed": manifest["budgetPolicy"][
                "maximumObservedOneMinuteLoad"
            ],
            "verdict": "pass",
        }
        and proof.get("verdict") == "pass",
        "exhaustion proof did not pass its exact contract",
    )


def main() -> int:
    arguments = parser().parse_args()
    manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
    artifact = json.loads(arguments.artifact.read_text(encoding="utf-8"))
    validate_calibration(manifest, arguments.manifest, artifact)
    print("R2 release calibration artifact: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"r2-release-calibration-validation: error: {error}", file=sys.stderr)
        raise SystemExit(2)
