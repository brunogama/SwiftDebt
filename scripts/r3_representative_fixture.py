"""Read fixed real Swift source snapshots and replay them as Git commits."""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
import tarfile
from pathlib import Path

SOURCE_REVISIONS = (
    "c509396a5492106f94e74df718c84edfe2dbd894",
    "9c7d1c2d38c1c975786fd70b3a3d83c1428cf5af",
    "a4a3c6d680feb2a221f417048b4e34de65175234",
)
COMMAND_TIMEOUT = 600
CACHE_SOURCE_REVISION = SOURCE_REVISIONS[-1]
CACHE_CLEAN_PATH = "Sources/SwiftDebtSyntax/BuiltInRuleCatalog.swift"
CACHE_DETECTED_PATH = "Sources/SwiftDebtKit/AnalysisProfiler.swift"


def run(argv: list[str], *, cwd: Path | None = None, timeout: int = COMMAND_TIMEOUT) -> bytes:
    result = subprocess.run(argv, cwd=cwd, env={**os.environ, "LC_ALL": "C"},
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"exit {result.returncode}: {' '.join(argv)}\n"
                           + result.stderr.decode(errors="replace")[-3000:])
    return result.stdout


def source_snapshot(checkout: Path, revision: str) -> dict[str, bytes]:
    archive = run(["git", "archive", "--format=tar", revision, "Sources", "Tests"], cwd=checkout)
    sources: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as content:
        for member in content:
            if not member.name.endswith(".swift"):
                continue
            if (not member.isfile() or member.name.startswith("/") or ".." in Path(member.name).parts
                    or not member.name.startswith(("Sources/", "Tests/"))):
                raise RuntimeError("Git archive contains an unsafe Swift source path")
            file = content.extractfile(member)
            if file is None:
                raise RuntimeError("Git archive omitted Swift source bytes")
            sources[member.name] = file.read()
    if not sources:
        raise RuntimeError("fixed revision contains no Swift source files")
    return sources


def source_digest(sources: dict[str, bytes]) -> str:
    value = hashlib.sha256()
    for path, content in sorted(sources.items()):
        value.update(len(path.encode()).to_bytes(8, "big"))
        value.update(path.encode())
        value.update(len(content).to_bytes(8, "big"))
        value.update(content)
    return value.hexdigest()


def replace_sources(repository: Path, sources: dict[str, bytes]) -> None:
    for path in list(repository.rglob("*.swift")):
        path.unlink()
    for relative, content in sources.items():
        target = repository / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)


def commit(repository: Path, ordinal: int) -> str:
    environment = {**os.environ, "LC_ALL": "C", "GIT_AUTHOR_NAME": "SwiftDebt Benchmark",
                   "GIT_AUTHOR_EMAIL": "benchmark@example.invalid",
                   "GIT_COMMITTER_NAME": "SwiftDebt Benchmark",
                   "GIT_COMMITTER_EMAIL": "benchmark@example.invalid",
                   "GIT_AUTHOR_DATE": f"2026-01-{ordinal:02d}T12:00:00Z",
                   "GIT_COMMITTER_DATE": f"2026-01-{ordinal:02d}T12:00:00Z"}
    for command in (["git", "add", "-A"],
                    ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                     "commit", "-qm", f"record fixed source snapshot {ordinal}"]):
        result = subprocess.run(command, cwd=repository, env=environment,
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=False)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace"))
    return run(["git", "rev-parse", "HEAD"], cwd=repository).decode().strip()


def cache_source_states(checkout: Path) -> tuple[dict[str, bytes], dict[str, bytes]]:
    sources = source_snapshot(checkout, CACHE_SOURCE_REVISION)
    if CACHE_CLEAN_PATH not in sources or CACHE_DETECTED_PATH not in sources:
        raise RuntimeError("fixed real-source cache files are absent")
    if b"@unchecked Sendable" not in sources[CACHE_DETECTED_PATH]:
        raise RuntimeError("fixed cache Detection source no longer has its actual rule subject")
    clean = {CACHE_CLEAN_PATH: sources[CACHE_CLEAN_PATH]}
    detected = {**clean, CACHE_DETECTED_PATH: sources[CACHE_DETECTED_PATH]}
    return clean, detected
