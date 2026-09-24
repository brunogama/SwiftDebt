from __future__ import annotations

import enum
import re
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
    pass


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


def requested_bump(subject: str, body: str = "") -> BumpLevel | None:
    if RELEASE_COMMIT.fullmatch(subject):
        return None
    if BREAKING_SUBJECT.search(subject) or re.search(r"(?m)^BREAKING CHANGE:", body):
        return BumpLevel.MAJOR
    if FEATURE_SUBJECT.search(subject):
        return BumpLevel.MINOR
    return BumpLevel.PATCH
