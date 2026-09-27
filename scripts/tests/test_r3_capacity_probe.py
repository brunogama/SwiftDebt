"""Static contract tests for the public-CLI capacity probe."""

import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).resolve().parents[1] / "r3_capacity_probe_support.py"
RUNNER_PATH = MODULE_PATH.with_name("run_r3_capacity_probe.py")
SPEC = importlib.util.spec_from_file_location("r3_capacity_probe_support", MODULE_PATH)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class CapacityProbeTests(unittest.TestCase):
    def test_startup_failure_replaces_stale_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            evidence.write_text('{"status":"passed","marker":"stale"}')
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER_PATH),
                    "--swift-debt",
                    "/usr/bin/true",
                    "--snapshots",
                    "3",
                    "--findings",
                    "0",
                    "--evidence",
                    str(evidence),
                    "--work-parent",
                    str(root),
                    "--minimum-free-gib",
                    "1000000",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(evidence.read_text())["status"], "failed")
            self.assertNotIn("stale", evidence.read_text())

    def test_replay_cannot_pass_after_total_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "fake-swift-debt"
            fake.write_text(FAKE_CLI)
            fake.chmod(0o755)
            evidence = root / "evidence.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER_PATH),
                    "--swift-debt",
                    str(fake),
                    "--snapshots",
                    "3",
                    "--findings",
                    "0",
                    "--evidence",
                    str(evidence),
                    "--work-parent",
                    str(root),
                    "--minimum-free-gib",
                    "0.001",
                    "--maximum-artifact-gib",
                    "0.001",
                    "--maximum-elapsed-seconds",
                    "3",
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=7,
            )
            self.assertEqual(result.returncode, 1)
            recorded = json.loads(evidence.read_text())
            self.assertEqual(recorded["status"], "failed")
            self.assertEqual(recorded["checkpoints"][-1]["sequence"], 3)
            self.assertIn("timed out", recorded["failure"])
            self.assertNotIn("replayWallSeconds", recorded)

    def test_cleanup_failure_cannot_leave_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "fake-swift-debt"
            fake.write_text(FAKE_CLI.replace("if count == 4:", "if False:"))
            fake.chmod(0o755)
            evidence = root / "evidence.json"
            sys.path.insert(0, str(RUNNER_PATH.parent))
            try:
                spec = importlib.util.spec_from_file_location(
                    "capacity_runner", RUNNER_PATH
                )
                runner = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(runner)
                arguments = [
                    str(RUNNER_PATH),
                    "--swift-debt",
                    str(fake),
                    "--snapshots",
                    "3",
                    "--findings",
                    "0",
                    "--evidence",
                    str(evidence),
                    "--work-parent",
                    str(root),
                    "--minimum-free-gib",
                    "0.001",
                    "--maximum-artifact-gib",
                    "0.001",
                    "--maximum-elapsed-seconds",
                    "5",
                ]
                with patch.object(sys, "argv", arguments), patch.object(
                    runner.shutil, "rmtree", side_effect=OSError("simulated cleanup")
                ):
                    self.assertEqual(runner.main(), 1)
            finally:
                sys.path.remove(str(RUNNER_PATH.parent))
            recorded = json.loads(evidence.read_text())
            self.assertEqual(recorded["status"], "failed")
            self.assertIn("Cleanup failed", recorded["failure"])

    def test_zero_finding_axis_accepts_empty_inventory(self):
        self.assertEqual(
            probe.require_inventory_shape(
                {
                    "reportKind": "swiftdebt-lifecycle-inventory",
                    "schemaVersion": 2,
                    "findings": [],
                    "unresolvedDetections": [],
                },
                findings=0,
                state="resolved",
            ),
            [],
        )

    def test_source_has_one_force_try_per_finding_without_long_functions(self):
        source = probe.source_with_findings(1_000)
        self.assertEqual(source.count("try! mayThrow("), 1_000)
        self.assertEqual(source.count("func debt"), 63)
        self.assertIn("func debt62()", source)
        self.assertNotIn("try!", probe.clean_source(3))
        self.assertNotEqual(probe.clean_source(3), probe.clean_source(4))

    def test_artifact_and_inventory_reject_missing_or_duplicate_findings(self):
        snapshots = [{"id": "s1"}, {"id": "s2"}, {"id": "s3"}]
        findings = [
            {"id": "f1", "lifecycleState": "resolved"},
            {"id": "f2", "lifecycleState": "resolved"},
        ]
        artifact = {
            "reportKind": "swiftdebt-lifecycle",
            "schemaVersion": 3,
            "snapshots": snapshots,
            "findings": findings,
            "processedSnapshotIDs": ["s1", "s2", "s3"],
            "snapshotParentEdges": [{}, {}],
            "unresolvedDetections": [],
        }
        inventory = {
            "reportKind": "swiftdebt-lifecycle-inventory",
            "schemaVersion": 2,
            "findings": findings,
            "unresolvedDetections": [],
        }
        self.assertEqual(
            len(
                probe.require_artifact_shape(artifact, snapshots=3, findings=2)[
                    "findingIDs"
                ]
            ),
            2,
        )
        self.assertEqual(
            probe.require_inventory_shape(inventory, findings=2, state="resolved"),
            ["f1", "f2"],
        )
        artifact["findings"] = [findings[0], findings[0]]
        with self.assertRaisesRegex(ValueError, "Finding identity"):
            probe.require_artifact_shape(artifact, snapshots=3, findings=2)
        inventory["findings"] = [findings[0], findings[0]]
        with self.assertRaisesRegex(ValueError, "Duplicate inventory"):
            probe.require_inventory_shape(inventory, findings=2, state="resolved")

    def test_fails_closed_on_disk_reserve_and_writes_atomic_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Free disk"):
                probe.preflight(root, 1_000_000)
            path = root / "evidence.json"
            probe.write_evidence(path, {"status": "running"})
            self.assertEqual(json.loads(path.read_text()), {"status": "running"})
            self.assertEqual(
                probe.file_sha256(path), hashlib.sha256(path.read_bytes()).hexdigest()
            )
            self.assertFalse(path.with_suffix(".json.tmp").exists())


FAKE_CLI = """#!/usr/bin/env python3
import json
import pathlib
import sys
import time

args = sys.argv[1:]
if args[0] == "analyze":
    artifact = pathlib.Path(args[args.index("--lifecycle-artifact") + 1])
    counter = artifact.with_suffix(".count")
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if count == 4:
        time.sleep(5)
    ids = [f"s{index}" for index in range(1, min(count, 3) + 1)]
    artifact.write_text(json.dumps({"reportKind": "swiftdebt-lifecycle", "schemaVersion": 3,
        "snapshots": [{"id": value} for value in ids], "findings": [],
        "processedSnapshotIDs": ids, "snapshotParentEdges": [{} for _ in ids[1:]],
        "unresolvedDetections": []}))
elif args[:2] == ["lifecycle", "inventory"]:
    print(json.dumps({"reportKind": "swiftdebt-lifecycle-inventory", "schemaVersion": 2,
        "findings": [], "unresolvedDetections": []}))
else:
    raise SystemExit(2)
"""


if __name__ == "__main__":
    unittest.main()
