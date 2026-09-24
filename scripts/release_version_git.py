from __future__ import annotations

import subprocess
from pathlib import Path

from release_version_files import audit, authored_version
from release_version_model import FIRST_RELEASE, ReleaseError, ReleasePlan, SemanticVersion, requested_bump


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(["git", *arguments], cwd=root, text=True, capture_output=True)
    if result.returncode != 0:
        raise ReleaseError(result.stderr.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout.strip()


def commits_since(root: Path, tag: str) -> tuple[tuple[str, str], ...]:
    output = git(root, "log", f"{tag}..HEAD", "--format=%s%x00%b%x00%x1e")
    commits: list[tuple[str, str]] = []
    for record in output.split("\x1e"):
        fields = record.strip("\n").split("\x00")
        if len(fields) >= 2 and fields[0]:
            commits.append((fields[0], fields[1]))
    return tuple(commits)


def release_tags(root: Path) -> list[tuple[SemanticVersion, str, str]]:
    tags: list[tuple[SemanticVersion, str, str]] = []
    for name in git(root, "tag", "--list", "v*").splitlines():
        try:
            version = SemanticVersion.parse(name.removeprefix("v"))
        except ReleaseError:
            continue
        if version < SemanticVersion.parse(FIRST_RELEASE):
            continue
        if subprocess.run(
            ["git", "merge-base", "--is-ancestor", name, "HEAD"], cwd=root, capture_output=True
        ).returncode != 0:
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
        first_release = SemanticVersion.parse(FIRST_RELEASE)
        if current > first_release:
            raise ReleaseError(f"VERSION {current} is ahead of first release {first_release} without a release tag")
        return ReleasePlan(None, first_release, (), True)
    base, tag, _ = tags[-1]
    commits = commits_since(root, tag)
    bumps = [level for subject, body in commits if (level := requested_bump(subject, body)) is not None]
    if not bumps:
        raise ReleaseError(f"HEAD has no non-release commits after {tag} and is not tagged")
    return ReleasePlan(tag, base.bump(max(bumps)), commits, True)
