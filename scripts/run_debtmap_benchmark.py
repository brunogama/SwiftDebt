#!/usr/bin/env python3
"""Measure an equivalent SwiftDebt workload and emit gate-ready JSON."""

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
import uuid
from pathlib import Path


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Run warmup and measured samples for one frozen SwiftDebt workload."
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
    result.add_argument(
        "--paired-output",
        type=Path,
        help="Emit a second result from paired, interleaved command measurements.",
    )
    result.add_argument(
        "--paired-executable",
        help="Replace the measured command executable for the paired result.",
    )
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


def measured_sample(
    command: list[str], pair_index: int | None = None, order_in_pair: int | None = None
) -> dict[str, float | int]:
    wall_clock, peak_memory = timed_command(command)
    sample: dict[str, float | int] = {
        "wallClockSeconds": wall_clock,
        "peakMemoryBytes": peak_memory,
    }
    if pair_index is not None and order_in_pair is not None:
        sample["pairIndex"] = pair_index
        sample["orderInPair"] = order_in_pair
    return sample


def collect_samples(
    command: list[str], warmups: int, runs: int, paired_command: list[str] | None = None
) -> tuple[list[dict[str, float | int]], list[dict[str, float | int]] | None]:
    if paired_command is None:
        for _ in range(warmups):
            timed_command(command)
        return ([measured_sample(command) for _ in range(runs)], None)

    for pair_index in range(warmups):
        commands = (command, paired_command) if pair_index % 2 == 0 else (paired_command, command)
        for selected in commands:
            timed_command(selected)

    samples: dict[str, list[dict[str, float | int]]] = {"primary": [], "paired": []}
    for pair_index in range(runs):
        primary_first = (pair_index + warmups) % 2 == 0
        order = (
            (("primary", command), ("paired", paired_command))
            if primary_first
            else (("paired", paired_command), ("primary", command))
        )
        for order_in_pair, (role, selected) in enumerate(order, start=1):
            samples[role].append(measured_sample(selected, pair_index, order_in_pair))
    return samples["primary"], samples["paired"]


def benchmark_result(
    arguments: argparse.Namespace,
    samples: list[dict[str, float | int]],
    metadata: dict[str, object],
) -> dict[str, object]:
    wall_clock_samples = [float(sample["wallClockSeconds"]) for sample in samples]
    memory_samples = [int(sample["peakMemoryBytes"]) for sample in samples]
    return {
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
        "metadata": metadata,
    }


def write_result(path: Path, result: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    try:
        temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    argument_parser = parser()
    arguments = argument_parser.parse_args()
    command = arguments.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        argument_parser.error("a command is required after --")
    if (arguments.paired_output is None) != (arguments.paired_executable is None):
        argument_parser.error("--paired-output and --paired-executable must be used together")
    if arguments.paired_output is not None:
        output = arguments.output.resolve()
        paired_output = arguments.paired_output.resolve()
        same_spelling = str(output).casefold() == str(paired_output).casefold()
        same_existing_file = (
            output.exists() and paired_output.exists() and output.samefile(paired_output)
        )
        if same_spelling or same_existing_file:
            argument_parser.error("--output and --paired-output must resolve to different paths")
    missing = [str(path) for path in arguments.input if not path.is_file()]
    if missing:
        argument_parser.error("input files do not exist: " + ", ".join(missing))

    paired_command = None
    if arguments.paired_executable is not None:
        paired_command = [arguments.paired_executable, *command[1:]]
    primary_samples, paired_samples = collect_samples(
        command, arguments.warmups, arguments.runs, paired_command
    )
    metadata = {
        "swiftVersion": command_output(["swift", "--version"]),
        "os": platform.platform(),
        "architecture": platform.machine(),
        "cpuModel": cpu_model(),
        "memoryBytes": system_memory_bytes(),
        "warmupRuns": arguments.warmups,
        "measuredRuns": arguments.runs,
        "measurementDesign": "paired-interleaved-v1" if paired_command else "sequential-v1",
    }
    generation_id = uuid.uuid4().hex if paired_samples is not None else None
    primary_result = benchmark_result(arguments, primary_samples, metadata)
    if generation_id is not None:
        primary_result["pairGenerationID"] = generation_id
    write_result(arguments.output, primary_result)
    if arguments.paired_output is not None and paired_samples is not None:
        paired_result = benchmark_result(arguments, paired_samples, metadata)
        paired_result["pairGenerationID"] = generation_id
        write_result(arguments.paired_output, paired_result)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"benchmark: error: {error}", file=sys.stderr)
        raise SystemExit(2)
