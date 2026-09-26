#!/usr/bin/env python3
"""Frozen repository-cache expectations for the R2 release benchmark."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from r2_benchmark_support import tree_sha256


EXPECTED_CACHE_DATA_CLASSES = [
    "data-clump-syntax-facts",
    "fact-budget-dependencies",
    "parse-diagnostics",
    "repeated-switch-syntax-facts",
    "source-content-digests",
]


def expected_cache_activity(cache_state: str, source_count: int) -> dict[str, Any]:
    if cache_state == "disabled":
        return {
            "mode": "disabled",
            "disposition": "disabled",
            "selectedSourceCount": source_count,
            "reusedSourceCount": 0,
            "recomputedSourceCount": source_count,
            "removedSourceCount": 0,
            "invalidations": {"cache-disabled": source_count},
            "writePerformed": False,
            "networkRequestCount": 0,
        }
    if cache_state == "cold":
        return {
            "mode": "reuse",
            "disposition": "cold-rebuild",
            "selectedSourceCount": source_count,
            "reusedSourceCount": 0,
            "recomputedSourceCount": source_count,
            "removedSourceCount": 0,
            "invalidations": {"cache-missing": source_count},
            "writePerformed": True,
            "networkRequestCount": 0,
        }
    if cache_state == "warm":
        return {
            "mode": "reuse",
            "disposition": "warm-reuse",
            "selectedSourceCount": source_count,
            "reusedSourceCount": source_count,
            "recomputedSourceCount": 0,
            "removedSourceCount": 0,
            "invalidations": {},
            "writePerformed": False,
            "networkRequestCount": 0,
        }
    if cache_state == "one-file-edit":
        return {
            "mode": "reuse",
            "disposition": "partial-rebuild",
            "selectedSourceCount": source_count,
            "reusedSourceCount": source_count - 1,
            "recomputedSourceCount": 1,
            "removedSourceCount": 0,
            "invalidations": {"source-content-changed": 1},
            "writePerformed": True,
            "networkRequestCount": 0,
        }
    raise ValueError(f"unsupported repository cache state: {cache_state}")


def seed_scenario(
    scenario: dict[str, Any], base_corpus: Path
) -> dict[str, Any]:
    source_count = scenario["sourceFileCount"]
    return {
        **scenario,
        "id": f"{scenario['id']}-seed",
        "cacheState": "cold",
        "snapshotSHA256": tree_sha256(base_corpus),
        "utf8ByteCount": sum(path.stat().st_size for path in base_corpus.glob("*.swift")),
        "expectedCacheActivity": expected_cache_activity("cold", source_count),
    }
