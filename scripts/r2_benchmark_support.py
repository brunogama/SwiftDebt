#!/usr/bin/env python3
"""Shared measurements and deterministic corpora for the R2 release benchmark."""

from __future__ import annotations

import hashlib
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def percentile(values: list[float | int], fraction: float) -> float:
    if not values:
        raise ValueError("percentile requires at least one value")
    if not 0 < fraction <= 1:
        raise ValueError("percentile fraction must be in (0, 1]")
    ordered = sorted(values)
    return float(ordered[max(0, math.ceil(len(ordered) * fraction) - 1)])


def median_absolute_deviation(values: list[float | int]) -> float:
    if not values:
        raise ValueError("median absolute deviation requires at least one value")
    median = statistics.median(values)
    return float(statistics.median(abs(value - median) for value in values))


def summary(values: list[float | int]) -> dict[str, float]:
    return {
        "median": float(statistics.median(values)),
        "p95": percentile(values, 0.95),
        "minimum": float(min(values)),
        "maximum": float(max(values)),
    }


def paired_roles(pair_index: int) -> list[str]:
    roles = ["reference", "candidate"]
    if pair_index % 2:
        roles.reverse()
    return roles


def short_stage_gate(
    baseline_p95_ms: float,
    candidate_p95_ms: float,
    relative_limit_percent: float,
    absolute_noise_floor_ms: float,
    short_stage_boundary_ms: float = 1_000,
) -> dict[str, Any]:
    delta = candidate_p95_ms - baseline_p95_ms
    relative = (
        0.0
        if baseline_p95_ms == 0 and delta <= 0
        else (math.inf if baseline_p95_ms == 0 else (delta / baseline_p95_ms) * 100)
    )
    relative_breached = relative > relative_limit_percent
    floor_breached = delta > absolute_noise_floor_ms
    failed = relative_breached and (
        baseline_p95_ms >= short_stage_boundary_ms or floor_breached
    )
    return {
        "baselineP95Milliseconds": baseline_p95_ms,
        "candidateP95Milliseconds": candidate_p95_ms,
        "absoluteRegressionMilliseconds": delta,
        "relativeRegressionPercent": relative,
        "relativeLimitPercent": relative_limit_percent,
        "absoluteNoiseFloorMilliseconds": absolute_noise_floor_ms,
        "maximumToleratedAbsoluteRegressionMilliseconds": max(
            baseline_p95_ms * relative_limit_percent / 100,
            absolute_noise_floor_ms if baseline_p95_ms < short_stage_boundary_ms else 0,
        ),
        "relativeLimitBreached": relative_breached,
        "absoluteFloorBreached": floor_breached,
        "verdict": "fail" if failed else "pass",
    }


def memory_gate(
    baseline_p95_bytes: float,
    candidate_p95_bytes: float,
    relative_limit_percent: float,
) -> dict[str, Any]:
    relative = (
        math.inf
        if baseline_p95_bytes == 0 and candidate_p95_bytes > 0
        else (candidate_p95_bytes - baseline_p95_bytes) / baseline_p95_bytes * 100
        if baseline_p95_bytes
        else 0.0
    )
    return {
        "baselineP95Bytes": int(baseline_p95_bytes),
        "candidateP95Bytes": int(candidate_p95_bytes),
        "relativeRegressionPercent": relative,
        "relativeLimitPercent": relative_limit_percent,
        "verdict": "fail" if relative > relative_limit_percent else "pass",
    }


def scale_source(index: int) -> str:
    identifier = f"{index:04d}"
    return f"""enum BenchmarkMode{identifier} {{ case idle, running }}

struct BenchmarkType{identifier} {{
    let mode: BenchmarkMode{identifier}

    func submit{identifier}(customerID: String, postalCode: String, countryCode: String) {{}}
    func preview{identifier}(customerID: String, postalCode: String, countryCode: String) {{}}

    func firstRoute{identifier}() {{
        switch mode {{
        case .idle: break
        case .running: break
        }}
    }}

    func secondRoute{identifier}() {{
        switch mode {{
        case .idle: break
        case .running: break
        }}
    }}
}}
"""


