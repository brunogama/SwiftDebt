#!/usr/bin/env python3
"""Measure an equivalent SwiftSCMA workload and emit gate-ready JSON."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Run warmup and measured samples for one frozen SwiftSCMA workload."
    )
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--input", action="append", required=True, type=Path)
    result.add_argument("--analyzer", required=True)
    result.add_argument("--workload-family", required=True)
    result.add_argument("--command-fingerprint", required=True)
    result.add_argument("--analysis-mode", required=True)
    result.add_argument("--optional-context", required=True)
    result.add_argument("--warmups", type=nonnegative_int, default=1)
    result.add_argument("--runs", type=positive_int, default=5)
    result.add_argument("command", nargs=argparse.REMAINDER)
    return result


def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be nonnegative")
    return parsed


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def input_checksum(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        data = path.read_bytes()
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def timed_command(command: list[str]) -> tuple[float, int]:
    time_arguments = ["/usr/bin/time", "-l" if sys.platform == "darwin" else "-v", *command]
    started = time.monotonic_ns()
    completed = subprocess.run(
        time_arguments,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "LC_ALL": "C"},
        check=False,
    )
    elapsed = (time.monotonic_ns() - started) / 1_000_000_000
    stderr = completed.stderr.decode("utf-8", errors="replace")
    if completed.returncode != 0:
        stdout = completed.stdout.decode("utf-8", errors="replace")
        raise RuntimeError(
            f"benchmark command exited {completed.returncode}: {' '.join(command)}\n{stdout}{stderr}"
        )
    return elapsed, peak_memory_bytes(stderr)


def peak_memory_bytes(output: str) -> int:
    if sys.platform == "darwin":
        match = re.search(r"(?m)^\s*(\d+)\s+maximum resident set size\s*$", output)
        multiplier = 1
    else:
        match = re.search(r"(?mi)^\s*Maximum resident set size \(kbytes\):\s*(\d+)\s*$", output)
        multiplier = 1024
    if match is None:
        raise RuntimeError("/usr/bin/time did not report maximum resident memory")
    return int(match.group(1)) * multiplier


def command_output(command: list[str]) -> str:
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return completed.stdout.strip() if completed.returncode == 0 else "unavailable"


def cpu_model() -> str:
    if sys.platform == "darwin":
        return command_output(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"])
    model = platform.processor().strip()
    if model:
        return model
    try:
        for line in Path("/proc/cpuinfo").read_text(encoding="utf-8").splitlines():
            if line.lower().startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return "unavailable"


def system_memory_bytes() -> int:
    if sys.platform == "darwin":
        value = command_output(["/usr/sbin/sysctl", "-n", "hw.memsize"])
        return int(value) if value.isdigit() else 0
    try:
        return os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
    except (OSError, ValueError):
        return 0


def main() -> int:
    arguments = parser().parse_args()
    command = arguments.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser().error("a command is required after --")
    missing = [str(path) for path in arguments.input if not path.is_file()]
    if missing:
        parser().error("input files do not exist: " + ", ".join(missing))

    for _ in range(arguments.warmups):
        timed_command(command)
    samples = []
    for _ in range(arguments.runs):
        wall_clock, peak_memory = timed_command(command)
        samples.append(
            {
                "wallClockSeconds": wall_clock,
                "peakMemoryBytes": peak_memory,
            }
        )

    wall_clock_samples = [sample["wallClockSeconds"] for sample in samples]
    memory_samples = [sample["peakMemoryBytes"] for sample in samples]
    result = {
        "schemaVersion": 1,
        "workload": {
            "analyzer": arguments.analyzer,
            "workloadFamily": arguments.workload_family,
            "inputSHA256": input_checksum(arguments.input),
            "commandFingerprint": arguments.command_fingerprint,
            "analysisMode": arguments.analysis_mode,
            "optionalContext": arguments.optional_context,
        },
        "wallClockSecondsMedian": statistics.median(wall_clock_samples),
        "wallClockSecondsMinimum": min(wall_clock_samples),
        "wallClockSecondsMaximum": max(wall_clock_samples),
        "peakMemoryBytesMedian": int(statistics.median(memory_samples)),
        "peakMemoryBytesMinimum": min(memory_samples),
        "peakMemoryBytesMaximum": max(memory_samples),
        "samples": samples,
        "metadata": {
            "swiftVersion": command_output(["swift", "--version"]),
            "os": platform.platform(),
            "architecture": platform.machine(),
            "cpuModel": cpu_model(),
            "memoryBytes": system_memory_bytes(),
            "warmupRuns": arguments.warmups,
            "measuredRuns": arguments.runs,
        },
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = arguments.output.with_name(arguments.output.name + ".tmp")
    temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, arguments.output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"benchmark: error: {error}", file=sys.stderr)
        raise SystemExit(2)
