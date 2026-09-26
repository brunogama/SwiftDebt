"""Static contract tests for the public-CLI capacity probe."""

import importlib.util
import hashlib
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "r3_capacity_probe_support.py"
SPEC = importlib.util.spec_from_file_location("r3_capacity_probe_support", MODULE_PATH)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class CapacityProbeTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
