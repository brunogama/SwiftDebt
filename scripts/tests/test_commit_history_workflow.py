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


class CommitHistoryWorkflowTests(unittest.TestCase):
    def test_rewritten_feature_push_uses_current_default_merge_base(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "ci: establish commit policy")
            git(root, "switch", "-c", "feature")
            before = commit(root, "fix: amend the feature change")

            git(root, "switch", "main")
            commit(root, "unrelated default branch commit")
            set_remote_branch(root, "main")

            git(root, "switch", "feature")
            git(
                root,
                "commit",
                "--amend",
                "-m",
                "fix(lifecycle): show snapshot IDs for unresolved detections",
            )
            amended = git(root, "rev-parse", "HEAD")
            self.assertEqual(
                run(["git", "merge-base", "--is-ancestor", before, amended], root).returncode,
                1,
            )

            passing = run_script(root, cutover, before, "main", "feature")
            self.assertEqual(passing.returncode, 0, passing.stderr)
            self.assertIn("1 commits checked", passing.stdout)

            commit(root, "new feature commit without conventional format")
            failing = run_script(root, cutover, before, "main", "feature")
            self.assertEqual(failing.returncode, 1)
            self.assertIn("new feature commit without conventional format", failing.stderr)

    def test_fast_forward_push_keeps_the_newly_pushed_range(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "ci: establish commit policy")
            commit(root, "old nonconforming commit")
            before = git(root, "rev-parse", "HEAD")
            commit(root, "docs: document the new feature")
            set_remote_branch(root, "main")

            result = run_script(root, cutover, before, "main", "feature")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("1 commits checked", result.stdout)

    def test_rewritten_default_branch_does_not_bypass_validation(self) -> None:
        with temporary_repository() as root:
            cutover = commit(root, "ci: establish commit policy")
            before = commit(root, "docs: explain default branch history")
            git(root, "commit", "--amend", "-m", "rewritten default branch commit")
            set_remote_branch(root, "main")

            result = run_script(root, cutover, before, "main", "main")

            self.assertEqual(result.returncode, 1)
            self.assertIn("rewritten default branch commit", result.stderr)


def run(command: list[str], root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)


def git(root: Path, *arguments: str) -> str:
    result = run(["git", *arguments], root)
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def commit(root: Path, subject: str) -> str:
    marker = root / "marker.txt"
    previous = marker.read_text(encoding="utf-8") if marker.exists() else ""
    marker.write_text(previous + subject + "\n", encoding="utf-8")
    git(root, "add", "marker.txt")
    git(root, "commit", "-m", subject)
    return git(root, "rev-parse", "HEAD")


def set_remote_branch(root: Path, branch: str) -> None:
    git(root, "update-ref", f"refs/remotes/origin/{branch}", "HEAD")


def run_script(
    root: Path,
    cutover: str,
    before: str,
    default_branch: str,
    pushed_branch: str,
) -> subprocess.CompletedProcess[str]:
    return run(
        [
            sys.executable,
            str(SCRIPT),
            "--root",
            str(root),
            "--cutover",
            cutover,
            "--base",
            before,
            "--default-branch",
            default_branch,
            "--pushed-branch",
            pushed_branch,
        ],
        root,
    )


class temporary_repository:
    def __init__(self) -> None:
        self.directory: tempfile.TemporaryDirectory[str] | None = None

    def __enter__(self) -> Path:
        self.directory = tempfile.TemporaryDirectory(prefix="swiftdebt-commit-history-test-")
        root = Path(self.directory.name)
        git(root, "init", "-b", "main")
        git(root, "config", "user.name", "Commit History Test")
        git(root, "config", "user.email", "commit-history-test@example.invalid")
        return root

    def __exit__(self, *_: object) -> None:
        assert self.directory is not None
        self.directory.cleanup()


if __name__ == "__main__":
    unittest.main()
