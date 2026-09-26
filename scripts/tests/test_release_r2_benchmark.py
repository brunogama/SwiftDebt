import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from r2_benchmark_support import (  # noqa: E402
    generate_exhaustion_corpus,
    generate_scale_corpus,
    median_absolute_deviation,
    paired_roles,
    percentile,
    short_stage_gate,
    tree_sha256,
)
from r2_benchmark_cli import (  # noqa: E402
    comparable_report_sha256,
    run_cli_sample,
    validate_sample,
)
from r2_benchmark_scenarios import limits_and_proof  # noqa: E402
from run_r2_release_benchmarks import (  # noqa: E402
    evidence,
    validate_distinct_binaries,
    validate_manifest,
)


class R2ReleaseBenchmarkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(
            (REPOSITORY_ROOT / "benchmarks/r2-release/manifest.v1.json").read_text()
        )

    def test_reference_and_candidate_paths_must_be_distinct(self):
        binary = Path("/tmp/swift-debt")
        with self.assertRaisesRegex(RuntimeError, "must be distinct"):
            validate_distinct_binaries(binary, binary)

    def test_manifest_requires_release_sized_sampling_and_explicit_blockers(self):
        validate_manifest(self.manifest)
        too_short = copy.deepcopy(self.manifest)
        too_short["measurement"]["measuredRuns"] = 29
        with self.assertRaisesRegex(RuntimeError, "at least 5 warmups and 30 measured"):
            validate_manifest(too_short)
        hidden_blockers = copy.deepcopy(self.manifest)
        hidden_blockers["blockedScenarios"] = []
        with self.assertRaisesRegex(RuntimeError, "must remain explicit"):
            validate_manifest(hidden_blockers)
        ambiguous_comparison = copy.deepcopy(self.manifest)
        ambiguous_comparison["measurement"].pop("crossVersionReportComparison")
        with self.assertRaisesRegex(RuntimeError, "comparison must remain explicit"):
            validate_manifest(ambiguous_comparison)
        mismatched_build = copy.deepcopy(self.manifest)
        mismatched_build["binaryBuildProtocol"]["appliesTo"] = ["candidate"]
        with self.assertRaisesRegex(RuntimeError, "share the frozen build protocol"):
            validate_manifest(mismatched_build)
        unbounded_load = copy.deepcopy(self.manifest)
        unbounded_load["budgetPolicy"]["maximumObservedOneMinuteLoad"] = 22.0
        with self.assertRaisesRegex(RuntimeError, "1.5 times"):
            validate_manifest(unbounded_load)

    def test_generated_scale_snapshots_and_analysis_unit_counts_are_frozen(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            unique_scales = {
                scenario["sourceFileCount"]: scenario
                for scenario in self.manifest["scenarios"]
            }
            for source_files, scenario in unique_scales.items():
                generated = generate_scale_corpus(
                    root / str(source_files), source_files
                )
                self.assertEqual(
                    generated["snapshotSHA256"], scenario["snapshotSHA256"]
                )
                self.assertEqual(generated["utf8ByteCount"], scenario["utf8ByteCount"])
                self.assertEqual(
                    generated["analysisUnitCounts"], scenario["analysisUnitCounts"]
                )
                self.assertEqual(
                    generated["expectedDetectionCounts"],
                    scenario["expectedDetectionCounts"],
                )

    def test_exhaustion_snapshot_is_frozen(self):
        expected = self.manifest["exhaustionScenario"]
        with tempfile.TemporaryDirectory() as temporary:
            generated = generate_exhaustion_corpus(
                Path(temporary), expected["analysisUnitCounts"]["dataClumpUnits"]
            )
        self.assertEqual(generated["snapshotSHA256"], expected["snapshotSHA256"])
        self.assertEqual(generated["utf8ByteCount"], expected["utf8ByteCount"])
        self.assertEqual(
            generated["analysisUnitCounts"], expected["analysisUnitCounts"]
        )

    def test_nearest_rank_and_median_absolute_deviation_are_explicit(self):
        values = list(range(1, 31))
        self.assertEqual(percentile(values, 0.95), 29)
        self.assertEqual(median_absolute_deviation([1, 2, 3, 100]), 1)

    def test_short_stage_requires_both_relative_and_absolute_breaches(self):
        noisy_small_delta = short_stage_gate(20, 23, 10, 10)
        material_regression = short_stage_gate(20, 40, 10, 10)
        long_regression = short_stage_gate(1_000, 1_101, 10, 500)
        self.assertEqual(noisy_small_delta["verdict"], "pass")
        self.assertTrue(noisy_small_delta["relativeLimitBreached"])
        self.assertFalse(noisy_small_delta["absoluteFloorBreached"])
        self.assertEqual(material_regression["verdict"], "fail")
        self.assertEqual(long_regression["verdict"], "fail")

    def test_induced_double_analysis_must_trip_the_calibrated_wall_gate(self):
        aggregate = {
            "wallClockMilliseconds": {"median": 20.0, "p95": 20.0},
            "peakResidentMemoryBytes": {"median": 100.0, "p95": 100.0},
        }
        raw = [
            {"wallClockMilliseconds": value, "hostLoadAverage": self._host_load()}
            for value in [19.0, 20.0, 21.0, 20.0, 19.5]
        ]
        induced = [
            {
                "wallClockMilliseconds": value,
                "componentHostLoadAverage": [self._host_load(), self._host_load()],
            }
            for value in [41.0, 42.0, 40.0, 43.0, 41.5]
        ]
        result = limits_and_proof(
            aggregate,
            aggregate,
            raw,
            raw,
            induced,
            self.manifest["budgetPolicy"],
            False,
        )
        self.assertEqual(result["wallClock"]["verdict"], "pass")
        self.assertEqual(
            result["noiseFloorCalibration"]["sampleBasis"],
            "calibration wall-clock samples",
        )
        self.assertEqual(
            result["noiseFloorCalibration"]["appliedFloorMilliseconds"], 10.0
        )
        self.assertEqual(
            result["inducedRegressionProof"]["evaluation"]["verdict"], "fail"
        )
        self.assertEqual(result["inducedRegressionProof"]["verdict"], "pass")
        self.assertEqual(result["hostLoad"]["verdict"], "pass")

        raw[0]["hostLoadAverage"] = self._host_load(one_minute=22.0)
        overloaded = limits_and_proof(
            aggregate,
            aggregate,
            raw,
            raw,
            induced,
            self.manifest["budgetPolicy"],
            False,
        )
        self.assertEqual(overloaded["hostLoad"]["verdict"], "fail")

    def test_paired_order_alternates_and_preserves_pair_indices(self):
        observed = [paired_roles(index) for index in range(4)]
        self.assertEqual(
            observed,
            [
                ["reference", "candidate"],
                ["candidate", "reference"],
                ["reference", "candidate"],
                ["candidate", "reference"],
            ],
        )

    def test_cross_version_report_projection_excludes_only_engine_version(self):
        reference = {
            "schemaVersion": 2,
            "engineVersion": "0.8.1",
            "inputFileCount": 16,
        }
        candidate = {**reference, "engineVersion": "0.9.0"}
        changed_behavior = {**candidate, "inputFileCount": 17}
        self.assertEqual(
            comparable_report_sha256(reference),
            comparable_report_sha256(candidate),
        )
        self.assertNotEqual(
            comparable_report_sha256(reference),
            comparable_report_sha256(changed_behavior),
        )

    def test_evidence_records_and_rejects_binary_engine_version_mismatch(self):
        scenarios = [
            {
                "outputValidation": {
                    "referenceEngineVersions": ["0.8.0"],
                    "candidateEngineVersions": ["0.9.0"],
                }
            }
        ]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
            reference = root / "reference"
            candidate = root / "candidate"
            reference.write_bytes(b"reference")
            candidate.write_bytes(b"candidate")
            result = evidence(
                self.manifest,
                manifest_path,
                {},
                reference,
                candidate,
                scenarios,
                {},
                True,
            )
            self.assertEqual(result["binaries"]["reference"]["engineVersion"], "0.8.0")
            self.assertEqual(result["binaries"]["candidate"]["engineVersion"], "0.9.0")
            scenarios[0]["outputValidation"]["candidateEngineVersions"] = ["0.9.1"]
            with self.assertRaisesRegex(RuntimeError, "engine version mismatch"):
                evidence(
                    self.manifest,
                    manifest_path,
                    {},
                    reference,
                    candidate,
                    scenarios,
                    {},
                    True,
                )

    def test_real_process_adapter_records_profile_and_validates_sidecar(self):
        scenario = next(
            item
            for item in self.manifest["scenarios"]
            if item["id"] == "repository-evidence-scale-16"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake = root / "fake-swift-debt"
            fake.write_text(
                self._fake_cli_source(
                    scenario, self.manifest["repositoryConfiguration"]
                ),
                encoding="utf-8",
            )
            fake.chmod(0o755)
            corpus = root / "corpus"
            corpus.mkdir()
            scenario = dict(scenario)
            scenario["snapshotSHA256"] = tree_sha256(corpus)
            sample = run_cli_sample(fake, corpus, root / "output", True)
        validate_sample(
            sample,
            scenario,
            self.manifest["repositoryConfiguration"],
            self.manifest["providerIdentities"]["repositorySyntax"],
            self.manifest["repositoryRules"],
        )
        wrong_provider = copy.deepcopy(sample)
        wrong_provider["repositoryEvidence"]["providers"] = [("SwiftSyntax", "unknown")]
        with self.assertRaisesRegex(RuntimeError, "unexpected repository provider"):
            validate_sample(
                wrong_provider,
                scenario,
                self.manifest["repositoryConfiguration"],
                self.manifest["providerIdentities"]["repositorySyntax"],
                self.manifest["repositoryRules"],
            )
        wrong_revision = copy.deepcopy(sample)
        wrong_revision["repositoryEvidence"]["ruleSemanticRevisions"][
            "swiftdebt.refactoring.data-clumps"
        ] = 999
        with self.assertRaisesRegex(RuntimeError, "unexpected rule semantic revisions"):
            validate_sample(
                wrong_revision,
                scenario,
                self.manifest["repositoryConfiguration"],
                self.manifest["providerIdentities"]["repositorySyntax"],
                self.manifest["repositoryRules"],
            )
        self.assertEqual(sample["exitStatus"], 0)
        self.assertGreater(sample["peakResidentMemoryBytes"], 0)
        self.assertEqual(sample["reportEngineVersion"], "unavailable")
        self.assertEqual(sample["phaseWallClockNanoseconds"], {"discovery": 100})
        self.assertEqual(sample["unexpectedFiles"], [])
        self.assertEqual(
            sample["createdFiles"],
            ["analysis.json", "profile.json", "repository-evidence.json"],
        )

    def test_process_adapter_rejects_source_corpus_mutation(self):
        scenario = next(
            item
            for item in self.manifest["scenarios"]
            if item["id"] == "repository-evidence-scale-16"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "corpus"
            corpus.mkdir()
            fake = root / "mutating-swift-debt"
            source = self._fake_cli_source(
                scenario, self.manifest["repositoryConfiguration"]
            )
            source = source.replace(
                "arguments = sys.argv[1:]",
                'arguments = sys.argv[1:]\n(Path(arguments[1]) / "unexpected.index").write_text("mutated")',
            )
            fake.write_text(source, encoding="utf-8")
            fake.chmod(0o755)
            with self.assertRaisesRegex(
                RuntimeError, "modified its frozen source corpus"
            ):
                run_cli_sample(fake, corpus, root / "output", True)

    @staticmethod
    def _host_load(one_minute=5.0):
        return {
            "before": {
                "oneMinute": one_minute,
                "fiveMinutes": one_minute,
                "fifteenMinutes": one_minute,
            },
            "after": {
                "oneMinute": one_minute,
                "fiveMinutes": one_minute,
                "fifteenMinutes": one_minute,
            },
        }

    @staticmethod
    def _fake_cli_source(scenario, configuration):
        detections = scenario["expectedDetectionCounts"]
        rules = [
            {
                "ruleIdentity": identity,
                "completionState": "complete",
                "semanticRevision": 2,
                "detections": [{} for _ in range(count)],
                "issues": [],
                "capabilities": [
                    {"provider": {"name": "SwiftSyntax", "version": "602.0.0"}}
                ],
            }
            for identity, count in detections.items()
        ]
        sidecar = {
            "summary": {
                "sourceFileCount": scenario["sourceFileCount"],
                "detectionCount": sum(detections.values()),
                "completeRuleCount": len(rules),
                "incompleteRuleCount": 0,
            },
            "rules": rules,
            "snapshot": {
                "contentDigest": {"algorithm": "sha256", "value": "0" * 64},
                "configuration": configuration,
            },
        }
        return f"""#!/usr/bin/env python3
import json
import sys
from pathlib import Path
arguments = sys.argv[1:]
def value(option):
    return Path(arguments[arguments.index(option) + 1])
report = value("--output")
profile = value("--profile-output")
sidecar = value("--repository-evidence")
for path in (report, profile, sidecar):
    path.parent.mkdir(parents=True, exist_ok=True)
report.write_text('{{"schemaVersion":2}}\\n')
profile.write_text(json.dumps({{"phases":[{{"phase":"discovery","elapsedNanoseconds":100}}]}}))
sidecar.write_text(json.dumps({json.dumps(sidecar)}))
"""


if __name__ == "__main__":
    unittest.main()
