#!/usr/bin/env python3
"""Explicit repository-cache state preparation and validation."""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from r2_benchmark_cache_contract import EXPECTED_CACHE_DATA_CLASSES, seed_scenario
from r2_benchmark_cli import run_cli_sample, validate_sample
from r2_benchmark_support import (
    apply_standard_one_file_edit,
    sha256_file,
)


def run_repository_sample(
    binary: Path,
    base_corpus: Path,
    sample_root: Path,
    scenario: dict[str, Any],
    repository_configuration: dict[str, Any],
    repository_provider: dict[str, Any],
    repository_rules: dict[str, Any],
    cache_compatibility: dict[str, Any],
    prepared_seed: dict[str, Any] | None = None,
) -> dict[str, Any]:
    shutil.rmtree(sample_root, ignore_errors=True)
    sample_root.mkdir(parents=True)
    cache_state = scenario["cacheState"]
    state_root = sample_root / "state"
    state_root.mkdir()
    cache_path = state_root / "repository-syntax-cache.json"
    corpus = base_corpus
    source_files = sorted(
        path.relative_to(base_corpus).as_posix()
        for path in base_corpus.rglob("*")
        if path.is_file()
    )
    seed = None

    if cache_state == "one-file-edit":
        corpus = state_root / "corpus"
        shutil.copytree(base_corpus, corpus)

    local_seed = False
    if cache_state in {"warm", "one-file-edit"}:
        if prepared_seed is None:
            seed = prepare_repository_seed(
                binary,
                base_corpus,
                sample_root / "seed",
                scenario,
                repository_configuration,
                repository_provider,
                repository_rules,
                cache_compatibility,
            )
            local_seed = True
        else:
            seed = prepared_seed
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(seed["cachePath"], cache_path)
        if cache_state == "one-file-edit":
            observed_edit = apply_standard_one_file_edit(corpus)
            if observed_edit != scenario["standardEdit"]:
                raise RuntimeError("standard one-file edit does not match the manifest")

    before_sha = sha256_file(cache_path) if cache_path.is_file() else None
    measured = run_cli_sample(
        binary,
        corpus,
        sample_root / "measured",
        True,
        cache_state=cache_state,
        cache_path=None if cache_state == "disabled" else cache_path,
    )
    after_sha = sha256_file(cache_path) if cache_path.is_file() else None
    measured["cacheState"] = cache_state
    measured["cacheStoreSHA256Before"] = before_sha
    measured["cacheStoreSHA256After"] = after_sha
    measured["cacheStoreByteCountAfter"] = (
        cache_path.stat().st_size if cache_path.is_file() else None
    )
    measured["expectedCachePath"] = (
        None if cache_state == "disabled" else str(cache_path.absolute())
    )
    if seed is not None:
        seed_sample = seed["sample"]
        measured["cacheSetup"] = {
            "preparation": (
                "sample-local-cli-seed" if local_seed else "copied-scenario-seed"
            ),
            "sourceSnapshotSHA256": seed_sample["sourceSnapshotSHA256"],
            "repositoryEvidenceSHA256": seed_sample["repositoryEvidenceSHA256"],
            "repositoryCacheReportSHA256": seed_sample[
                "repositoryCacheReportSHA256"
            ],
            "repositoryCacheActivity": seed_sample["repositoryCacheActivity"],
            "cacheStoreSHA256After": seed_sample["cacheStoreSHA256After"],
            "cacheStoreByteCountAfter": seed_sample["cacheStoreByteCountAfter"],
            "setupWallClockMilliseconds": seed_sample["wallClockMilliseconds"],
            "setupPeakResidentMemoryBytes": seed_sample["peakResidentMemoryBytes"],
            "setupHostLoadAverage": seed_sample["hostLoadAverage"],
        }
    measured["controlledStateFiles"] = sorted(
        path.relative_to(sample_root).as_posix()
        for path in sample_root.rglob("*")
        if path.is_file()
    )
    expected_files = {
        f"measured/{relative}" for relative in measured["createdFiles"]
    }
    if cache_state != "disabled":
        expected_files.add("state/repository-syntax-cache.json")
    if local_seed:
        expected_files.add("seed/repository-syntax-cache.json")
        expected_files.update(
            f"seed/output/{relative}" for relative in seed["sample"]["createdFiles"]
        )
    if cache_state == "one-file-edit":
        expected_files.update(f"state/corpus/{relative}" for relative in source_files)
    if measured["controlledStateFiles"] != sorted(expected_files):
        observed_files = set(measured["controlledStateFiles"])
        raise RuntimeError(
            f"{scenario['id']} controlled state mismatch: "
            f"unexpected={sorted(observed_files - expected_files)}, "
            f"missing={sorted(expected_files - observed_files)}"
        )
    validate_cache_sample(
        measured,
        scenario,
        repository_configuration,
        repository_provider,
        repository_rules,
        cache_compatibility,
    )
    return measured


