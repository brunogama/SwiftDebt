#!/usr/bin/env python3
"""Scenario calibration and regression proof for the R2 release benchmark."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from r2_benchmark_cache import (
    induced_repository_samples,
    prepare_repository_seed,
    run_repository_sample,
)
from r2_benchmark_cache_contract import expected_cache_activity
from r2_benchmark_cli import (
    aggregate,
    induced_samples,
    record_compact_sample,
    retain_compact_sample,
    run_cli_sample,
    validate_sample,
)
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
        policy["maximumPeakMemoryRegressionBytes"],
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
                "reference-only wall-clock samples"
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
            "peakResidentMemoryP95Bytes": memory["baselineP95Bytes"]
            + memory["maximumToleratedAbsoluteRegressionBytes"],
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
    warmups_completed = 0
    for warmup in range(measurement["warmupRuns"]):
        for position, role in enumerate(paired_roles(warmup)):
            destination = root / f"warmup-{warmup}-{position}-{role}"
            sample = run_cli_sample(
                binaries[role],
                corpus,
                destination,
                False,
            )
            validate_sample(sample, scenario)
            enforce_sample_load(sample, policy)
            retain_compact_sample(destination, sample)
        warmups_completed += 1
    raw = []
    progress(scenario["id"], f"running {measurement['measuredRuns']} measured pairs")
    for pair_index in range(measurement["measuredRuns"]):
        for order_in_pair, role in enumerate(paired_roles(pair_index)):
            destination = root / f"pair-{pair_index}-{role}"
            sample = run_cli_sample(
                binaries[role], corpus, destination, False
            )
            validate_sample(sample, scenario)
            enforce_sample_load(sample, policy)
            sample.update(
                {"pairIndex": pair_index, "orderInPair": order_in_pair, "role": role}
            )
            raw.append(sample)
            retain_compact_sample(destination, sample)
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
    enforce_induced_load(induced, policy)
    evaluations = limits_and_proof(
        reference_aggregate,
        candidate_aggregate,
        reference_samples,
        candidate_samples,
        induced,
        policy,
        True,
    )
    output_validation = relative_output_validation(
        reference_samples, candidate_samples
    )
    deterministic = output_validation["referenceReportByteStable"] and output_validation[
        "candidateReportByteStable"
    ]
    comparable = output_validation["crossImplementationComparable"]
    return scenario_result(
        scenario,
        raw,
        reference_aggregate,
        candidate_aggregate,
        evaluations,
        deterministic,
        comparable,
        output_validation,
        {
            "warmupRunsCompleted": warmups_completed,
            "measuredPairsCompleted": len(reference_samples),
            "inducedRegressionRunsCompleted": len(induced),
        },
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
    cache_compatibility: dict[str, Any],
) -> dict[str, Any]:
    prepared_seed = None
    if scenario["cacheState"] in {"warm", "one-file-edit"}:
        progress(scenario["id"], "preparing one validated reusable cache seed")
        prepared_seed = prepare_repository_seed(
            candidate,
            corpus,
            root / "prepared-seed",
            scenario,
            repository_configuration,
            repository_provider,
            repository_rules,
            cache_compatibility,
        )
        enforce_sample_load(prepared_seed["sample"], policy)
    progress(scenario["id"], f"running {measurement['warmupRuns']} warmups")
    warmups_completed = 0
    for warmup in range(measurement["warmupRuns"]):
        sample = run_repository_sample(
            candidate,
            corpus,
            root / f"warmup-{warmup}",
            scenario,
            repository_configuration,
            repository_provider,
            repository_rules,
            cache_compatibility,
            prepared_seed,
        )
        enforce_sample_load(sample, policy)
        warmups_completed += 1
    raw = []
    progress(scenario["id"], f"running {measurement['measuredRuns']} measured samples")
    for index in range(measurement["measuredRuns"]):
        sample = run_repository_sample(
            candidate,
            corpus,
            root / f"sample-{index}",
            scenario,
            repository_configuration,
            repository_provider,
            repository_rules,
            cache_compatibility,
            prepared_seed,
        )
        enforce_sample_load(sample, policy)
        sample["sampleIndex"] = index
        record_compact_sample(root / f"sample-{index}", sample)
        raw.append(sample)
        if (index + 1) % 5 == 0 or index + 1 == measurement["measuredRuns"]:
            progress(
                scenario["id"],
                f"measured sample {index + 1}/{measurement['measuredRuns']}",
            )
    baseline = aggregate(raw)
    progress(scenario["id"], "running deliberate two-pass regression proof")
    induced = induced_repository_samples(
        candidate,
        corpus,
        root,
        scenario,
        measurement["inducedRegressionRuns"],
        repository_configuration,
        repository_provider,
        repository_rules,
        cache_compatibility,
        prepared_seed,
    )
    enforce_induced_load(induced, policy)
    evaluations = limits_and_proof(baseline, baseline, raw, raw, induced, policy, False)
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
    return scenario_result(
        scenario,
        raw,
        baseline,
        baseline,
        evaluations,
        deterministic,
        True,
        output_validation,
        {
            "warmupRunsCompleted": warmups_completed,
            "measuredSamplesCompleted": len(raw),
            "inducedRegressionRunsCompleted": len(induced),
        },
    )


def relative_output_validation(
    reference_samples: list[dict[str, Any]],
    candidate_samples: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "referenceReportByteStable": len(
            {sample["reportSHA256"] for sample in reference_samples}
        )
        == 1,
        "candidateReportByteStable": len(
            {sample["reportSHA256"] for sample in candidate_samples}
        )
        == 1,
        "crossImplementationComparable": len(
            {
                sample["comparableReportSHA256"]
                for sample in [*reference_samples, *candidate_samples]
            }
        )
        == 1,
        "comparisonProjection": "canonical JSON excluding engineVersion",
        "referenceEngineVersions": sorted(
            {sample["reportEngineVersion"] for sample in reference_samples}
        ),
        "candidateEngineVersions": sorted(
            {sample["reportEngineVersion"] for sample in candidate_samples}
        ),
    }


def repository_output_validation(raw: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "candidateReportByteStable": len(
            {sample["reportSHA256"] for sample in raw}
        )
        == 1,
        "candidateRepositorySidecarByteStable": len(
            {sample["repositoryEvidenceSHA256"] for sample in raw}
        )
        == 1,
        "candidateCacheActivityCanonicalByteStable": len(
            {sample["comparableRepositoryCacheReportSHA256"] for sample in raw}
        )
        == 1,
        "candidateCacheStoreByteStable": len(
            {sample["cacheStoreSHA256After"] for sample in raw}
        )
        == 1,
        "candidateEngineVersions": sorted(
            {sample["reportEngineVersion"] for sample in raw}
        ),
        "crossImplementationComparable": {
            "availability": "not-applicable",
            "reason": "R1 has no repository-evidence command.",
        },
    }


def scenario_result(
    scenario: dict[str, Any],
    raw: list[dict[str, Any]],
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    evaluations: dict[str, Any],
    deterministic: bool,
    comparable: bool,
    output_validation: dict[str, Any],
    sampling_evidence: dict[str, int],
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
        "comparison": scenario["comparison"],
        "state": scenario["state"],
        "cacheState": scenario["cacheState"],
        "samplingEvidence": sampling_evidence,
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
        **(
            {
                "expectedCacheActivity": scenario["expectedCacheActivity"],
                **(
                    {"standardEdit": scenario["standardEdit"]}
                    if "standardEdit" in scenario
                    else {}
                ),
            }
            if scenario["repositoryEvidence"]
            else {}
        ),
        "baseline": baseline,
        "candidate": candidate,
        "rawSamples": raw,
        "budget": evaluations,
        "deterministicOutput": deterministic,
        "outputValidation": output_validation,
        "indexSizeBytes": {
            "availability": "not-applicable",
            "reason": "Similarity is disabled and this benchmark performs no candidate-index operation.",
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
    destination = root / "exhaustion"
    sample = run_cli_sample(
        candidate,
        corpus,
        destination,
        True,
        {2},
        cache_state="disabled",
    )
    validate_exhaustion_sample(manifest, sample, generated)
    enforce_sample_load(sample, manifest["budgetPolicy"])
    maximum_load = max(
        sample["hostLoadAverage"]["before"]["oneMinute"],
        sample["hostLoadAverage"]["after"]["oneMinute"],
    )
    load_limit = manifest["budgetPolicy"]["maximumObservedOneMinuteLoad"]
    passed = (
        sample["exitStatus"] == 2 and not sample["unexpectedFiles"] and maximum_load <= load_limit
    )
    result = {
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
    retain_compact_sample(destination, sample)
    return result


def validate_exhaustion_sample(
    manifest: dict[str, Any], sample: dict[str, Any], generated: dict[str, Any]
) -> None:
    scenario = manifest["exhaustionScenario"]
    evidence = sample["repositoryEvidence"]
    expected_rules = manifest["repositoryRules"]
    expected_revisions = {
        identity: contract["semanticRevision"]
        for identity, contract in expected_rules.items()
    }
    provider = manifest["providerIdentities"]["repositorySyntax"]
    expected_provider = [[provider["name"], provider["version"]]]
    expected_rule_providers = {
        identity: expected_provider for identity in expected_rules
    }
    activity = sample["repositoryCacheActivity"]
    observed_activity = {
        key: activity[key]
        for key in (
            "mode",
            "disposition",
            "selectedSourceCount",
            "reusedSourceCount",
            "recomputedSourceCount",
            "removedSourceCount",
            "invalidations",
            "networkRequestCount",
        )
    }
    observed_activity["writePerformed"] = activity["storage"]["writePerformed"]
    valid = (
        sample["exitStatus"] == scenario["expectedExitStatus"]
        and not sample["unexpectedFiles"]
        and sample["sourceSnapshotSHA256"] == generated["snapshotSHA256"]
        and evidence["sourceFileCount"] == scenario["sourceFileCount"]
        and evidence["detectionCount"] == 0
        and evidence["completeRuleCount"] == 1
        and evidence["incompleteRuleCount"] == 1
        and evidence["issueCodes"] == [scenario["expectedIssueCode"]]
        and evidence["configuration"] == manifest["repositoryConfiguration"]
        and evidence["ruleDetectionCounts"]
        == {identity: 0 for identity in expected_rules}
        and evidence["ruleSemanticRevisions"] == expected_revisions
        and evidence["ruleCompletionStates"]
        == {
            "swiftdebt.refactoring.data-clumps": "incomplete",
            "swiftdebt.refactoring.repeated-switches": "complete",
        }
        and evidence["providers"] == expected_provider
        and evidence["ruleProviders"] == expected_rule_providers
        and activity["reportKind"] == "swiftdebt-repository-syntax-cache"
        and activity["schemaVersion"] == 1
        and activity["sourceSnapshotDigest"] == evidence["snapshotContentDigest"]
        and activity["compatibility"] == manifest["repositoryCacheCompatibility"]
        and observed_activity
        == expected_cache_activity("disabled", scenario["sourceFileCount"])
        and activity["storage"]
        == {
            "location": None,
            "dataClasses": [],
            "byteCount": 0,
            "contentDigest": None,
            "writePerformed": False,
        }
    )
    if not valid:
        raise RuntimeError(
            "comparison-budget exhaustion did not produce the exact incomplete result"
        )


def enforce_sample_load(sample: dict[str, Any], policy: dict[str, Any]) -> None:
    limit = policy["maximumObservedOneMinuteLoad"]
    observed = max(
        sample["hostLoadAverage"]["before"]["oneMinute"],
        sample["hostLoadAverage"]["after"]["oneMinute"],
    )
    if observed > limit:
        raise RuntimeError(
            f"host load {observed:.2f} exceeded the frozen {limit:.2f} ceiling"
        )


def enforce_induced_load(
    samples: list[dict[str, Any]], policy: dict[str, Any]
) -> None:
    for sample in samples:
        for component in sample["componentHostLoadAverage"]:
            enforce_sample_load({"hostLoadAverage": component}, policy)
