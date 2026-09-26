#!/usr/bin/env python3
"""Scenario calibration and regression proof for the R2 release benchmark."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from r2_benchmark_cli import aggregate, induced_samples, run_cli_sample, validate_sample
from r2_benchmark_support import (
    generate_exhaustion_corpus,
    median_absolute_deviation,
    memory_gate,
    paired_roles,
    short_stage_gate,
    summary,
)


def progress(scenario_id: str, message: str) -> None:
    print(
        f"r2-release-benchmark: {scenario_id}: {message}", file=sys.stderr, flush=True
    )


def limits_and_proof(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    raw_baseline: list[dict[str, Any]],
    raw_candidate: list[dict[str, Any]],
    induced: list[dict[str, Any]],
    policy: dict[str, Any],
    paired: bool,
) -> dict[str, Any]:
    if paired:
        floor_samples = [
            candidate_sample["wallClockMilliseconds"]
            - baseline_sample["wallClockMilliseconds"]
            for baseline_sample, candidate_sample in zip(raw_baseline, raw_candidate)
        ]
    else:
        floor_samples = [sample["wallClockMilliseconds"] for sample in raw_baseline]
    mad = median_absolute_deviation(floor_samples)
    floor = max(
        policy["minimumShortStageFloorMilliseconds"],
        policy["medianAbsoluteDeviationMultiplier"] * mad,
    )
    wall = short_stage_gate(
        baseline["wallClockMilliseconds"]["p95"],
        candidate["wallClockMilliseconds"]["p95"],
        policy["maximumWallClockRegressionPercent"],
        floor,
        policy["shortStageBoundaryMilliseconds"],
    )
    memory = memory_gate(
        baseline["peakResidentMemoryBytes"]["p95"],
        candidate["peakResidentMemoryBytes"]["p95"],
        policy["maximumPeakMemoryRegressionPercent"],
    )
    induced_summary = summary([sample["wallClockMilliseconds"] for sample in induced])
    observed_loads = [
        load
        for sample in [*raw_baseline, *raw_candidate]
        for load in (
            sample["hostLoadAverage"]["before"]["oneMinute"],
            sample["hostLoadAverage"]["after"]["oneMinute"],
        )
    ] + [
        load
        for sample in induced
        for component in sample["componentHostLoadAverage"]
        for load in (
            component["before"]["oneMinute"],
            component["after"]["oneMinute"],
        )
    ]
    maximum_load = max(observed_loads)
    load_limit = policy["maximumObservedOneMinuteLoad"]
    induced_gate = short_stage_gate(
        baseline["wallClockMilliseconds"]["p95"],
        induced_summary["p95"],
        policy["maximumWallClockRegressionPercent"],
        floor,
        policy["shortStageBoundaryMilliseconds"],
    )
    return {
        "noiseFloorCalibration": {
            "sampleBasis": (
                "paired candidate-minus-reference wall-clock deltas"
                if paired
                else "calibration wall-clock samples"
            ),
            "samplesMilliseconds": floor_samples,
            "medianAbsoluteDeviationMilliseconds": mad,
            "multiplier": policy["medianAbsoluteDeviationMultiplier"],
            "minimumFloorMilliseconds": policy["minimumShortStageFloorMilliseconds"],
            "appliedFloorMilliseconds": floor,
        },
        "wallClock": wall,
        "peakResidentMemory": memory,
        "hostLoad": {
            "oneMinute": summary(observed_loads),
            "maximumAllowed": load_limit,
            "verdict": "pass" if maximum_load <= load_limit else "fail",
        },
        "fixedLimits": {
            "wallClockP95Milliseconds": wall["baselineP95Milliseconds"]
            + wall["maximumToleratedAbsoluteRegressionMilliseconds"],
            "peakResidentMemoryP95Bytes": int(
                memory["baselineP95Bytes"]
                * (1 + policy["maximumPeakMemoryRegressionPercent"] / 100)
            ),
            "approvalState": "proposed-for-review",
        },
        "inducedRegressionProof": {
            "workload": "two complete sequential CLI analyses per measured sample",
            "samples": induced,
            "wallClockMilliseconds": induced_summary,
            "evaluation": induced_gate,
            "verdict": "pass" if induced_gate["verdict"] == "fail" else "fail",
        },
    }


def measure_relative(
    scenario: dict[str, Any],
    corpus: Path,
    reference: Path,
    candidate: Path,
    root: Path,
    measurement: dict[str, Any],
    policy: dict[str, Any],
) -> dict[str, Any]:
    binaries = {"reference": reference, "candidate": candidate}
    progress(scenario["id"], f"running {measurement['warmupRuns']} paired warmups")
    for warmup in range(measurement["warmupRuns"]):
        for position, role in enumerate(paired_roles(warmup)):
            sample = run_cli_sample(
                binaries[role],
                corpus,
                root / f"warmup-{warmup}-{position}-{role}",
                False,
            )
            validate_sample(sample, scenario)
    raw = []
    progress(scenario["id"], f"running {measurement['measuredRuns']} measured pairs")
    for pair_index in range(measurement["measuredRuns"]):
        for order_in_pair, role in enumerate(paired_roles(pair_index)):
            sample = run_cli_sample(
                binaries[role], corpus, root / f"pair-{pair_index}-{role}", False
            )
            validate_sample(sample, scenario)
            sample.update(
                {"pairIndex": pair_index, "orderInPair": order_in_pair, "role": role}
            )
            raw.append(sample)
        if (pair_index + 1) % 5 == 0 or pair_index + 1 == measurement["measuredRuns"]:
            progress(
                scenario["id"],
                f"measured pair {pair_index + 1}/{measurement['measuredRuns']}",
            )
    reference_samples = sorted(
        (sample for sample in raw if sample["role"] == "reference"),
        key=lambda item: item["pairIndex"],
    )
    candidate_samples = sorted(
        (sample for sample in raw if sample["role"] == "candidate"),
        key=lambda item: item["pairIndex"],
    )
    reference_aggregate = aggregate(reference_samples)
    candidate_aggregate = aggregate(candidate_samples)
    progress(scenario["id"], "running deliberate two-pass regression proof")
    induced = induced_samples(
        candidate, corpus, root, False, measurement["inducedRegressionRuns"]
    )
    evaluations = limits_and_proof(
        reference_aggregate,
        candidate_aggregate,
        reference_samples,
        candidate_samples,
        induced,
        policy,
        True,
    )
    reference_stable = (
        len({sample["reportSHA256"] for sample in reference_samples}) == 1
    )
    candidate_stable = (
        len({sample["reportSHA256"] for sample in candidate_samples}) == 1
    )
    comparable = (
        len(
            {
                sample["comparableReportSHA256"]
                for sample in [*reference_samples, *candidate_samples]
            }
        )
        == 1
    )
    output_validation = {
        "referenceReportByteStable": reference_stable,
        "candidateReportByteStable": candidate_stable,
        "crossImplementationComparable": comparable,
        "comparisonProjection": "canonical JSON excluding engineVersion",
        "referenceEngineVersions": sorted(
            {sample["reportEngineVersion"] for sample in reference_samples}
        ),
        "candidateEngineVersions": sorted(
            {sample["reportEngineVersion"] for sample in candidate_samples}
        ),
    }
    return scenario_result(
        scenario,
        raw,
        reference_aggregate,
        candidate_aggregate,
        evaluations,
        reference_stable and candidate_stable,
        comparable,
        output_validation,
    )


def measure_repository(
    scenario: dict[str, Any],
    corpus: Path,
    candidate: Path,
    root: Path,
    measurement: dict[str, Any],
    policy: dict[str, Any],
    repository_configuration: dict[str, Any],
    repository_provider: dict[str, Any],
    repository_rules: dict[str, Any],
) -> dict[str, Any]:
    progress(scenario["id"], f"running {measurement['warmupRuns']} warmups")
    for warmup in range(measurement["warmupRuns"]):
        sample = run_cli_sample(candidate, corpus, root / f"warmup-{warmup}", True)
        validate_sample(
            sample,
            scenario,
            repository_configuration,
            repository_provider,
            repository_rules,
        )
    raw = []
    progress(scenario["id"], f"running {measurement['measuredRuns']} measured samples")
    for index in range(measurement["measuredRuns"]):
        sample = run_cli_sample(candidate, corpus, root / f"sample-{index}", True)
        validate_sample(
            sample,
            scenario,
            repository_configuration,
            repository_provider,
            repository_rules,
        )
        sample["sampleIndex"] = index
        raw.append(sample)
        if (index + 1) % 5 == 0 or index + 1 == measurement["measuredRuns"]:
            progress(
                scenario["id"],
                f"measured sample {index + 1}/{measurement['measuredRuns']}",
            )
    baseline = aggregate(raw)
    progress(scenario["id"], "running deliberate two-pass regression proof")
    induced = induced_samples(
        candidate, corpus, root, True, measurement["inducedRegressionRuns"]
    )
    evaluations = limits_and_proof(baseline, baseline, raw, raw, induced, policy, False)
    report_stable = len({sample["reportSHA256"] for sample in raw}) == 1
    sidecar_stable = len({sample["repositoryEvidenceSHA256"] for sample in raw}) == 1
    output_validation = {
        "candidateReportByteStable": report_stable,
        "candidateRepositorySidecarByteStable": sidecar_stable,
        "candidateEngineVersions": sorted(
            {sample["reportEngineVersion"] for sample in raw}
        ),
        "crossImplementationComparable": {
            "availability": "not-applicable",
            "reason": "R1 has no repository-evidence command.",
        },
    }
    return scenario_result(
        scenario,
        raw,
        baseline,
        baseline,
        evaluations,
        report_stable and sidecar_stable,
        True,
        output_validation,
    )


def scenario_result(
    scenario: dict[str, Any],
    raw: list[dict[str, Any]],
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    evaluations: dict[str, Any],
    deterministic: bool,
    comparable: bool,
    output_validation: dict[str, Any],
) -> dict[str, Any]:
    current_pass = (
        evaluations["wallClock"]["verdict"] == "pass"
        and evaluations["peakResidentMemory"]["verdict"] == "pass"
        and evaluations["hostLoad"]["verdict"] == "pass"
        and evaluations["inducedRegressionProof"]["verdict"] == "pass"
        and deterministic
        and comparable
    )
    return {
        "id": scenario["id"],
        "state": scenario["state"],
        "sourceSnapshot": {
            **{
                key: scenario[key]
                for key in (
                    "sourceFileCount",
                    "utf8ByteCount",
                    "snapshotSHA256",
                    "analysisUnitCounts",
                )
            },
            **(
                {
                    "repositoryContentDigest": raw[0]["repositoryEvidence"][
                        "snapshotContentDigest"
                    ]
                }
                if scenario["repositoryEvidence"]
                else {}
            ),
        },
        "measuredStages": scenario["measuredStages"],
        "baseline": baseline,
        "candidate": candidate,
        "rawSamples": raw,
        "budget": evaluations,
        "deterministicOutput": deterministic,
        "outputValidation": output_validation,
        "indexSizeBytes": {
            "availability": "not-applicable",
            "reason": "Similarity is disabled and this source branch contains no candidate index.",
        },
        "candidateCount": {
            "availability": "not-applicable",
            "reason": "No similarity candidate retrieval occurs in this scenario.",
        },
        "calibrationVerdict": "pass" if current_pass else "fail",
    }


def exhaustion_proof(
    manifest: dict[str, Any], candidate: Path, corpus: Path, root: Path
) -> dict[str, Any]:
    scenario = manifest["exhaustionScenario"]
    generated = generate_exhaustion_corpus(
        corpus, scenario["analysisUnitCounts"]["dataClumpUnits"]
    )
    if generated["snapshotSHA256"] != scenario["snapshotSHA256"]:
        raise RuntimeError("exhaustion corpus does not match the manifest")
    sample = run_cli_sample(candidate, corpus, root / "exhaustion", True, {2})
    evidence = sample["repositoryEvidence"]
    maximum_load = max(
        sample["hostLoadAverage"]["before"]["oneMinute"],
        sample["hostLoadAverage"]["after"]["oneMinute"],
    )
    load_limit = manifest["budgetPolicy"]["maximumObservedOneMinuteLoad"]
    passed = (
        sample["exitStatus"] == 2
        and "comparison-budget-exceeded" in evidence["issueCodes"]
        and not sample["unexpectedFiles"]
        and maximum_load <= load_limit
    )
    return {
        "id": scenario["id"],
        "sourceSnapshot": generated,
        "sample": sample,
        "expectedExitStatus": 2,
        "expectedIssueCode": "comparison-budget-exceeded",
        "hostLoad": {
            "maximumObservedOneMinute": maximum_load,
            "maximumAllowed": load_limit,
            "verdict": "pass" if maximum_load <= load_limit else "fail",
        },
        "verdict": "pass" if passed else "fail",
    }
