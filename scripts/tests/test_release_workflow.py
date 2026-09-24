from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY / ".github" / "workflows" / "release.yml"
SWIFT_SETUP = "swift-actions/setup-swift@7ca6abe6b3b0e8b5421b88be48feee39cbf52c6a"
SWIFT_WORKFLOWS = (
    "debtmap-performance.yml",
    "domain-coverage.yml",
    "genesis-code-reviewer.yml",
    "pr-quality.yml",
    "release.yml",
)


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

    def test_swift_workflows_select_the_required_toolchain(self) -> None:
        for name in SWIFT_WORKFLOWS:
            with self.subTest(workflow=name):
                workflow = (WORKFLOW.parent / name).read_text(encoding="utf-8")
                self.assertIn(SWIFT_SETUP, workflow)
                self.assertIn('swift-version: "6.2.0"', workflow)
                self.assertIn("swift --version | grep 'Swift version 6.2'", workflow)

    def test_release_is_serialized_and_push_is_atomic(self) -> None:
        self.assertIn("branches: [main]", self.workflow)
        self.assertIn("cancel-in-progress: false", self.workflow)
        self.assertGreaterEqual(self.workflow.count("git rev-parse origin/main"), 2)
        self.assertIn("git push --atomic origin HEAD:refs/heads/main", self.workflow)
        self.assertNotIn("--force", self.workflow)

    def test_release_generates_changelog_and_versions_before_tagging(self) -> None:
        prepare = self.workflow.index("scripts/release_version.py prepare")
        changelog = self.workflow.index("scripts/generate_changelog.py")
        commit = self.workflow.index("git add CHANGELOG.md")
        tag = self.workflow.index("git tag --annotate")
        self.assertLess(prepare, changelog)
        self.assertLess(changelog, commit)
        self.assertLess(commit, tag)

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

    def test_commit_and_quality_workflows_enforce_new_history(self) -> None:
        cutover = "15fa039b0cfb9f7fe3ac9891c64199e038e7fe6b"
        checker = (WORKFLOW.parent / "commit-history.yml").read_text(encoding="utf-8")
        pull_request = (WORKFLOW.parent / "pr-quality.yml").read_text(encoding="utf-8")
        policy_script = (REPOSITORY / "scripts" / "check_conventional_commits.py").read_text(
            encoding="utf-8"
        )
        self.assertIn(cutover, policy_script)
        self.assertIn("github.event.before", checker)
        self.assertIn("github.event.repository.default_branch", checker)
        self.assertIn("git merge-base", checker)
        self.assertIn("github.event.pull_request.base.sha", pull_request)
        self.assertIn("fetch-depth: 0", checker)
        self.assertIn("fetch-depth: 0", pull_request)
        self.assertIn("swift format lint --strict --recursive", pull_request)
        self.assertIn("swift build --build-tests -Xswiftc -warnings-as-errors", pull_request)

    def test_tag_workflow_fails_instead_of_rewriting_an_immutable_tag(self) -> None:
        tag_workflow = (WORKFLOW.parent / "tag-documentation.yml").read_text(encoding="utf-8")
        self.assertIn('python3 scripts/release_version.py set "$version"', tag_workflow)
        self.assertIn("python3 scripts/release_version.py check", tag_workflow)
        self.assertIn("git diff --name-only", tag_workflow)
        self.assertIn("The tag is immutable", tag_workflow)
        self.assertNotIn("git push", tag_workflow)


if __name__ == "__main__":
    unittest.main()
