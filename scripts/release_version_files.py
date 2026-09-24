from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from release_version_model import DRIFT_PROBES, VERSION_PATTERN, MarkerBlock, ReleaseError, SemanticVersion, marker_blocks


def repository_files(root: Path) -> list[Path]:
    command = ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    result = subprocess.run(command, cwd=root, capture_output=True, check=False)
    if result.returncode != 0:
        raise ReleaseError("repository root is not a Git worktree")
    return [root / raw.decode() for raw in result.stdout.split(b"\0") if raw]


def ignored(path: Path, root: Path) -> bool:
    relative = path.relative_to(root).as_posix()
    return (
        relative in {"CHECKSUMS.sha256", "scripts/release_version_model.py"}
        or relative.startswith(("scripts/tests/", ".agents/evidence/", "docs/validation-logs/"))
        or relative.startswith("benchmarks/debtmap-baseline/evidence/")
    )


def text_files(root: Path) -> list[tuple[Path, str]]:
    result: list[tuple[Path, str]] = []
    for path in repository_files(root):
        if ignored(path, root) or not path.is_file():
            continue
        try:
            result.append((path, path.read_text(encoding="utf-8")))
        except UnicodeDecodeError:
            continue
    return result


def authored_version(root: Path) -> SemanticVersion:
    path = root / "VERSION"
    try:
        value = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError as error:
        raise ReleaseError("VERSION is missing") from error
    return SemanticVersion.parse(value)


def audit(root: Path) -> tuple[SemanticVersion, list[MarkerBlock], list[str]]:
    version = authored_version(root)
    blocks: list[MarkerBlock] = []
    failures: list[str] = []
    for path, text in text_files(root):
        file_blocks = marker_blocks(path.relative_to(root), text)
        blocks.extend(file_blocks)
        for block in file_blocks:
            if block.version != version:
                failures.append(f"{block.path}: marker has {block.version}, expected {version}")
        masked = list(text)
        for block in file_blocks:
            for index in range(block.block_start, block.block_end):
                if masked[index] != "\n":
                    masked[index] = " "
        unmarked = "".join(masked)
        for pattern in DRIFT_PROBES:
            for match in pattern.finditer(unmarked):
                line_number = unmarked.count("\n", 0, match.start()) + 1
                failures.append(f"{path.relative_to(root)}:{line_number}: unmarked SwiftDebt release version")
    if not blocks:
        failures.append("no release-version marker blocks found")
    return version, blocks, failures


def replace_versions(root: Path, target: SemanticVersion) -> None:
    updates: dict[Path, str] = {}
    for path, text in text_files(root):
        blocks = marker_blocks(path.relative_to(root), text)
        for block in reversed(blocks):
            body = text[block.body_start:block.body_end]
            body = VERSION_PATTERN.sub(str(target), body, count=1)
            text = text[:block.body_start] + body + text[block.body_end:]
        if blocks:
            updates[path] = text
    if not updates:
        raise ReleaseError("no release-version marker blocks found")
    updates[root / "VERSION"] = f"{target}\n"
    for path, text in updates.items():
        if path.exists() and path.read_text(encoding="utf-8") == text:
            continue
        mode = path.stat().st_mode if path.exists() else None
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as temporary:
            temporary.write(text)
            temporary_path = Path(temporary.name)
        if mode is not None:
            os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
