"""Fixture generation, artifact checks, and resource guards for the R3 capacity probe."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path


def source_with_findings(count: int) -> str:
    functions = []
    for start in range(0, count, 16):
        calls = "\n".join(
            f"    _ = try! mayThrow({index})"
            for index in range(start, min(start + 16, count))
        )
        functions.append(f"func debt{start // 16}() {{\n{calls}\n}}")
    return (
        "func mayThrow(_ value: Int) throws -> Int { value }\n"
        + "\n".join(functions)
        + "\n"
    )


def clean_source(sequence: int) -> str:
    return f"// capacity snapshot {sequence}\nfunc mayThrow(_ value: Int) throws -> Int {{ value }}\nfunc run() {{}}\n"


def require_artifact_shape(artifact: dict, *, snapshots: int, findings: int) -> dict:
    if (
        artifact.get("reportKind") != "swiftdebt-lifecycle"
        or artifact.get("schemaVersion") != 3
    ):
        raise ValueError("Unexpected lifecycle artifact kind or schema")
    observed = artifact.get("snapshots")
    persisted_findings = artifact.get("findings")
    processed = artifact.get("processedSnapshotIDs")
    edges = artifact.get("snapshotParentEdges")
    if not all(
        isinstance(value, list)
        for value in (observed, persisted_findings, processed, edges)
    ):
        raise ValueError("Missing lifecycle collections")
    if (len(observed), len(persisted_findings), len(processed), len(edges)) != (
        snapshots,
        findings,
        snapshots,
        snapshots - 1,
    ):
        raise ValueError("Lifecycle cardinality mismatch")
    ids = [item["id"] for item in observed]
    if len(set(ids)) != snapshots or set(processed) != set(ids):
        raise ValueError("Snapshot identity or processing mismatch")
    if len({item["id"] for item in persisted_findings}) != findings:
        raise ValueError("Finding identity mismatch")
    if artifact.get("unresolvedDetections"):
        raise ValueError("Unexpected unresolved detections")
    states = [item.get("lifecycleState") for item in persisted_findings]
    return {
        "snapshotIDs": ids,
        "findingIDs": [item["id"] for item in persisted_findings],
        "states": states,
    }


def require_inventory_shape(inventory: dict, *, findings: int, state: str) -> list[str]:
    if (
        inventory.get("reportKind") != "swiftdebt-lifecycle-inventory"
        or inventory.get("schemaVersion") != 2
    ):
        raise ValueError("Unexpected lifecycle inventory kind or schema")
    rows = inventory.get("findings")
    if not isinstance(rows, list) or len(rows) != findings:
        raise ValueError("Inventory Finding cardinality mismatch")
    if any(row.get("lifecycleState") != state for row in rows):
        raise ValueError("Inventory Finding state mismatch")
    if inventory.get("unresolvedDetections"):
        raise ValueError("Unexpected inventory unresolved detections")
    ids = [row["id"] for row in rows]
    if len(set(ids)) != findings:
        raise ValueError("Duplicate inventory Finding ID")
    return ids


def run(
    command: list[str], *, cwd: Path | None = None, timeout: float = 300
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command, cwd=cwd, text=True, capture_output=True, timeout=timeout, check=False
    )
    if result.returncode:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {command[0:3]!r}: {result.stderr[-2000:]}"
        )
    return result


def write_evidence(path: Path, evidence: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def preflight(directory: Path, minimum_free_gib: float) -> int:
    free = shutil.disk_usage(directory).free
    required = int(minimum_free_gib * 1024**3)
    if free < required:
        raise RuntimeError(f"Free disk {free} bytes is below required {required} bytes")
    return free


def bounded_timeout(deadline: float, command_limit: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError("Elapsed-time ceiling exceeded")
    return min(remaining, command_limit)


def git(repo: Path, *arguments: str, timeout: float = 300) -> str:
    return run(["git", *arguments], cwd=repo, timeout=timeout).stdout.strip()


def commit(
    repo: Path, content: str, sequence: int, *, deadline: float, command_limit: float
) -> str:
    (repo / "Capacity.swift").write_text(content)
    git(repo, "add", "Capacity.swift", timeout=bounded_timeout(deadline, command_limit))
    git(
        repo,
        "-c",
        "user.name=SwiftDebt Capacity Probe",
        "-c",
        "user.email=capacity@example.invalid",
        "commit",
        "-m",
        f"test(capacity): observe snapshot {sequence}",
        timeout=bounded_timeout(deadline, command_limit),
    )
    return git(
        repo, "rev-parse", "HEAD", timeout=bounded_timeout(deadline, command_limit)
    )


def inspect(
    artifact_path: Path,
    cli: Path,
    *,
    snapshots: int,
    findings: int,
    state: str,
    deadline: float,
    command_limit: float,
) -> dict:
    data = artifact_path.read_bytes()
    shape = require_artifact_shape(
        json.loads(data), snapshots=snapshots, findings=findings
    )
    result = run(
        [str(cli), "lifecycle", "inventory", str(artifact_path), "--format", "json"],
        timeout=bounded_timeout(deadline, command_limit),
    )
    inventory_ids = require_inventory_shape(
        json.loads(result.stdout), findings=findings, state=state
    )
    if set(inventory_ids) != set(shape["findingIDs"]):
        raise ValueError("Inventory and artifact Finding IDs differ")
    return {
        "artifactBytes": len(data),
        "artifactSHA256": hashlib.sha256(data).hexdigest(),
        "snapshotCount": snapshots,
        "findingCount": findings,
        "inventoryState": state,
        "findingIDSetSHA256": hashlib.sha256(
            "\n".join(sorted(inventory_ids)).encode()
        ).hexdigest(),
    }
