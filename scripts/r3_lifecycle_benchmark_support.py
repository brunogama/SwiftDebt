"""Generated Git fixtures and artifact summaries for the R3 lifecycle benchmark."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

PADDING_LINES = 48


def _git(argv: list[str], repository: Path | None = None) -> str:
    result = subprocess.run(
        ["git", *argv], cwd=repository, env={**os.environ, "LC_ALL": "C"},
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"Git fixture command failed: {' '.join(argv)}\n"
                           + result.stderr.decode(errors="replace")[-4000:])
    return result.stdout.decode().strip()


def source(index: int, *, detected: bool) -> str:
    name = f"operation{index:05d}"
    body = f"func {name}(_ input: Int) throws -> Int {{ input + 1 }}\n"
    body += (f"func use{index:05d}(_ input: Int) -> Int {{ try! {name}(input) }}\n"
             if detected else f"func use{index:05d}(_ input: Int) -> Int {{ input }}\n")
    body += "".join(f"// Stable fixture line {line:02d} in {name}\n" for line in range(PADDING_LINES))
    return body


def commit(repository: Path, message: str, ordinal: int) -> str:
    environment = {**os.environ, "LC_ALL": "C", "GIT_AUTHOR_DATE": f"2026-01-{ordinal:02d}T12:00:00Z",
                   "GIT_COMMITTER_DATE": f"2026-01-{ordinal:02d}T12:00:00Z"}
    for argv in (["git", "add", "-A"], ["git", "commit", "-qm", message]):
        result = subprocess.run(argv, cwd=repository, env=environment,
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, check=False)
        if result.returncode:
            raise RuntimeError(f"Git fixture commit failed: {' '.join(argv)}\n"
                               + result.stderr.decode(errors="replace")[-4000:])
    return _git(["rev-parse", "HEAD"], repository)


def fixture(repository: Path, source_count: int) -> tuple[str, str]:
    _git(["init", "-q", "--initial-branch=main", str(repository)])
    for key, value in (("user.name", "SwiftDebt Benchmark"),
                       ("user.email", "benchmark@example.invalid"),
                       ("commit.gpgsign", "false"), ("core.autocrlf", "false")):
        _git(["config", key, value], repository)
    source_dir = repository / "Sources"
    source_dir.mkdir()
    for index in range(source_count):
        (source_dir / f"File{index:05d}.swift").write_text(source(index, detected=False))
    absent = commit(repository, "add clean benchmark sources", 1)
    for index in range(source_count):
        (source_dir / f"File{index:05d}.swift").write_text(source(index, detected=True))
    detected = commit(repository, "introduce benchmark debt", 2)
    return absent, detected


def artifact_info(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    document = json.loads(data)
    findings = document["findings"]
    events = [event for finding in findings for event in finding["events"]]
    kinds = {kind: sum(event["transition"]["kind"] == kind for event in events)
             for kind in ("opened", "observed", "resolved", "reopened", "unverified",
                          "continuity-ambiguous")}
    return {
        "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "snapshots": len(document["snapshots"]), "findings": len(findings),
        "events": len(events), "unresolvedDetections": len(document["unresolvedDetections"]),
        "introductionConclusions": len(document.get("introductionConclusions", [])),
        "eventKinds": kinds,
    }
