#!/usr/bin/env python3
"""Synchronize SwiftDebt release versions and plan semantic releases."""

from __future__ import annotations

import argparse
import enum
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


VERSION_PATTERN = re.compile(r"(?<![0-9])(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?![0-9])")
START_MARKER = "swiftdebt-release-version:start"
END_MARKER = "swiftdebt-release-version:end"
FIRST_RELEASE = "0.1.0"
RELEASE_COMMIT = re.compile(r"^chore\(release\): v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$")
BREAKING_SUBJECT = re.compile(r"^[a-z][a-z0-9-]*(?:\([^()]+\))?!:")
FEATURE_SUBJECT = re.compile(r"^feat(?:\([^()]+\))?:")
DRIFT_PROBES = (
    re.compile(r"SwiftDebt(?: release)? v?[0-9]+\.[0-9]+\.[0-9]+"),
    re.compile(r'engineVersion\s*:\s*"[0-9]+\.[0-9]+\.[0-9]+"'),
    re.compile(r"\*\*Version:\*\*\s*v?[0-9]+\.[0-9]+\.[0-9]+"),
    re.compile(r"Measurement specification - engine [0-9]+\.[0-9]+\.[0-9]+"),
    re.compile(
        r'\.package\((?=[^)]*SwiftDebt\.git)[^)]*(?:from|exact)\s*:\s*"[0-9]+\.[0-9]+\.[0-9]+"',
        re.DOTALL,
    ),
    re.compile(
        r"git clone(?=[\s\S]{0,300}SwiftDebt\.git)[\s\S]{0,300}--branch\s+v[0-9]+\.[0-9]+\.[0-9]+"
    ),
)


class ReleaseError(RuntimeError):
    """A user-actionable release-state failure."""


class BumpLevel(enum.IntEnum):
    PATCH = 1
    MINOR = 2
    MAJOR = 3


@dataclass(frozen=True, order=True)
class SemanticVersion:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, value: str) -> "SemanticVersion":
        if VERSION_PATTERN.fullmatch(value) is None:
            raise ReleaseError(f"invalid semantic version: {value!r}")
        return cls(*(int(component) for component in value.split(".")))

    def bump(self, level: BumpLevel) -> "SemanticVersion":
        if level is BumpLevel.MAJOR:
            return SemanticVersion(self.major + 1, 0, 0)
        if level is BumpLevel.MINOR:
            return SemanticVersion(self.major, self.minor + 1, 0)
        return SemanticVersion(self.major, self.minor, self.patch + 1)

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"


@dataclass(frozen=True)
class MarkerBlock:
    path: Path
    body_start: int
    body_end: int
    block_start: int
    block_end: int
    version: SemanticVersion


@dataclass(frozen=True)
class ReleasePlan:
    base_tag: str | None
    target: SemanticVersion
    commits: tuple[tuple[str, str], ...]
    requires_release: bool


def repository_files(root: Path) -> list[Path]:
    command = ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    result = subprocess.run(command, cwd=root, capture_output=True, check=False)
    if result.returncode != 0:
        raise ReleaseError("repository root is not a Git worktree")
    return [root / raw.decode() for raw in result.stdout.split(b"\0") if raw]