def generate_scale_corpus(root: Path, source_files: int) -> dict[str, Any]:
    if source_files <= 0:
        raise ValueError("source_files must be positive")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    for index in range(source_files):
        (root / f"Scale{index:04d}.swift").write_text(
            scale_source(index), encoding="utf-8"
        )
    return {
        "sourceFileCount": source_files,
        "utf8ByteCount": sum(path.stat().st_size for path in root.glob("*.swift")),
        "snapshotSHA256": tree_sha256(root),
        "analysisUnitCounts": {
            "dataClumpUnits": source_files * 3,
            "repeatedSwitchUnits": source_files * 2,
        },
        "expectedDetectionCounts": {
            "swiftdebt.refactoring.data-clumps": 1,
            "swiftdebt.refactoring.repeated-switches": source_files,
        },
    }


def generate_exhaustion_corpus(root: Path, analysis_units: int = 600) -> dict[str, Any]:
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    declarations = [
        f"func operation{index:04d}(value{index}: Int, flag{index}: Bool, name{index}: String) {{}}"
        for index in range(analysis_units)
    ]
    (root / "ComparisonBudget.swift").write_text(
        "\n".join(declarations) + "\n", encoding="utf-8"
    )
    return {
        "sourceFileCount": 1,
        "utf8ByteCount": (root / "ComparisonBudget.swift").stat().st_size,
        "snapshotSHA256": tree_sha256(root),
        "analysisUnitCounts": {
            "dataClumpUnits": analysis_units,
            "repeatedSwitchUnits": 0,
        },
    }


def command_output(command: list[str]) -> str:
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return completed.stdout.strip() if completed.returncode == 0 else "unavailable"


def environment_metadata() -> dict[str, Any]:
    xcode = command_output(["xcodebuild", "-version"]).splitlines()
    return {
        "swiftVersion": command_output(["swift", "--version"]),
        "xcodeVersion": xcode[0] if xcode else "unavailable",
        "xcodeBuild": xcode[1].removeprefix("Build version ")
        if len(xcode) > 1
        else "unavailable",
        "macOSVersion": command_output(["sw_vers", "-productVersion"]),
        "macOSBuild": command_output(["sw_vers", "-buildVersion"]),
        "sdkVersion": command_output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-version"]
        ),
        "architecture": platform.machine(),
        "hardwareModel": command_output(["sysctl", "-n", "hw.model"]),
        "cpuModel": command_output(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "physicalCPUCount": os.cpu_count()
        if sys.platform != "darwin"
        else int(command_output(["sysctl", "-n", "hw.physicalcpu"])),
        "logicalCPUCount": os.cpu_count(),
        "memoryBytes": int(command_output(["sysctl", "-n", "hw.memsize"]))
        if sys.platform == "darwin"
        else 0,
    }


def peak_memory_bytes(stderr: str) -> int:
    if sys.platform == "darwin":
        match = re.search(r"(?m)^\s*(\d+)\s+maximum resident set size\s*$", stderr)
        multiplier = 1
    else:
        match = re.search(
            r"(?mi)^\s*Maximum resident set size \(kbytes\):\s*(\d+)\s*$", stderr
        )
        multiplier = 1_024
    if match is None:
        raise RuntimeError("/usr/bin/time did not report maximum resident memory")
    return int(match.group(1)) * multiplier


def timed_command(
    command: list[str], accepted_statuses: set[int], cwd: Path | None = None
) -> dict[str, Any]:
    timer = ["/usr/bin/time", "-l" if sys.platform == "darwin" else "-v", *command]
    load_before = os.getloadavg()
    started = time.monotonic_ns()
    completed = subprocess.run(
        timer,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "LC_ALL": "C"},
        cwd=cwd,
        check=False,
    )
    elapsed_ms = (time.monotonic_ns() - started) / 1_000_000
    load_after = os.getloadavg()
    stderr = completed.stderr.decode("utf-8", errors="replace")
    if completed.returncode not in accepted_statuses:
        stdout = completed.stdout.decode("utf-8", errors="replace")
        raise RuntimeError(
            f"benchmark command exited {completed.returncode}: {' '.join(command)}\n{stdout}{stderr}"
        )
    return {
        "wallClockMilliseconds": elapsed_ms,
        "peakResidentMemoryBytes": peak_memory_bytes(stderr),
        "exitStatus": completed.returncode,
        "hostLoadAverage": {
            "before": {
                "oneMinute": load_before[0],
                "fiveMinutes": load_before[1],
                "fifteenMinutes": load_before[2],
            },
            "after": {
                "oneMinute": load_after[0],
                "fiveMinutes": load_after[1],
                "fifteenMinutes": load_after[2],
            },
        },
    }


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)
