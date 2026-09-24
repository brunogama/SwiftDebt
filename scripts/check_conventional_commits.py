#!/usr/bin/env python3
"""Validate commit subjects introduced after the commit-policy cutover."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_CUTOVER = "15fa039b0cfb9f7fe3ac9891c64199e038e7fe6b"
ZERO_REVISION = re.compile(r"^0+$")
ALLOWED_TYPES = (
    "build",
    "chore",
    "ci",
    "docs",
    "feat",
    "fix",
    "perf",
    "refactor",
    "revert",
    "style",
    "test",
)
CONVENTIONAL_SUBJECT = re.compile(
    rf"^(?P<type>{'|'.join(ALLOWED_TYPES)})(?:\([^()\r\n]+\))?"
    r"(?P<breaking>!)?: (?P<description>[^\s\r\n].*)$"
)
BREAKING_FOOTER = re.compile(r"(?m)^BREAKING CHANGE: \S.*$")


class CommitPolicyError(RuntimeError):
    pass


@dataclass(frozen=True)
class Commit:
    sha: str
    subject: str
    body: str = ""


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or f"git {' '.join(arguments)} failed"
        raise CommitPolicyError(message)
    return result.stdout.strip()


def resolve_commit(root: Path, revision: str, label: str) -> str:
    try:
        return git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
    except CommitPolicyError as error:
        raise CommitPolicyError(f"{label} is not an available commit: {revision}") from error


def is_available(root: Path, revision: str) -> bool:
    try:
        git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
    except CommitPolicyError:
        return False
    return True


def is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root,
        capture_output=True,
        check=False,
    )
    if result.returncode not in (0, 1):
        raise CommitPolicyError(result.stderr.decode().strip() or "git merge-base failed")
    return result.returncode == 0


def merge_base(root: Path, left: str, right: str) -> str:
    try:
        return git(root, "merge-base", left, right)
    except CommitPolicyError as error:
        raise CommitPolicyError(f"base {left} and head {right} have no common ancestor") from error


def validation_base(root: Path, base: str | None, head: str, cutover: str) -> tuple[str, str]:
    resolved_head = resolve_commit(root, head, "head")
    resolved_cutover = resolve_commit(root, cutover, "cutover")
    # A force-push reports the replaced commit as the base. That commit is no longer
    # reachable from any ref, so the checkout does not contain it and it cannot bound
    # the range. Treat it like an absent base and fall back to the cutover, which
    # validates every commit the policy covers rather than skipping the push.
    if base is None or ZERO_REVISION.fullmatch(base) or not is_available(root, base):
        if not is_ancestor(root, resolved_cutover, resolved_head):
            raise CommitPolicyError("a base commit is required when head predates the policy cutover")
        return resolved_cutover, resolved_head
    resolved_base = resolve_commit(root, base, "base")
    common_base = merge_base(root, resolved_base, resolved_head)
    if is_ancestor(root, resolved_cutover, resolved_head) and is_ancestor(
        root, common_base, resolved_cutover
    ):
        return resolved_cutover, resolved_head
    return common_base, resolved_head


def commits_between(root: Path, base: str, head: str) -> tuple[Commit, ...]:
    output = git(
        root,
        "log",
        "--reverse",
        "--topo-order",
        "--format=%H%x00%s%x00%b%x1e",
        f"{base}..{head}",
    )
    commits: list[Commit] = []
    for record in output.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        try:
            sha, subject, body = record.split("\x00", maxsplit=2)
        except ValueError as error:
            raise CommitPolicyError("could not parse git log output") from error
        commits.append(Commit(sha=sha, subject=subject, body=body.rstrip("\n")))
    return tuple(commits)


def violation(commit: Commit) -> str | None:
    match = CONVENTIONAL_SUBJECT.fullmatch(commit.subject)
    if match is None:
        return "subject does not use an allowed Conventional Commit type and format"
    if len(commit.subject) > 72:
        return "subject exceeds 72 characters"
    if commit.subject.endswith("."):
        return "subject must not end with a period"
    has_bang = match.group("breaking") == "!"
    has_footer = BREAKING_FOOTER.search(commit.body) is not None
    if has_bang and not has_footer:
        return "breaking subject is missing a BREAKING CHANGE footer"
    if has_footer and not has_bang:
        return "BREAKING CHANGE footer requires ! in the subject"
    return None


def violations(commits: tuple[Commit, ...]) -> tuple[tuple[Commit, str], ...]:
    return tuple(
        (commit, reason) for commit in commits if (reason := violation(commit)) is not None
    )


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--cutover", default=DEFAULT_CUTOVER)
    args = parser.parse_args(arguments)
    try:
        base, head = validation_base(args.root.resolve(), args.base, args.head, args.cutover)
        commits = commits_between(args.root.resolve(), base, head)
        failures = violations(commits)
        if failures:
            print("commit policy: FAIL", file=sys.stderr)
            for commit, reason in failures:
                print(f"{commit.sha[:12]} {commit.subject}: {reason}", file=sys.stderr)
            return 1
        print(f"commit policy: PASS ({len(commits)} commits checked after {base[:12]})")
        return 0
    except CommitPolicyError as error:
        print(f"commit policy: FAIL: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
