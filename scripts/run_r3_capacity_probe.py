#!/usr/bin/env python3
"""Measure lifecycle capacity through real Git commits and the public swift-debt CLI."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from r3_capacity_probe_support import (
    clean_source,
    commit,
    file_sha256,
    git,
    inspect,
    preflight,
    run,
    source_with_findings,
    write_evidence,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-debt", type=Path, required=True)
    parser.add_argument("--snapshots", type=int, required=True)
    parser.add_argument("--findings", type=int, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--work-parent", type=Path, default=Path(tempfile.gettempdir()))
    parser.add_argument("--minimum-free-gib", type=float, default=8.0)
    parser.add_argument("--maximum-artifact-gib", type=float, default=4.0)
    parser.add_argument("--maximum-elapsed-seconds", type=int, default=3600)
    parser.add_argument("--command-timeout-seconds", type=int, default=300)
    parser.add_argument("--checkpoint-every", type=int, default=10)
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args()
    if args.snapshots < 3 or args.findings < 0 or args.checkpoint_every < 1:
        parser.error("snapshots must be >= 3, findings >= 0, checkpoint-every >= 1")
    if (
        args.minimum_free_gib <= 0
        or args.maximum_artifact_gib <= 0
        or args.maximum_elapsed_seconds <= 0
        or args.command_timeout_seconds <= 0
    ):
        parser.error("resource ceilings and timeouts must be positive")
    cli = args.swift_debt.resolve(strict=True)
    parent = args.work_parent.resolve(strict=True)
    output = args.evidence.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replacement may temporarily hold the old and new artifact.
    free_at_start = preflight(
        parent, args.minimum_free_gib + 2 * args.maximum_artifact_gib
    )
    workdir = Path(tempfile.mkdtemp(prefix="swiftdebt-r3-capacity-", dir=parent))
    repo = workdir / "repo"
    repo.mkdir()
    artifact = workdir / "lifecycle.json"
    report = workdir / "report.json"
    script_path = Path(__file__).resolve()
    script_repository = script_path.parents[1]
    evidence: dict = {
        "status": "running",
        "requestedSnapshots": args.snapshots,
        "requestedFindings": args.findings,
        "freeDiskBytesAtStart": free_at_start,
        "swiftDebtBinarySHA256": file_sha256(cli),
        "sourceCommit": git(script_repository, "rev-parse", "HEAD"),
        "sourceDirty": bool(git(script_repository, "status", "--porcelain")),
        "scriptSHA256": file_sha256(script_path),
        "workdir": str(workdir),
        "checkpoints": [],
        "ingestions": [],
    }
    started = time.monotonic()
    try:
        git(repo, "init", "-q")
        for sequence in range(1, args.snapshots + 1):
            if time.monotonic() - started > args.maximum_elapsed_seconds:
                raise RuntimeError("Elapsed-time ceiling exceeded")
            preflight(parent, args.minimum_free_gib + args.maximum_artifact_gib)
            content = (
                clean_source(sequence)
                if sequence != 2 or args.findings == 0
                else source_with_findings(args.findings)
            )
            revision = commit(repo, content, sequence)
            command = [
                str(cli),
                "analyze",
                str(repo),
                "--format",
                "json",
                "--output",
                str(report),
                "--lifecycle-artifact",
                str(artifact),
                "--jobs",
                "2",
            ]
            begin = time.monotonic()
            run(command, timeout=args.command_timeout_seconds)
            elapsed = time.monotonic() - begin
            evidence["ingestions"].append(
                {
                    "sequence": sequence,
                    "gitRevision": revision,
                    "wallSeconds": elapsed,
                    "artifactBytes": artifact.stat().st_size,
                }
            )
            if artifact.stat().st_size > args.maximum_artifact_gib * 1024**3:
                raise RuntimeError("Artifact-size ceiling exceeded")
            if (
                sequence in (1, 2, 3, args.snapshots)
                or sequence % args.checkpoint_every == 0
            ):
                expected_findings = 0 if sequence == 1 else args.findings
                state = "open" if sequence == 2 else "resolved"
                point = inspect(
                    artifact,
                    cli,
                    snapshots=sequence,
                    findings=expected_findings,
                    state=state,
                )
                point.update(
                    {
                        "sequence": sequence,
                        "gitRevision": revision,
                        "ingestWallSeconds": elapsed,
                        "elapsedSeconds": time.monotonic() - started,
                        "freeDiskBytes": shutil.disk_usage(parent).free,
                    }
                )
                evidence["checkpoints"].append(point)
                write_evidence(output, evidence)
        before_size = artifact.stat().st_size
        before_hash = file_sha256(artifact)
        replay_begin = time.monotonic()
        run(command, timeout=args.command_timeout_seconds)
        if (
            artifact.stat().st_size != before_size
            or file_sha256(artifact) != before_hash
        ):
            raise ValueError("Same-revision replay changed lifecycle artifact bytes")
        evidence.update(
            {
                "status": "passed",
                "replayWallSeconds": time.monotonic() - replay_begin,
                "totalWallSeconds": time.monotonic() - started,
                "sourceHeadRevision": git(repo, "rev-parse", "HEAD"),
            }
        )
        write_evidence(output, evidence)
        return 0
    except (
        OSError,
        ValueError,
        RuntimeError,
        subprocess.TimeoutExpired,
        KeyboardInterrupt,
    ) as error:
        failure = str(error) or type(error).__name__
        evidence.update(
            {
                "status": "failed",
                "failure": failure,
                "totalWallSeconds": time.monotonic() - started,
            }
        )
        write_evidence(output, evidence)
        print(f"Capacity probe failed: {failure}", file=sys.stderr)
        return 1
    finally:
        if not args.keep_workdir:
            shutil.rmtree(workdir)


if __name__ == "__main__":
    raise SystemExit(main())
