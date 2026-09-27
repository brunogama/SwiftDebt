#!/usr/bin/env python3
"""Measure lifecycle capacity through real Git commits and the public swift-debt CLI."""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import time
from pathlib import Path

from r3_capacity_probe_support import (
    bounded_timeout,
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
    output = args.evidence.resolve()
    started = time.monotonic()
    deadline = started + args.maximum_elapsed_seconds
    evidence: dict = {
        "status": "running",
        "requestedSnapshots": args.snapshots,
        "requestedFindings": args.findings,
        "limits": {
            "minimumFreeGiB": args.minimum_free_gib,
            "maximumArtifactGiB": args.maximum_artifact_gib,
            "maximumElapsedSeconds": args.maximum_elapsed_seconds,
            "commandTimeoutSeconds": args.command_timeout_seconds,
            "checkpointEvery": args.checkpoint_every,
            "keepWorkdir": args.keep_workdir,
        },
        "checkpoints": [],
        "ingestions": [],
    }
    workdir: Path | None = None
    failure: str | None = None
    success: dict = {}
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.unlink(missing_ok=True)
        write_evidence(output, evidence)
        if args.snapshots < 3 or args.findings < 0 or args.checkpoint_every < 1:
            raise ValueError(
                "snapshots must be >= 3, findings >= 0, checkpoint-every >= 1"
            )
        if (
            args.minimum_free_gib <= 0
            or args.maximum_artifact_gib <= 0
            or args.maximum_elapsed_seconds <= 0
            or args.command_timeout_seconds <= 0
        ):
            raise ValueError("resource ceilings and timeouts must be positive")
        cli = args.swift_debt.resolve(strict=True)
        parent = args.work_parent.resolve(strict=True)
        script_path = Path(__file__).resolve()
        support_path = script_path.with_name("r3_capacity_probe_support.py")
        script_repository = script_path.parents[1]
        evidence.update(
            {
                "freeDiskBytesAtStart": preflight(
                    parent, args.minimum_free_gib + 2 * args.maximum_artifact_gib
                ),
                "swiftDebtBinarySHA256": file_sha256(cli),
                "runnerCommit": git(
                    script_repository,
                    "rev-parse",
                    "HEAD",
                    timeout=bounded_timeout(deadline, args.command_timeout_seconds),
                ),
                "runnerDirty": bool(
                    git(
                        script_repository,
                        "status",
                        "--porcelain",
                        timeout=bounded_timeout(deadline, args.command_timeout_seconds),
                    )
                ),
                "scriptSHA256": file_sha256(script_path),
                "supportSHA256": file_sha256(support_path),
            }
        )
        write_evidence(output, evidence)
        workdir = Path(tempfile.mkdtemp(prefix="swiftdebt-r3-capacity-", dir=parent))
        evidence["workdir"] = str(workdir)
        repo = workdir / "repo"
        repo.mkdir()
        artifact = workdir / "lifecycle.json"
        report = workdir / "report.json"
        git(
            repo,
            "init",
            "-q",
            timeout=bounded_timeout(deadline, args.command_timeout_seconds),
        )
        for sequence in range(1, args.snapshots + 1):
            bounded_timeout(deadline, args.command_timeout_seconds)
            preflight(parent, args.minimum_free_gib + args.maximum_artifact_gib)
            content = (
                clean_source(sequence)
                if sequence != 2 or args.findings == 0
                else source_with_findings(args.findings)
            )
            revision = commit(
                repo,
                content,
                sequence,
                deadline=deadline,
                command_limit=args.command_timeout_seconds,
            )
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
            run(
                command, timeout=bounded_timeout(deadline, args.command_timeout_seconds)
            )
            elapsed = time.monotonic() - begin
            bounded_timeout(deadline, args.command_timeout_seconds)
            artifact_bytes = artifact.stat().st_size
            evidence["ingestions"].append(
                {
                    "sequence": sequence,
                    "gitRevision": revision,
                    "wallSeconds": elapsed,
                    "artifactBytes": artifact_bytes,
                }
            )
            if artifact_bytes > args.maximum_artifact_gib * 1024**3:
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
                    deadline=deadline,
                    command_limit=args.command_timeout_seconds,
                )
                bounded_timeout(deadline, args.command_timeout_seconds)
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
        run(command, timeout=bounded_timeout(deadline, args.command_timeout_seconds))
        if (
            artifact.stat().st_size != before_size
            or file_sha256(artifact) != before_hash
        ):
            raise ValueError("Same-revision replay changed lifecycle artifact bytes")
        bounded_timeout(deadline, args.command_timeout_seconds)
        success = {
            "replayWallSeconds": time.monotonic() - replay_begin,
            "sourceHeadRevision": git(
                repo,
                "rev-parse",
                "HEAD",
                timeout=bounded_timeout(deadline, args.command_timeout_seconds),
            ),
        }
    except (Exception, KeyboardInterrupt) as error:
        failure = str(error) or type(error).__name__
    finally:
        if workdir is not None and not args.keep_workdir:
            try:
                shutil.rmtree(workdir)
            except Exception as error:
                cleanup_failure = f"Cleanup failed: {error}"
                failure = (
                    f"{failure}; {cleanup_failure}" if failure else cleanup_failure
                )
    evidence["totalWallSeconds"] = time.monotonic() - started
    if failure is None and time.monotonic() > deadline:
        failure = "Elapsed-time ceiling exceeded"
    if failure is None:
        evidence.update(success)
        evidence["status"] = "passed"
    else:
        evidence.update({"status": "failed", "failure": failure})
    try:
        write_evidence(output, evidence)
    except Exception as error:
        print(f"Capacity probe could not write evidence: {error}", file=sys.stderr)
        return 1
    if failure is not None:
        print(f"Capacity probe failed: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
