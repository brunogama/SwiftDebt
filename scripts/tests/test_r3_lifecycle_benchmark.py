import json
import platform
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from r3_lifecycle_benchmark_support import (  # noqa: E402
    largest_artifact_bytes,
    validate_explanation,
    validate_incremental_artifact,
    validate_incremental_profile,
    validate_introduction_profile,
    validate_inventory,
)
from run_r3_lifecycle_benchmark import FIXTURE_VERSION, budget_failures  # noqa: E402


class R3LifecycleBenchmarkValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.finding = {
            "id": "finding-1",
            "events": [{"transition": {"kind": "opened"}}],
        }
        self.cold = {
            "findings": [self.finding],
            "snapshots": [{"id": "snapshot-1"}],
            "unresolvedDetections": [],
        }
        self.incremental = {
            "findings": [{"id": "finding-1", "events": [
                {"transition": {"kind": "opened"}},
                {"transition": {"kind": "observed"}},
            ]}],
            "snapshots": [
                {"id": "snapshot-1"},
                {"id": "snapshot-2", "detections": [{
                    "location": {"sourcePath": "Sources/File00000.swift", "line": 3},
                    "rule": {"id": "force-try"},
                }]},
            ],
            "unresolvedDetections": [],
        }

    def encoded(self, value: dict) -> bytes:
        return json.dumps(value).encode()

    def test_incremental_requires_observed_continuity_and_shifted_location(self) -> None:
        validate_incremental_artifact(self.encoded(self.cold), self.encoded(self.incremental), 1)
        self.incremental["findings"][0]["events"][1]["transition"]["kind"] = "unverified"
        with self.assertRaisesRegex(RuntimeError, "continuity"):
            validate_incremental_artifact(self.encoded(self.cold), self.encoded(self.incremental), 1)
        self.incremental["findings"][0]["events"][1]["transition"]["kind"] = "observed"
        self.incremental["snapshots"][1]["detections"][0]["location"]["line"] = 2
        with self.assertRaisesRegex(RuntimeError, "shifted"):
            validate_incremental_artifact(self.encoded(self.cold), self.encoded(self.incremental), 1)

    def test_incremental_rejects_replacement_finding_with_same_count(self) -> None:
        self.incremental["findings"][0]["id"] = "finding-2"
        with self.assertRaisesRegex(RuntimeError, "continuity"):
            validate_incremental_artifact(self.encoded(self.cold), self.encoded(self.incremental), 1)

    def test_inventory_and_explanation_validate_public_json(self) -> None:
        inventory = {
            "reportKind": "swiftdebt-lifecycle-inventory",
            "headSnapshotIDs": ["snapshot-1"],
            "findings": [{"id": "finding-1", "lifecycleState": "open", "evidenceState": "observed"}],
            "unresolvedDetections": [],
        }
        validate_inventory(json.dumps(inventory), [self.finding], "snapshot-1")
        inventory["findings"][0]["evidenceState"] = "unverified"
        with self.assertRaisesRegex(RuntimeError, "inventory"):
            validate_inventory(json.dumps(inventory), [self.finding], "snapshot-1")

        explanation = {
            "reportKind": "swiftdebt-lifecycle-finding-explanation",
            "finding": self.finding,
            "projections": [{"snapshotID": "snapshot-1", "finding": self.finding}],
            "supportingSnapshots": [{"id": "snapshot-1"}],
            "unresolvedDetections": [],
        }
        validate_explanation(json.dumps(explanation), self.finding, "snapshot-1")
        explanation["supportingSnapshots"] = []
        with self.assertRaisesRegex(RuntimeError, "explanation"):
            validate_explanation(json.dumps(explanation), self.finding, "snapshot-1")

    def test_artifact_ceiling_uses_largest_recorded_artifact(self) -> None:
        tier = {
            "coldArtifact": {"bytes": 100},
            "incrementalArtifact": {"bytes": 180},
            "introductionArtifact": {"bytes": 240},
        }
        self.assertEqual(largest_artifact_bytes(tier), 240)

    def test_calibrated_budget_rejects_measured_regression(self) -> None:
        result = {
            "runnerDirty": False,
            "environment": {"cpuModel": "fixture CPU", "swift": "fixture Swift"},
            "tiers": {"small": {
                "coldArtifact": {"bytes": 100},
                "incrementalArtifact": {"bytes": 180},
                "introductionArtifact": {"bytes": 240},
                "incrementalReconciliation": {"medianElapsedNanoseconds": 500_000_000},
                "operations": {"cold": {
                    "medianWallSeconds": 1.0,
                    "maximumPeakRSSBytes": 1000,
                }},
            }},
        }
        budgets = {
            "fixtureVersion": FIXTURE_VERSION,
            "platformFamily": sys.platform,
            "machine": platform.machine(),
            "cpuModel": "fixture CPU",
            "swiftVersion": "fixture Swift",
            "tiers": {"small": {
                "maximumArtifactBytes": 300,
                "maximumMedianReconciliationSeconds": 1.0,
                "maximumMedianWallSeconds": {"cold": 2.0},
                "maximumPeakRSSBytes": {"cold": 1500},
            }},
        }
        self.assertEqual(budget_failures(result, budgets), [])
        result["tiers"]["small"]["operations"]["cold"]["medianWallSeconds"] = 2.01
        self.assertEqual(
            budget_failures(result, budgets),
            ["small/cold: median wall time exceeds limit"],
        )
        result["tiers"]["small"]["operations"]["cold"]["medianWallSeconds"] = 1.0
        result["tiers"]["small"]["operations"]["cold"]["maximumPeakRSSBytes"] = 1501
        result["tiers"]["small"]["incrementalArtifact"]["bytes"] = 301
        result["tiers"]["small"]["incrementalReconciliation"]["medianElapsedNanoseconds"] = 1_000_000_001
        self.assertEqual(
            budget_failures(result, budgets),
            ["small: artifact exceeds byte limit",
             "small: median reconciliation time exceeds limit",
             "small/cold: peak RSS exceeds limit"],
        )
        result["runnerDirty"] = True
        with self.assertRaisesRegex(RuntimeError, "clean runner checkout"):
            budget_failures(result, budgets)

    def test_introduction_profile_is_bound_to_persisted_history(self) -> None:
        conclusion = {
            "findingID": "finding-1",
            "evidence": {
                "revisions": [{"revision": "a"}, {"revision": "b"}],
                "boundary": {"maximumRevisions": 4, "frontierRevisions": []},
            }
        }
        profile = {
            "reportKind": "swiftdebt-lifecycle-introduction-profile",
            "schemaVersion": 1,
            "findingID": "finding-1",
            "maximumRevisions": 4,
            "maximumFileBytes": 16 * 1_024 * 1_024,
            "evidenceRevisionCount": 2,
            "analyzedRevisionCount": 2,
            "reusedRevisionCount": 0,
            "frontierRevisionCount": 0,
            "recordingStatus": "already-present",
            "operationElapsedNanoseconds": 1,
        }
        self.assertEqual(
            validate_introduction_profile(
                json.dumps(profile), conclusion, finding_id="finding-1",
                maximum_revisions=4, maximum_file_bytes=16 * 1_024 * 1_024,
                recording_status="already-present",
            )["reusedRevisionCount"],
            0,
        )
        for key, value in (
            ("reportKind", "other"),
            ("evidenceRevisionCount", 1),
            ("analyzedRevisionCount", 1),
            ("reusedRevisionCount", -1),
            ("frontierRevisionCount", 1),
            ("operationElapsedNanoseconds", 0),
            ("recordingStatus", "accepted"),
        ):
            changed = dict(profile, **{key: value})
            with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, "introduction profile"):
                validate_introduction_profile(
                    json.dumps(changed), conclusion, finding_id="finding-1",
                    maximum_revisions=4, maximum_file_bytes=16 * 1_024 * 1_024,
                    recording_status="already-present",
                )
        for changed_conclusion in (
            dict(conclusion, findingID="finding-2"),
            dict(
                conclusion,
                evidence=dict(
                    conclusion["evidence"],
                    boundary={"maximumRevisions": 8, "frontierRevisions": []},
                ),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "introduction profile"):
                validate_introduction_profile(
                    json.dumps(profile), changed_conclusion, finding_id="finding-1",
                    maximum_revisions=4, maximum_file_bytes=16 * 1_024 * 1_024,
                    recording_status="already-present",
                )

    def test_reconciliation_profile_is_bound_to_observed_continuity(self) -> None:
        record = {
            "snapshotID": "snapshot-2", "detections": 1, "candidates": 1,
            "evaluatedPairs": 1, "crediblePairs": 1, "uniqueContinuities": 1,
            "newFindings": 0, "unresolvedDetections": 0, "ambiguousGroups": 0,
            "processingElapsedNanoseconds": 200, "reconciliationElapsedNanoseconds": 100,
        }
        profile = {"schemaVersion": 1, "lifecycleReconciliation": [record]}
        self.assertEqual(
            validate_incremental_profile(self.encoded(profile), self.encoded(self.incremental), 1),
            {key: value for key, value in record.items() if key != "snapshotID"},
        )
        for key, value in (
            ("snapshotID", "wrong-snapshot"), ("candidates", 0),
            ("evaluatedPairs", 999), ("crediblePairs", 999),
            ("uniqueContinuities", 0), ("reconciliationElapsedNanoseconds", 0),
        ):
            changed = dict(record, **{key: value})
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                validate_incremental_profile(
                    self.encoded({"schemaVersion": 1, "lifecycleReconciliation": [changed]}),
                    self.encoded(self.incremental), 1,
                )

    def test_reconciliation_profile_counts_assessed_pairs_not_cartesian_pairs(self) -> None:
        incremental = json.loads(json.dumps(self.incremental))
        second = json.loads(json.dumps(incremental["snapshots"][-1]["detections"][0]))
        second["location"]["sourcePath"] = "Sources/File00001.swift"
        incremental["snapshots"][-1]["detections"].append(second)
        record = {
            "snapshotID": "snapshot-2", "detections": 2, "candidates": 2,
            "evaluatedPairs": 2, "crediblePairs": 2, "uniqueContinuities": 2,
            "newFindings": 0, "unresolvedDetections": 0, "ambiguousGroups": 0,
            "processingElapsedNanoseconds": 200, "reconciliationElapsedNanoseconds": 100,
        }
        profile = {"schemaVersion": 1, "lifecycleReconciliation": [record]}
        validate_incremental_profile(self.encoded(profile), self.encoded(incremental), 2)
        record["evaluatedPairs"] = 4
        with self.assertRaisesRegex(RuntimeError, "incremental profile"):
            validate_incremental_profile(self.encoded(profile), self.encoded(incremental), 2)


if __name__ == "__main__":
    unittest.main()
