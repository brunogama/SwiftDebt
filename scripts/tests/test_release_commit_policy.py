from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
SCRIPT = REPOSITORY / "scripts" / "check_conventional_commits.py"
SPEC = importlib.util.spec_from_file_location("check_conventional_commits", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
commit_policy = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = commit_policy
SPEC.loader.exec_module(commit_policy)


class CommitPolicyTests(unittest.TestCase):
    def test_conventional_subjects_accept_types_scopes_and_breaking_changes(self) -> None:
        valid = (
            commit_value("feat: add analyzer"),
            commit_value("fix(parser): accept declarations"),
            commit_value("docs: clarify examples", "Co-Authored-By: Human Reviewer <human@example.com>"),
            commit_value(
                "feat(api)!: replace report schema",
                "BREAKING CHANGE: Consumers must update report decoding.",
            ),
        )
        invalid = (
            commit_value("Merge branch main"),
            commit_value("Fix: uppercase type"),
            commit_value("release-tools(ci): validate history"),
            commit_value("fix missing delimiter"),
            commit_value("fix: "),
            commit_value("fix(): empty scope"),
            commit_value("fix: do not end the subject with a period."),
            commit_value("feat!: omit required migration details"),
            commit_value("feat: omit breaking marker", "BREAKING CHANGE: Update callers."),
            commit_value("docs: " + "x" * 67),
            commit_value("ci: reject agent trailers", "Co-Authored-By: Claude <bot@example.com>"),
        )
        for value in valid:
            with self.subTest(subject=value.subject):
                self.assertIsNone(commit_policy.violation(value))
        for value in invalid:
            with self.subTest(subject=value.subject):
                self.assertIsNotNone(commit_policy.violation(value))

    def test_cutover_grandfathers_existing_history_and_checks_new_commits(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "Merge legacy history")
            commit(root, "fix(ci): validate new commits")
            passing = run_script(root, cutover)
            self.assertEqual(passing.returncode, 0, passing.stderr)
            self.assertIn("1 commits checked", passing.stdout)

            commit(root, "nonconforming new subject")
            failing = run_script(root, cutover)
            self.assertEqual(failing.returncode, 1)
            self.assertIn("nonconforming new subject", failing.stderr)

    def test_newer_base_limits_push_validation_range(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "Merge legacy history")
            commit(root, "bad post-cutover commit")
            before = git(root, "rev-parse", "HEAD")
            commit(root, "docs: document repository policy")
            result = run_script(root, cutover, base=before)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("1 commits checked", result.stdout)

    def test_zero_push_base_falls_back_to_cutover(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "Merge legacy history")
            commit(root, "not conventional")
            result = run_script(root, cutover, base="0" * 40)
            self.assertEqual(result.returncode, 1)
            self.assertIn("not conventional", result.stderr)

    def test_unavailable_push_base_falls_back_to_cutover(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "Merge legacy history")
            commit(root, "not conventional")
            missing = "0" * 39 + "1"
            result = run_script(root, cutover, base=missing)
            self.assertEqual(result.returncode, 1)
            self.assertIn("not conventional", result.stderr)

    def test_branch_from_pre_cutover_history_uses_its_merge_base(self) -> None:
        with temporary_repository() as root:
            old_base = commit(root, "chore: establish repository")
            git(root, "switch", "-c", "policy")
            cutover = commit(root, "ci: establish commit policy")
            git(root, "switch", "-c", "old-branch", old_base)
            commit(root, "fix: repair old branch")
            result = run_script(root, cutover, base=old_base)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("1 commits checked", result.stdout)

    def test_breaking_commit_requires_marker_and_footer_in_git_history(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "Merge legacy history")
            commit(
                root,
                "feat(api)!: replace report schema",
                "BREAKING CHANGE: Consumers must update report decoding.",
            )
            passing = run_script(root, cutover)
            self.assertEqual(passing.returncode, 0, passing.stderr)

            commit(root, "fix(api)!: omit migration footer")
            failing = run_script(root, cutover)
            self.assertEqual(failing.returncode, 1)
            self.assertIn("missing a BREAKING CHANGE footer", failing.stderr)

    def test_ai_coauthor_trailer_is_rejected_in_git_history(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "chore: establish policy")
            commit(root, "ci: check commit trailers", "Co-Authored-By: Claude <bot@example.com>")
            result = run_script(root, cutover)
            self.assertEqual(result.returncode, 1)
            self.assertIn("AI co-author trailer", result.stderr)


def run(command: list[str], root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)


def git(root: Path, *arguments: str) -> str:
    result = run(["git", *arguments], root)
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def commit(root: Path, subject: str, body: str = "") -> str:
    marker = root / "marker.txt"
    previous = marker.read_text(encoding="utf-8") if marker.exists() else ""
    marker.write_text(previous + subject + "\n", encoding="utf-8")
    git(root, "add", "marker.txt")
    arguments = ["commit", "-m", subject]
    if body:
        arguments.extend(("-m", body))
    git(root, *arguments)
    return git(root, "rev-parse", "HEAD")


def commit_value(subject: str, body: str = ""):
    return commit_policy.Commit(sha="a" * 40, subject=subject, body=body)


def run_script(root: Path, cutover: str, base: str | None = None) -> subprocess.CompletedProcess[str]:
    arguments = [
        sys.executable,
        str(SCRIPT),
        "--root",
        str(root),
        "--cutover",
        cutover,
    ]
    if base is not None:
        arguments.extend(("--base", base))
    return run(arguments, root)


class temporary_repository:
    def __init__(self) -> None:
        self.directory: tempfile.TemporaryDirectory[str] | None = None

    def __enter__(self) -> Path:
        self.directory = tempfile.TemporaryDirectory(prefix="swiftdebt-commit-policy-test-")
        root = Path(self.directory.name)
        git(root, "init", "-b", "main")
        git(root, "config", "user.name", "Commit Policy Test")
        git(root, "config", "user.email", "commit-policy-test@example.invalid")
        return root

    def __exit__(self, *_: object) -> None:
        assert self.directory is not None
        self.directory.cleanup()


if __name__ == "__main__":
    unittest.main()
