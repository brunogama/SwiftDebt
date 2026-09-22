from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
SCRIPT = REPOSITORY / "scripts" / "release_version.py"
SPEC = importlib.util.spec_from_file_location("release_version", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
release_version = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release_version
SPEC.loader.exec_module(release_version)


class ReleaseVersionTests(unittest.TestCase):
    def test_semantic_version_parsing_is_strict_and_numeric(self) -> None:
        parsed = release_version.SemanticVersion.parse("10.2.31")
        self.assertEqual((parsed.major, parsed.minor, parsed.patch), (10, 2, 31))
        self.assertLess(release_version.SemanticVersion.parse("2.0.0"), parsed)
        for invalid in ("v1.2.3", "1.2", "01.2.3", "1.2.3-beta", " 1.2.3"):
            with self.subTest(invalid=invalid), self.assertRaises(release_version.ReleaseError):
                release_version.SemanticVersion.parse(invalid)

    def test_bump_precedence_and_release_commit_exclusion(self) -> None:
        cases = (
            ("docs: clarify usage", "", release_version.BumpLevel.PATCH),
            ("feat: add report", "", release_version.BumpLevel.MINOR),
            ("feat(core)!: replace schema", "", release_version.BumpLevel.MAJOR),
            ("fix: accept input", "BREAKING CHANGE: remove old input", release_version.BumpLevel.MAJOR),
            ("chore(release): v1.2.3", "", None),
        )
        for subject, body, expected in cases:
            with self.subTest(subject=subject):
                self.assertEqual(release_version.requested_bump(subject, body), expected)

    def test_markers_set_and_check_without_changing_unrelated_versions(self) -> None:
        with temporary_repository() as root:
            document = root / "Guide.md"
            document.write_text(
                "Swift 6.2\nSwiftSyntax 602.0.0\nDebtmap 0.23.0\n"
                "<!-- swiftdebt-release-version:start -->\nSwiftDebt 0.1.0\n"
                "<!-- swiftdebt-release-version:end -->\n",
                encoding="utf-8",
            )
            before = document.read_text(encoding="utf-8")
            result = run_script(root, "set", "2.4.6")
            self.assertEqual(result.returncode, 0, result.stderr)
            after = document.read_text(encoding="utf-8")
            self.assertIn("SwiftDebt 2.4.6", after)
            for unrelated in ("Swift 6.2", "SwiftSyntax 602.0.0", "Debtmap 0.23.0"):
                self.assertEqual(before.count(unrelated), after.count(unrelated))
            self.assertEqual(run_script(root, "check").returncode, 0)

    def test_check_detects_marker_drift_and_unmarked_release_literal(self) -> None:
        with temporary_repository() as root:
            write_marker(root, "0.1.1")
            drift = run_script(root, "check")
            self.assertEqual(drift.returncode, 1)
            self.assertIn("expected 0.1.0", drift.stderr)
            write_marker(root, "0.1.0")
            (root / "Unmanaged.md").write_text("Install SwiftDebt 0.1.0 today.\n", encoding="utf-8")
            unmanaged = run_script(root, "check")
            self.assertEqual(unmanaged.returncode, 1)
            self.assertIn("unmarked SwiftDebt release version", unmanaged.stderr)

    def test_check_detects_multiline_unmarked_package_dependency(self) -> None:
        with temporary_repository() as root:
            write_marker(root, "0.1.0")
            (root / "PackageExample.md").write_text(
                ".package(\n"
                '    url: "https://github.com/brunogama/SwiftDebt.git",\n'
                '    from: "0.1.0"\n'
                ")\n",
                encoding="utf-8",
            )
            result = run_script(root, "check")
            self.assertEqual(result.returncode, 1)
            self.assertIn("unmarked SwiftDebt release version", result.stderr)

    def test_malformed_marker_blocks_are_rejected(self) -> None:
        for body in ("no version here", "versions 0.1.0 and 0.2.0"):
            with self.subTest(body=body), temporary_repository() as root:
                (root / "Guide.md").write_text(
                    f"<!-- swiftdebt-release-version:start -->\n{body}\n"
                    "<!-- swiftdebt-release-version:end -->\n",
                    encoding="utf-8",
                )
                result = run_script(root, "check")
                self.assertEqual(result.returncode, 1)
                self.assertIn("exactly one semantic version", result.stderr)

    def test_legacy_tag_bootstraps_exactly_0_1_0(self) -> None:
        with temporary_repository(initial_version="0.0.1") as root:
            commit_all(root, "feat: legacy implementation")
            git(root, "tag", "v0.0.1")
            result = run_script(root, "prepare")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "0.1.0")
            self.assertEqual((root / "VERSION").read_text().strip(), "0.1.0")
            self.assertEqual(git(root, "tag", "--list", "v0.0.1"), "v0.0.1")

    def test_patch_minor_and_major_release_plans(self) -> None:
        cases = (
            ("docs: update guide", "0.1.1"),
            ("feat: add report", "0.2.0"),
            ("refactor(core)!: replace report", "1.0.0"),
        )
        for subject, expected in cases:
            with self.subTest(subject=subject), tagged_repository() as root:
                (root / "change.txt").write_text(subject, encoding="utf-8")
                commit_all(root, subject)
                result = run_script(root, "prepare")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_repeated_prepare_is_idempotent_before_release_commit(self) -> None:
        with tagged_repository() as root:
            (root / "change.txt").write_text("change", encoding="utf-8")
            commit_all(root, "fix: update analyzer")
            first = run_script(root, "prepare")
            snapshot = (root / "VERSION").read_bytes(), (root / "Guide.md").read_bytes()
            second = run_script(root, "prepare")
            self.assertEqual((first.returncode, second.returncode), (0, 0))
            self.assertEqual(first.stdout, second.stdout)
            self.assertEqual(snapshot, ((root / "VERSION").read_bytes(), (root / "Guide.md").read_bytes()))

    def test_non_ancestor_tag_is_ignored(self) -> None:
        with tagged_repository() as root:
            git(root, "switch", "-c", "unrelated")
            (root / "side.txt").write_text("side", encoding="utf-8")
            commit_all(root, "feat!: unrelated rewrite")
            git(root, "tag", "v9.0.0")
            git(root, "switch", "main")
            (root / "change.txt").write_text("main", encoding="utf-8")
            commit_all(root, "fix: main change")
            result = run_script(root, "prepare")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "0.1.1")

    def test_already_tagged_head_prints_version_and_exits_three(self) -> None:
        with tagged_repository() as root:
            result = run_script(root, "prepare")
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual(result.stdout.strip(), "0.1.0")
            self.assertEqual(git(root, "status", "--porcelain"), "")


