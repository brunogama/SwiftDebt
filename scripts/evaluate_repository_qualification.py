#!/usr/bin/env python3
"""Run the frozen Data Clumps and Repeated Switches qualification corpus."""

from __future__ import annotations

import argparse
import difflib
import sys
import tempfile
from pathlib import Path

from repository_qualification_evaluator import QualificationError, canonical_json, evaluate


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = (
    REPOSITORY_ROOT
    / "Tests/SwiftDebtKitTests/Fixtures/RepositoryQualification/corpus-v1.json"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--swift-debt", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect", type=Path)
    parser.add_argument("--determinism-runs", type=int, default=0)
    parser.add_argument("--parse-jobs", default="1,2,8")
    parser.add_argument("--verify-network-denied", action="store_true")
    parser.add_argument(
        "--work-directory",
        type=Path,
        help="Retain materialized sources and sidecars in a new directory for review.",
    )
    arguments = parser.parse_args()
    try:
        jobs = [int(value) for value in arguments.parse_jobs.split(",")]
        if arguments.work_directory:
            working_root = arguments.work_directory.resolve()
            if working_root.exists():
                raise QualificationError(f"work directory must not already exist: {working_root}")
            working_root.mkdir(parents=True)
            report = _evaluate(arguments, jobs, working_root)
        else:
            with tempfile.TemporaryDirectory(prefix="swiftdebt-rule-qualification-") as temporary:
                report = _evaluate(arguments, jobs, Path(temporary))
        encoded = canonical_json(report)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_bytes(encoded)
        if arguments.expect:
            expected = arguments.expect.read_bytes()
            if encoded != expected:
                difference = difflib.unified_diff(
                    expected.decode().splitlines(),
                    encoded.decode().splitlines(),
                    fromfile=str(arguments.expect),
                    tofile=str(arguments.output),
                    lineterm="",
                )
                print("\n".join(list(difference)[:200]), file=sys.stderr)
                return 1
        if report["gate"]["syntheticEngineeringEvidence"] != "pass":
            print("qualification engineering evidence failed", file=sys.stderr)
            return 1
        return 0
    except (OSError, ValueError, QualificationError) as error:
        print(f"qualification evaluation failed: {error}", file=sys.stderr)
        return 1


def _evaluate(arguments: argparse.Namespace, jobs: list[int], working_root: Path) -> dict:
    return evaluate(
        arguments.manifest.resolve(),
        arguments.swift_debt,
        working_root,
        arguments.determinism_runs,
        jobs,
        arguments.verify_network_denied,
    )


if __name__ == "__main__":
    raise SystemExit(main())