def prepare_repository_seed(
    binary: Path,
    base_corpus: Path,
    seed_root: Path,
    scenario: dict[str, Any],
    repository_configuration: dict[str, Any],
    repository_provider: dict[str, Any],
    repository_rules: dict[str, Any],
    cache_compatibility: dict[str, Any],
) -> dict[str, Any]:
    shutil.rmtree(seed_root, ignore_errors=True)
    seed_root.mkdir(parents=True)
    cache_path = seed_root / "repository-syntax-cache.json"
    sample = run_cli_sample(
        binary,
        base_corpus,
        seed_root / "output",
        True,
        cache_state="cold",
        cache_path=cache_path,
    )
    sample["cacheState"] = "cold"
    sample["cacheStoreSHA256Before"] = None
    sample["cacheStoreSHA256After"] = (
        sha256_file(cache_path) if cache_path.is_file() else None
    )
    sample["cacheStoreByteCountAfter"] = (
        cache_path.stat().st_size if cache_path.is_file() else None
    )
    sample["expectedCachePath"] = str(cache_path.absolute())
    validate_cache_sample(
        sample,
        seed_scenario(scenario, base_corpus),
        repository_configuration,
        repository_provider,
        repository_rules,
        cache_compatibility,
    )
    return {"cachePath": cache_path, "sample": sample}


def validate_cache_sample(
    sample: dict[str, Any],
    scenario: dict[str, Any],
    repository_configuration: dict[str, Any],
    repository_provider: dict[str, Any],
    repository_rules: dict[str, Any],
    cache_compatibility: dict[str, Any],
) -> None:
    validate_sample(
        sample,
        scenario,
        repository_configuration,
        repository_provider,
        repository_rules,
    )
    activity = sample["repositoryCacheActivity"]
    if activity["sourceSnapshotDigest"] != sample["repositoryEvidence"][
        "snapshotContentDigest"
    ]:
        raise RuntimeError(
            "repository cache activity and evidence describe different source snapshots"
        )
    if activity["reportKind"] != "swiftdebt-repository-syntax-cache":
        raise RuntimeError("cache activity used an unexpected report kind")
    if activity["schemaVersion"] != 1:
        raise RuntimeError("cache activity used an unexpected schema version")
    if activity["compatibility"] != cache_compatibility:
        raise RuntimeError("cache activity used unexpected compatibility identity")
    expected = scenario["expectedCacheActivity"]
    observed = {
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
    observed["writePerformed"] = activity["storage"]["writePerformed"]
    if observed != expected:
        raise RuntimeError(
            f"{scenario['id']} cache activity mismatch: expected {expected!r}, observed {observed!r}"
        )
    expected_storage: dict[str, Any]
    if scenario["cacheState"] == "disabled":
        expected_storage = {
            "location": None,
            "dataClasses": [],
            "byteCount": 0,
            "contentDigest": None,
            "writePerformed": False,
        }
    else:
        expected_storage = {
            "location": sample.get("expectedCachePath"),
            "dataClasses": EXPECTED_CACHE_DATA_CLASSES,
            "byteCount": sample.get("cacheStoreByteCountAfter"),
            "contentDigest": {
                "algorithm": "sha256",
                "value": sample.get("cacheStoreSHA256After"),
            },
            "writePerformed": expected["writePerformed"],
        }
    if activity["storage"] != expected_storage:
        raise RuntimeError(
            f"{scenario['id']} cache storage provenance mismatch: "
            f"expected {expected_storage!r}, observed {activity['storage']!r}"
        )
    if scenario["cacheState"] == "warm":
        if sample.get("cacheStoreSHA256Before") != sample.get("cacheStoreSHA256After"):
            raise RuntimeError("warm cache sample rewrote compatible state")
    elif scenario["cacheState"] == "disabled":
        if sample.get("cacheStoreSHA256Before") or sample.get("cacheStoreSHA256After"):
            raise RuntimeError("cache-disabled sample created retained state")
    elif sample.get("cacheStoreSHA256After") is None:
        raise RuntimeError("cache-writing sample did not retain a cache document")


def induced_repository_samples(
    binary: Path,
    corpus: Path,
    root: Path,
    scenario: dict[str, Any],
    count: int,
    repository_configuration: dict[str, Any],
    repository_provider: dict[str, Any],
    repository_rules: dict[str, Any],
    cache_compatibility: dict[str, Any],
    prepared_seed: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    samples = []
    for index in range(count):
        components = [
            run_repository_sample(
                binary,
                corpus,
                root / f"induced-{index}-{component}",
                scenario,
                repository_configuration,
                repository_provider,
                repository_rules,
                cache_compatibility,
                prepared_seed,
            )
            for component in range(2)
        ]
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