def ignored(path: Path, root: Path) -> bool:
    relative = path.relative_to(root).as_posix()
    return (
        relative in {"CHECKSUMS.sha256", "scripts/release_version.py"}
        or relative.startswith(("scripts/tests/", ".scratch/tickets/", "docs/validation-logs/"))
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


def marker_blocks(path: Path, text: str) -> list[MarkerBlock]:
    blocks: list[MarkerBlock] = []
    opened: tuple[int, int] | None = None
    offset = 0
    for line_number, line in enumerate(text.splitlines(keepends=True), start=1):
        has_start = START_MARKER in line
        has_end = END_MARKER in line
        if has_start and has_end:
            raise ReleaseError(f"{path}:{line_number}: marker tokens must be on separate lines")
        if has_start:
            if opened is not None:
                raise ReleaseError(f"{path}:{line_number}: nested release-version marker")
            opened = (offset, offset + len(line))
        elif has_end:
            if opened is None:
                raise ReleaseError(f"{path}:{line_number}: unmatched release-version end marker")
            block_start, body_start = opened
            body = text[body_start:offset]
            matches = list(VERSION_PATTERN.finditer(body))
            if len(matches) != 1:
                raise ReleaseError(
                    f"{path}:{line_number}: release-version block must contain exactly one semantic version"
                )
            blocks.append(
                MarkerBlock(
                    path=path,
                    body_start=body_start,
                    body_end=offset,
                    block_start=block_start,
                    block_end=offset + len(line),
                    version=SemanticVersion.parse(matches[0].group()),
                )
            )
            opened = None
        offset += len(line)
    if opened is not None:
        raise ReleaseError(f"{path}: unmatched release-version start marker")
    return blocks


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
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as temporary:
            temporary.write(text)
            temporary_path = temporary.name
        os.replace(temporary_path, path)


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(["git", *arguments], cwd=root, text=True, capture_output=True)
    if result.returncode != 0:
        raise ReleaseError(result.stderr.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout.strip()


def requested_bump(subject: str, body: str = "") -> BumpLevel | None:
    if RELEASE_COMMIT.fullmatch(subject):
        return None
    if BREAKING_SUBJECT.search(subject) or re.search(r"(?m)^BREAKING CHANGE:", body):
        return BumpLevel.MAJOR
    if FEATURE_SUBJECT.search(subject):
        return BumpLevel.MINOR
    return BumpLevel.PATCH


def commits_since(root: Path, tag: str) -> tuple[tuple[str, str], ...]:
    output = git(root, "log", f"{tag}..HEAD", "--format=%s%x00%b%x00%x1e")
    commits: list[tuple[str, str]] = []
    for record in output.split("\x1e"):
        fields = record.strip("\n").split("\x00")
        if len(fields) >= 2 and fields[0]:
            commits.append((fields[0], fields[1]))
    return tuple(commits)


def release_tags(root: Path) -> list[tuple[SemanticVersion, str, str]]:
    head = git(root, "rev-parse", "HEAD")
    tags: list[tuple[SemanticVersion, str, str]] = []
    for name in git(root, "tag", "--list", "v*").splitlines():
        try:
            version = SemanticVersion.parse(name.removeprefix("v"))
        except ReleaseError:
            continue
        if version < SemanticVersion.parse(FIRST_RELEASE):
            continue
        if subprocess.run(["git", "merge-base", "--is-ancestor", name, "HEAD"], cwd=root).returncode != 0:
            continue
        tags.append((version, name, git(root, "rev-list", "-n", "1", name)))
    return sorted(tags, key=lambda item: item[0])


def prepare_plan(root: Path) -> ReleasePlan:
    current = authored_version(root)
    head = git(root, "rev-parse", "HEAD")
    tags = release_tags(root)
    tags_at_head = [tag for tag in tags if tag[2] == head]
    if tags_at_head:
        version, tag, _ = tags_at_head[-1]
        if current != version:
            raise ReleaseError(f"HEAD tag {tag} does not match VERSION {current}")
        _, _, failures = audit(root)
        if failures:
            raise ReleaseError("; ".join(failures))
        return ReleasePlan(tag, version, (), False)
    if not tags:
        return ReleasePlan(None, SemanticVersion.parse(FIRST_RELEASE), (), True)
    base, tag, _ = tags[-1]
    commits = commits_since(root, tag)
    bumps = [level for subject, body in commits if (level := requested_bump(subject, body)) is not None]
    if not bumps:
        raise ReleaseError(f"HEAD has no non-release commits after {tag} and is not tagged")
    return ReleasePlan(tag, base.bump(max(bumps)), commits, True)


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check")
    setter = subparsers.add_parser("set")
    setter.add_argument("version")
    subparsers.add_parser("prepare")
    args = parser.parse_args(arguments)
    root = args.root.resolve()
    try:
        if args.command == "check":
            version, blocks, failures = audit(root)
            if failures:
                raise ReleaseError("\n".join(failures))
            print(f"release version: PASS ({version}, {len(blocks)} markers)")
            return 0
        if args.command == "set":
            target = SemanticVersion.parse(args.version)
            replace_versions(root, target)
            print(target)
            return 0
        plan = prepare_plan(root)
        if plan.requires_release:
            replace_versions(root, plan.target)
        print(plan.target)
        return 0 if plan.requires_release else 3
    except ReleaseError as error:
        print(f"release version: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
