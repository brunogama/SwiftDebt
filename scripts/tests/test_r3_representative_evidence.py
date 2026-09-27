"""Contract checks for the real-source R3 evidence reader."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from r3_representative_evidence_support import (  # noqa: E402
    introduction_profile, require_cache_work, snapshot_metrics,
)
from r3_representative_fixture import (  # noqa: E402
    CACHE_CLEAN_PATH, CACHE_DETECTED_PATH, SOURCE_REVISIONS, cache_source_states,
    source_digest, source_snapshot,
)


class RepresentativeEvidenceTests(unittest.TestCase):
    def test_cache_work_requires_exact_two_revision_profile(self) -> None:
        profile = {"recordingStatus": "already-present", "evidenceRevisionCount": 2,
                   "analyzedRevisionCount": 1, "reusedRevisionCount": 1,
                   "frontierRevisionCount": 0}
        require_cache_work(profile, status="already-present", analyzed=1, reused=1)
        for field, value in (("evidenceRevisionCount", 1),
                             ("analyzedRevisionCount", 2),
                             ("reusedRevisionCount", 0),
                             ("frontierRevisionCount", 1),
                             ("recordingStatus", "accepted")):
            invalid = {**profile, field: value}
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "cache work"):
                require_cache_work(invalid, status="already-present", analyzed=1, reused=1)

    def test_fixed_revisions_contain_real_changed_swift_sources(self) -> None:
        checkout = SCRIPTS.parent
        sources = [source_snapshot(checkout, revision) for revision in SOURCE_REVISIONS]
        self.assertTrue(all(len(item) >= 100 for item in sources))
        self.assertEqual(len({source_digest(item) for item in sources}), 3)
        self.assertTrue(all(path.startswith(("Sources/", "Tests/"))
                            for item in sources for path in item))

    def test_snapshot_rates_account_for_every_detection(self) -> None:
        rule = {"namespace": "swiftdebt", "id": "force-try", "semanticRevision": 1}
        artifact = {
            "snapshots": [{"id": "later", "rules": [rule],
                           "detections": [{"rule": rule}, {"rule": rule}, {"rule": rule}]}],
            "findings": [{"events": [{"snapshotID": "later", "transition": {"kind": "observed"}}]},
                         {"events": [{"snapshotID": "later", "transition": {"kind": "opened"}}]}],
            "unresolvedDetections": [{"snapshotID": "later"}],
        }
        metrics = snapshot_metrics(artifact, "later")
        self.assertEqual(metrics["uniqueContinuity"], 1)
        self.assertEqual(metrics["newFindings"], 1)
        self.assertEqual(metrics["unresolvedDetections"], 1)
        self.assertEqual(metrics["rates"]["uniqueContinuity"], 1 / 3)
        artifact["unresolvedDetections"] = []
        with self.assertRaisesRegex(RuntimeError, "account"):
            snapshot_metrics(artifact, "later")

    def test_cache_source_states_use_unmodified_real_files(self) -> None:
        clean, detected = cache_source_states(SCRIPTS.parent)
        self.assertEqual(set(clean), {CACHE_CLEAN_PATH})
        self.assertEqual(set(detected), {CACHE_CLEAN_PATH, CACHE_DETECTED_PATH})
        self.assertEqual(clean[CACHE_CLEAN_PATH], detected[CACHE_CLEAN_PATH])
        self.assertIn(b"@unchecked Sendable", detected[CACHE_DETECTED_PATH])

    def test_introduction_profile_requires_real_mixed_counts(self) -> None:
        conclusion = {"findingID": "finding", "evidence": {"revisions": [{}, {}],
                     "boundary": {"frontierRevisions": []}}}
        profile = {"reportKind": "swiftdebt-lifecycle-introduction-profile", "schemaVersion": 1,
                   "findingID": "finding", "maximumRevisions": 3, "maximumFileBytes": 1_048_576,
                   "evidenceRevisionCount": 2, "analyzedRevisionCount": 1,
                   "reusedRevisionCount": 1, "frontierRevisionCount": 0,
                   "operationElapsedNanoseconds": 1, "recordingStatus": "already-present"}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "profile.json"
            path.write_text(json.dumps(profile))
            self.assertEqual(introduction_profile(path, conclusion, finding_id="finding",
                                                  maximum_revisions=3,
                                                  maximum_file_bytes=1_048_576)["reusedRevisionCount"], 1)
            profile["reusedRevisionCount"] = 0
            path.write_text(json.dumps(profile))
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                introduction_profile(path, conclusion, finding_id="finding",
                                     maximum_revisions=3, maximum_file_bytes=1_048_576)


if __name__ == "__main__":
    unittest.main()
