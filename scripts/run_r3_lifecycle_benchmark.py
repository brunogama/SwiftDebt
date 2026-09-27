#!/usr/bin/env python3
"""Measure the public SwiftDebt lifecycle CLI on generated, committed Swift repositories."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable

from r3_lifecycle_benchmark_support import (
    PADDING_LINES, artifact_info, commit, fixture, largest_artifact_bytes,
    validate_explanation, validate_incremental_artifact, validate_incremental_profile,
    validate_introduction_profile, validate_inventory,
)

TIERS = {"small": 10, "medium": 100, "large": 1_000}
FIXTURE_VERSION = 3
COMMAND_TIMEOUT_SECONDS = 600
OPERATIONS = (
    "cold", "replay", "incremental", "inventory", "explain", "introduction",
    "introductionRepeat",
)


def command(argv: list[str], *, cwd: Path | None = None, capture: bool = False) -> str:
    result = subprocess.run(
        argv, cwd=cwd, env={**os.environ, "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"exit {result.returncode}: {' '.join(argv)}\n"
                           + result.stderr.decode(errors="replace")[-4000:])
    return result.stdout.decode() if capture else ""


def measured(
    argv: list[str], *, validate_output: Callable[[str], None] | None = None
) -> dict[str, object]:
    time_flag = "-l" if sys.platform == "darwin" else "-v"
    started = time.monotonic_ns()
    process = subprocess.Popen(
        ["/usr/bin/time", time_flag, *argv],
        env={**os.environ, "LC_ALL": "C"}, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE if validate_output else subprocess.DEVNULL,
        stderr=subprocess.PIPE, start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=COMMAND_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as error:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
        raise RuntimeError(f"benchmark command exceeded {COMMAND_TIMEOUT_SECONDS} seconds: {' '.join(argv)}") from error
    elapsed = (time.monotonic_ns() - started) / 1_000_000_000
    output = stderr.decode(errors="replace")
    if process.returncode:
        raise RuntimeError(f"exit {process.returncode}: {' '.join(argv)}\n{output[-4000:]}")
    if validate_output:
        validate_output(stdout.decode("utf-8"))
    pattern = (r"(?m)^\s*(\d+)\s+maximum resident set size\s*$" if sys.platform == "darwin"
               else r"(?mi)^\s*Maximum resident set size \(kbytes\):\s*(\d+)\s*$")
    match = re.search(pattern, output)
    if match is None:
        raise RuntimeError("/usr/bin/time did not report peak resident memory")
    return {"wallSeconds": elapsed, "peakRSSBytes": int(match.group(1)) * (1 if sys.platform == "darwin" else 1024)}


def summary(samples: list[dict[str, object]]) -> dict[str, object]:
    return {
        "samples": samples,
        "medianWallSeconds": statistics.median(sample["wallSeconds"] for sample in samples),
        "maximumWallSeconds": max(sample["wallSeconds"] for sample in samples),
        "maximumPeakRSSBytes": max(sample["peakRSSBytes"] for sample in samples),
    }


def system_memory_bytes() -> int:
    if sys.platform == "darwin":
        return int(command(["/usr/sbin/sysctl", "-n", "hw.memsize"], capture=True).strip())
    return os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")


def cpu_model() -> str:
    if sys.platform == "darwin":
        for key in ("machdep.cpu.brand_string", "hw.model"):
            try:
                return command(["/usr/sbin/sysctl", "-n", key], capture=True).strip()
            except RuntimeError:
                continue
        return "unavailable"
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text().splitlines():
            if line.lower().startswith("model name"):
                return line.split(":", 1)[1].strip()
    return platform.processor() or "unavailable"


def run_tier(binary: Path, source_count: int, runs: int, warmups: int) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="swiftdebt-r3-benchmark-") as temporary:
        root = Path(temporary)
        repository = root / "repository"
        repository.mkdir()
        absent_revision, detected_revision = fixture(repository, source_count)
        artifact = root / "lifecycle.json"
        analyze = [str(binary), "analyze", str(repository), "--format", "json", "--jobs", "1",
                   "--lifecycle-artifact", str(artifact)]
        samples: dict[str, list[dict[str, object]]] = {name: [] for name in OPERATIONS}
        cold_bytes = b""
        for index in range(warmups + runs):
            artifact.unlink(missing_ok=True)
            sample = measured(analyze)
            if index >= warmups:
                samples["cold"].append(sample)
            cold_bytes = artifact.read_bytes()
        cold_info = artifact_info(artifact)
        findings = json.loads(cold_bytes)["findings"]
        if len(findings) != source_count:
            raise RuntimeError(f"expected {source_count} Findings, observed {len(findings)}")
        finding_id = findings[0]["id"]
        for index in range(warmups + runs):
            artifact.write_bytes(cold_bytes)
            sample = measured(analyze)
            if artifact.read_bytes() != cold_bytes:
                raise RuntimeError("identical replay changed lifecycle artifact bytes")
            if index >= warmups:
                samples["replay"].append(sample)
        cold_snapshot_id = json.loads(cold_bytes)["snapshots"][0]["id"]
        for name, arguments, validator in (
            ("inventory", [str(binary), "lifecycle", "inventory", str(artifact), "--format", "json"],
             lambda output: validate_inventory(output, findings, cold_snapshot_id)),
            ("explain", [str(binary), "lifecycle", "explain", str(artifact), finding_id, "--format", "json"],
             lambda output: validate_explanation(output, findings[0], cold_snapshot_id)),
        ):
            for index in range(warmups + runs):
                sample = measured(arguments, validate_output=validator)
                if artifact.read_bytes() != cold_bytes:
                    raise RuntimeError(f"{name} changed lifecycle artifact bytes")
                if index >= warmups:
                    samples[name].append(sample)
        introduction_profile = root / "introduction-profile.json"
        introduction = [str(binary), "lifecycle", "infer-introduction", str(artifact), finding_id,
                        "--repository", str(repository), "--max-revisions", "4",
                        "--profile-output", str(introduction_profile), "--format", "json"]
        introduced_bytes = b""
        for index in range(warmups + runs):
            artifact.write_bytes(cold_bytes)
            introduction_profile.unlink(missing_ok=True)
            sample = measured(introduction)
            introduced_bytes = artifact.read_bytes()
            conclusion = json.loads(introduced_bytes)["introductionConclusions"]
            if len(conclusion) != 1 or conclusion[0]["kind"] != "exact":
                raise RuntimeError("bounded introduction query did not establish the expected exact conclusion")
            sample["history"] = validate_introduction_profile(
                introduction_profile.read_text(), conclusion[0], finding_id=finding_id,
                maximum_revisions=4, maximum_file_bytes=16 * 1_024 * 1_024,
                recording_status="accepted",
            )
            if index >= warmups:
                samples["introduction"].append(sample)
        for index in range(warmups + runs):
            artifact.write_bytes(introduced_bytes)
            introduction_profile.unlink(missing_ok=True)
            sample = measured(introduction)
            if artifact.read_bytes() != introduced_bytes:
                raise RuntimeError("identical introduction query changed lifecycle artifact bytes")
            conclusion = json.loads(introduced_bytes)["introductionConclusions"][0]
            sample["history"] = validate_introduction_profile(
                introduction_profile.read_text(), conclusion, finding_id=finding_id,
                maximum_revisions=4, maximum_file_bytes=16 * 1_024 * 1_024,
                recording_status="already-present",
            )
            if index >= warmups:
                samples["introductionRepeat"].append(sample)
        introduction_info = artifact_info(artifact)
        history = json.loads(introduced_bytes)["introductionConclusions"][0]["evidence"]
        introduction_info["examinedRevisions"] = len(history["revisions"])
        introduction_info["frontierRevisions"] = len(history["boundary"]["frontierRevisions"])

        edited = repository / "Sources" / "File00000.swift"
        edited.write_text("// Shift location without changing the debt predicate\n" + edited.read_text())
        edited_revision = commit(repository, "move one benchmark detection", 3)
        incremental_info = {}
        profile_path = root / "incremental-profile.json"
        for index in range(warmups + runs):
            artifact.write_bytes(cold_bytes)
            profile_path.unlink(missing_ok=True)
            sample = measured(analyze + ["--profile-output", str(profile_path)])
            incremental_bytes = artifact.read_bytes()
            incremental_info = artifact_info(artifact)
            validate_incremental_artifact(cold_bytes, incremental_bytes, source_count)
            sample["reconciliation"] = validate_incremental_profile(
                profile_path.read_text(), incremental_bytes, source_count
            )
            if index >= warmups:
                samples["incremental"].append(sample)
        reconciliation_samples = [sample["reconciliation"] for sample in samples["incremental"]]
        return {
            "sourceFiles": source_count, "sourceLines": source_count * (PADDING_LINES + 2),
            "gitRevisions": {"absent": absent_revision, "detected": detected_revision,
                             "edited": edited_revision},
            "coldArtifact": cold_info, "incrementalArtifact": incremental_info,
            "introductionArtifact": introduction_info,
            "incrementalReconciliation": {
                "samples": reconciliation_samples,
                "medianElapsedNanoseconds": statistics.median(
                    sample["reconciliationElapsedNanoseconds"] for sample in reconciliation_samples
                ),
                "affectedCandidates": reconciliation_samples[0]["candidates"],
            },
            "operations": {name: summary(samples[name]) for name in OPERATIONS},
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-debt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--tiers", nargs="+", choices=TIERS, default=list(TIERS))
    parser.add_argument("--budgets", type=Path, help="Fail if a measured median or artifact size exceeds a calibrated limit")
    args = parser.parse_args()
    if args.runs < 1 or args.warmups < 0:
        parser.error("--runs must be positive and --warmups must be nonnegative")
    if args.budgets and set(args.tiers) != set(TIERS):
        parser.error("a budget gate must measure all three tiers")
    if args.budgets and (args.runs < 3 or args.warmups < 1):
        parser.error("a budget gate requires at least three measured runs and one warmup")
    binary = args.swift_debt.resolve(strict=True)
    repository_root = Path(__file__).resolve().parent.parent
    result = {
        "schemaVersion": 1, "swiftDebtCommit": command(["git", "rev-parse", "HEAD"], cwd=repository_root, capture=True).strip(),
        "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "environment": {"platform": platform.platform(), "machine": platform.machine(),
                        "cpuModel": cpu_model(), "memoryBytes": system_memory_bytes(),
                        "python": platform.python_version(),
                        "swift": command(["swift", "--version"], capture=True).strip()},
        "method": {"runs": args.runs, "warmups": args.warmups, "jobs": 1,
                   "fixtureVersion": FIXTURE_VERSION, "historyRevisionBudget": 4,
                   "paddingLinesPerFile": PADDING_LINES},
        "tiers": {name: run_tier(binary, TIERS[name], args.runs, args.warmups) for name in args.tiers},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.budgets:
        budgets = json.loads(args.budgets.read_text())
        if budgets["fixtureVersion"] != FIXTURE_VERSION:
            raise RuntimeError("R3 lifecycle budget fixture version does not match this script")
        if (budgets["platformFamily"] != sys.platform
                or budgets["machine"] != platform.machine()
                or budgets["cpuModel"] != result["environment"]["cpuModel"]
                or budgets["swiftVersion"] != result["environment"]["swift"]):
            raise RuntimeError("R3 lifecycle budget platform or toolchain does not match this run")
        failures = []
        for tier_name, tier in result["tiers"].items():
            allowed = budgets["tiers"][tier_name]
            artifact_bytes = largest_artifact_bytes(tier)
            if artifact_bytes > allowed["maximumArtifactBytes"]:
                failures.append(f"{tier_name}: artifact exceeds byte limit")
            for name, metrics in tier["operations"].items():
                if metrics["medianWallSeconds"] > allowed["maximumMedianWallSeconds"][name]:
                    failures.append(f"{tier_name}/{name}: median wall time exceeds limit")
                if metrics["maximumPeakRSSBytes"] > allowed["maximumPeakRSSBytes"][name]:
                    failures.append(f"{tier_name}/{name}: peak RSS exceeds limit")
        if failures:
            raise RuntimeError("R3 lifecycle benchmark budget failed: " + "; ".join(failures))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, KeyError, ValueError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