def run(command: list[str], root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)


def git(root: Path, *arguments: str) -> str:
    result = run(["git", *arguments], root)
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def run_script(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return run([sys.executable, str(SCRIPT), "--root", str(root), *arguments], root)


def write_marker(root: Path, version: str) -> None:
    (root / "Guide.md").write_text(
        "<!-- swiftdebt-release-version:start -->\n"
        f"SwiftDebt {version}\n"
        "<!-- swiftdebt-release-version:end -->\n",
        encoding="utf-8",
    )


def commit_all(root: Path, subject: str) -> None:
    git(root, "add", ".")
    git(root, "commit", "-m", subject)


class temporary_repository:
    def __init__(self, initial_version: str = "0.1.0") -> None:
        self.initial_version = initial_version
        self.directory: tempfile.TemporaryDirectory[str] | None = None

    def __enter__(self) -> Path:
        self.directory = tempfile.TemporaryDirectory(prefix="swiftdebt-release-test-")
        root = Path(self.directory.name)
        git(root, "init", "-b", "main")
        git(root, "config", "user.name", "Release Test")
        git(root, "config", "user.email", "release-test@example.invalid")
        (root / "VERSION").write_text(f"{self.initial_version}\n", encoding="utf-8")
        write_marker(root, self.initial_version)
        return root

    def __exit__(self, *_: object) -> None:
        assert self.directory is not None
        self.directory.cleanup()


class tagged_repository(temporary_repository):
    def __enter__(self) -> Path:
        root = super().__enter__()
        commit_all(root, "feat: bootstrap SwiftDebt")
        git(root, "tag", "v0.1.0")
        return root


if __name__ == "__main__":
    unittest.main()
