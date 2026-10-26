from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
SCRIPT = REPOSITORY / "scripts" / "generate_changelog.py"
sys.path.insert(0, str(SCRIPT.parent))
from release_version_model import SemanticVersion

SPEC = importlib.util.spec_from_file_location("generate_changelog", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
changelog = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = changelog
SPEC.loader.exec_module(changelog)


class ChangelogTests(unittest.TestCase):
    def test_first_release_is_generated_idempotently(self) -> None:
        plan = changelog.ReleasePlan(None, version("0.1.0"), (), True)
        first = changelog.updated_changelog("", plan)
        second = changelog.updated_changelog(first, plan)
        self.assertEqual(first, second)
        self.assertIn("## [0.1.0]\n\n- Initial release.", first)

    def test_current_release_is_replaced_and_history_is_preserved(self) -> None:
        original_plan = changelog.ReleasePlan(
            "v0.1.0",
            version("0.1.1"),
            (("fix: old description", ""),),
            True,
        )
        existing = changelog.updated_changelog("", original_plan)
        existing += "\n## [0.1.0]\n\n- Initial release.\n"
        updated_plan = changelog.ReleasePlan(
            "v0.1.0",
            version("0.1.1"),
            (
                ("fix: correct parser output", ""),
                ("chore(release): v0.1.0", "SwiftDebt-Release: v0.1.0"),
            ),
            True,
        )
        updated = changelog.updated_changelog(existing, updated_plan)
        self.assertIn("- fix: correct parser output", updated)
        self.assertNotIn("old description", updated)
        self.assertNotIn("- chore(release):", updated)
        self.assertEqual(updated.count("## [0.1.1]"), 1)
        self.assertEqual(updated.count("## [0.1.0]"), 1)

    def test_unmanaged_changelog_is_not_overwritten(self) -> None:
        plan = changelog.ReleasePlan(None, version("0.1.0"), (), True)
        with self.assertRaisesRegex(changelog.ReleaseError, "not managed"):
            changelog.updated_changelog("# Handwritten notes\n", plan)


def version(value: str):
    return SemanticVersion.parse(value)


if __name__ == "__main__":
    unittest.main()
