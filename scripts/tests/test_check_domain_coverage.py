"""Coverage gate diagnostics from SwiftPM's exported JSON."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_domain_coverage.py"
CORE_SOURCE = ROOT / "Sources" / "SwiftDebtCore" / "RepositoryEvidenceCanonicalization.swift"


class DomainCoverageDiagnosticsTests(unittest.TestCase):
    def run_checker(self, covered: int, counts: list[int]) -> subprocess.CompletedProcess[str]:
        report = {
            "data": [{
                "files": [{
                    "filename": str(CORE_SOURCE),
                    "summary": {"lines": {"covered": covered, "count": 2}},
                    "segments": [
                        [index + 4, 1, count, True, True, False]
                        for index, count in enumerate(counts)
                    ],
                }],
            }],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "coverage.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(CHECKER), "--coverage-json", str(path)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_failure_reports_zero_count_region_start(self) -> None:
        result = self.run_checker(covered=1, counts=[7, 0])

        self.assertEqual(result.returncode, 1)
        self.assertIn("zero-count coverage regions start at lines 5", result.stderr)
        self.assertIn("domain coverage: FAIL (1 executable lines uncovered)", result.stderr)

    def test_success_keeps_diagnostics_quiet(self) -> None:
        result = self.run_checker(covered=2, counts=[7, 1])

        self.assertEqual(result.returncode, 0)
        self.assertIn("domain coverage: PASS", result.stdout)
        self.assertNotIn("zero-count coverage regions", result.stderr)


if __name__ == "__main__":
    unittest.main()
