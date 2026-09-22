from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY / ".github" / "workflows" / "release.yml"


class ReleaseWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_actions_are_sha_pinned(self) -> None:
        expected = (
            "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683",
            "actions/configure-pages@45bfe0192ca1faeb007ade9deae92b16b8254a0d",
            "actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9",
            "actions/deploy-pages@368f82528645a54fb793d4d04e342629a3f51346",
        )
        for action in expected:
            with self.subTest(action=action):
                self.assertIn(action, self.workflow)

    def test_release_is_serialized_and_push_is_atomic(self) -> None:
        self.assertIn("branches: [main]", self.workflow)
        self.assertIn("cancel-in-progress: false", self.workflow)
        self.assertGreaterEqual(self.workflow.count("git rev-parse origin/main"), 2)
        self.assertIn("git push --atomic origin HEAD:refs/heads/main", self.workflow)
        self.assertNotIn("--force", self.workflow)

    def test_documentation_uses_dynamic_hosting_path_and_repair_route(self) -> None:
        self.assertIn("REPOSITORY_NAME: ${{ github.event.repository.name }}", self.workflow)
        self.assertIn('--hosting-base-path "$REPOSITORY_NAME"', self.workflow)
        self.assertIn("status\" -ne 3", self.workflow)
        self.assertIn("if: steps.publish.outputs.deploy == 'true'", self.workflow)

    def test_job_permissions_are_bounded(self) -> None:
        self.assertIn("permissions:\n      contents: write", self.workflow)
        self.assertIn(
            "permissions:\n      contents: read\n      pages: write\n      id-token: write",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main()
