import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from r2_benchmark_support import (  # noqa: E402
    atomic_json,
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
from r2_benchmark_scenarios import (  # noqa: E402
    limits_and_proof,
    validate_exhaustion_sample,
)
from r2_benchmark_test_support import fake_cli_source  # noqa: E402
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
        premature_support = copy.deepcopy(self.manifest)
        premature_support["repositoryRules"]["swiftdebt.refactoring.data-clumps"][
            "qualification"
        ] = "Supported"
        with self.assertRaisesRegex(RuntimeError, "must remain Research"):
            validate_manifest(premature_support)
        hidden_index_blocker = copy.deepcopy(self.manifest)
        hidden_index_blocker["blockedScenarios"] = [
            scenario
            for scenario in hidden_index_blocker["blockedScenarios"]
            if scenario["id"] != "sqvector-exact-index"
        ]
        with self.assertRaisesRegex(RuntimeError, "must remain blocked"):
            validate_manifest(hidden_index_blocker)
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
        corrupted_activity = copy.deepcopy(self.manifest)
        repository_scenario = next(
            scenario
            for scenario in corrupted_activity["scenarios"]
            if scenario["cacheState"] == "warm"
        )
        repository_scenario["expectedCacheActivity"]["reusedSourceCount"] -= 1
        with self.assertRaisesRegex(RuntimeError, "exact cache activity"):
            validate_manifest(corrupted_activity)

    def test_manifest_rejects_statistical_and_budget_policy_drift(self):
        wrong_percentile = copy.deepcopy(self.manifest)
        wrong_percentile["measurement"]["percentileMethod"] = "linear-interpolation"
        with self.assertRaisesRegex(RuntimeError, "nearest-rank"):
            validate_manifest(wrong_percentile)

        candidate_derived_floor = copy.deepcopy(self.manifest)
        candidate_derived_floor["measurement"]["noiseFloorSource"] = (
            "paired candidate-minus-reference deltas"
        )
        with self.assertRaisesRegex(RuntimeError, "must remain independent"):
            validate_manifest(candidate_derived_floor)

        relaxed_wall_limit = copy.deepcopy(self.manifest)
        relaxed_wall_limit["budgetPolicy"]["maximumWallClockRegressionPercent"] = 100.0
        with self.assertRaisesRegex(RuntimeError, "frozen limits"):
            validate_manifest(relaxed_wall_limit)

        relaxed_memory_allowance = copy.deepcopy(self.manifest)
        relaxed_memory_allowance["budgetPolicy"]["maximumPeakMemoryRegressionBytes"] += 1
        with self.assertRaisesRegex(RuntimeError, "frozen limits"):
            validate_manifest(relaxed_memory_allowance)

        changed_data_classes = copy.deepcopy(self.manifest)
        changed_data_classes["repositoryCacheDataClasses"].append("unreviewed-facts")
        with self.assertRaisesRegex(RuntimeError, "data classes changed"):
            validate_manifest(changed_data_classes)

    def test_manifest_requires_exactly_one_scenario_per_frozen_coordinate(self):
        duplicate_repository_state = copy.deepcopy(self.manifest)
        duplicate = copy.deepcopy(
            next(
                scenario
                for scenario in duplicate_repository_state["scenarios"]
                if scenario["id"] == "repository-evidence-warm-cache-scale-16"
            )
        )
        duplicate["id"] += "-duplicate"
        duplicate_repository_state["scenarios"].append(duplicate)
        with self.assertRaisesRegex(RuntimeError, "exactly one sample"):
            validate_manifest(duplicate_repository_state)

        missing_paired_scale = copy.deepcopy(self.manifest)
        missing_paired_scale["scenarios"] = [
            scenario
            for scenario in missing_paired_scale["scenarios"]
            if scenario["id"] != "similarity-disabled-scale-1024"
        ]
        with self.assertRaisesRegex(RuntimeError, "exactly one paired sample"):
            validate_manifest(missing_paired_scale)

    def test_historical_invalid_artifact_identity_remains_frozen(self):
        artifact_path = (
            REPOSITORY_ROOT
            / "benchmarks/r2-release/evidence/2026-09-25-m4-max/moderate-load-invalid.v1.json"
        )
        data = artifact_path.read_bytes()
        artifact = json.loads(data)

        self.assertEqual(
            hashlib.sha256(data).hexdigest(),
            "987449981a9852f2a480606291d277e24e49dee7e847fb46732ab6b824206cd1",
        )
        self.assertEqual(
            artifact["manifestSHA256"],
            "7622d7ae5ea95a7aa9af41f4b3d517b0eba1c8c624cc74d4b2b770541f30ef24",
        )

    def test_atomic_artifact_write_never_exposes_partial_final_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "calibration.json"
            with patch(
                "r2_benchmark_support.os.replace",
                side_effect=OSError("interrupted before rename"),
            ):
                with self.assertRaisesRegex(OSError, "interrupted before rename"):
                    atomic_json(output, {"calibrationState": "measured-pass"})

            self.assertFalse(output.exists())
            self.assertTrue(output.with_name("calibration.json.tmp").is_file())

            output.with_name("calibration.json.tmp").unlink()
            with self.assertRaisesRegex(ValueError, "Out of range float values"):
                atomic_json(output, {"nonFiniteMeasurement": float("inf")})
            self.assertFalse(output.exists())
            self.assertFalse(output.with_name("calibration.json.tmp").exists())

    def test_generated_scale_snapshots_and_analysis_unit_counts_are_frozen(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            unique_scales = {
                scenario["sourceFileCount"]: scenario
                for scenario in self.manifest["scenarios"]
                if scenario["cacheState"] == "not-applicable"
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

    def test_exhaustion_proof_requires_exact_incomplete_evidence(self):
        scenario = self.manifest["exhaustionScenario"]
        digest = {"algorithm": "sha256", "value": "0" * 64}
        provider = ("SwiftSyntax", "602.0.0")
        identities = sorted(self.manifest["repositoryRules"])
        sample = {
            "exitStatus": 2,
            "unexpectedFiles": [],
            "sourceSnapshotSHA256": scenario["snapshotSHA256"],
            "repositoryEvidence": {
                "sourceFileCount": 1,
                "detectionCount": 0,
                "completeRuleCount": 1,
                "incompleteRuleCount": 1,
                "issueCodes": ["comparison-budget-exceeded"],
                "snapshotContentDigest": digest,
                "configuration": self.manifest["repositoryConfiguration"],
                "ruleDetectionCounts": {identity: 0 for identity in identities},
                "ruleSemanticRevisions": {
                    identity: self.manifest["repositoryRules"][identity][
                        "semanticRevision"
                    ]
                    for identity in identities
                },
                "ruleCompletionStates": {
                    "swiftdebt.refactoring.data-clumps": "incomplete",
                    "swiftdebt.refactoring.repeated-switches": "complete",
                },
                "providers": [provider],
                "ruleProviders": {identity: [provider] for identity in identities},
            },
            "repositoryCacheActivity": {
                "reportKind": "swiftdebt-repository-syntax-cache",
                "schemaVersion": 1,
                "sourceSnapshotDigest": digest,
                "mode": "disabled",
                "disposition": "disabled",
                "compatibility": self.manifest["repositoryCacheCompatibility"],
                "storage": {
                    "location": None,
                    "dataClasses": [],
                    "byteCount": 0,
                    "contentDigest": None,
                    "writePerformed": False,
                },
                "selectedSourceCount": 1,
                "reusedSourceCount": 0,
                "recomputedSourceCount": 1,
                "removedSourceCount": 0,
                "invalidations": {"cache-disabled": 1},
                "networkRequestCount": 0,
            },
        }
        generated = {"snapshotSHA256": scenario["snapshotSHA256"]}
        validate_exhaustion_sample(self.manifest, sample, generated)

        corrupted = copy.deepcopy(sample)
        corrupted["repositoryEvidence"]["issueCodes"].append("parse-failed")
        with self.assertRaisesRegex(RuntimeError, "exact incomplete result"):
            validate_exhaustion_sample(self.manifest, corrupted, generated)

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

    def test_candidate_variance_cannot_widen_paired_noise_floor(self):
        baseline = {
            "wallClockMilliseconds": {"median": 100.0, "p95": 100.0},
            "peakResidentMemoryBytes": {"median": 1_000_000.0, "p95": 1_000_000.0},
        }
        candidate = {
            "wallClockMilliseconds": {"median": 150.0, "p95": 200.0},
            "peakResidentMemoryBytes": {"median": 1_000_000.0, "p95": 1_000_000.0},
        }
        reference_samples = [
            {"wallClockMilliseconds": 100.0, "hostLoadAverage": self._host_load()}
            for _ in range(30)
        ]
        candidate_samples = [
            {"wallClockMilliseconds": value, "hostLoadAverage": self._host_load()}
            for value in ([100.0] * 15 + [200.0] * 15)
        ]
        induced = [
            {
                "wallClockMilliseconds": 400.0,
                "componentHostLoadAverage": [self._host_load(), self._host_load()],
            }
            for _ in range(5)
        ]

        result = limits_and_proof(
            baseline,
            candidate,
            reference_samples,
            candidate_samples,
            induced,
            self.manifest["budgetPolicy"],
            True,
        )

        self.assertEqual(
            result["noiseFloorCalibration"]["sampleBasis"],
            "reference-only wall-clock samples",
        )
        self.assertEqual(
            result["noiseFloorCalibration"]["medianAbsoluteDeviationMilliseconds"],
            0.0,
        )
        self.assertEqual(
            result["noiseFloorCalibration"]["appliedFloorMilliseconds"], 10.0
        )
        self.assertEqual(result["wallClock"]["relativeRegressionPercent"], 100.0)
        self.assertEqual(result["wallClock"]["verdict"], "fail")
        self.assertEqual(result["inducedRegressionProof"]["verdict"], "pass")

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
                    "candidateEngineVersions": ["0.10.0"],
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
            self.assertEqual(result["binaries"]["candidate"]["engineVersion"], "0.10.0")
            scenarios[0]["outputValidation"]["candidateEngineVersions"] = ["0.10.1"]
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
            if item["id"] == "repository-evidence-cache-disabled-scale-16"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake = root / "fake-swift-debt"
            fake.write_text(
                fake_cli_source(
                    scenario,
                    self.manifest["repositoryConfiguration"],
                    self.manifest["repositoryCacheCompatibility"],
                ),
                encoding="utf-8",
            )
            fake.chmod(0o755)
            corpus = root / "corpus"
            corpus.mkdir()
            scenario = dict(scenario)
            scenario["snapshotSHA256"] = tree_sha256(corpus)
            sample = run_cli_sample(
                fake, corpus, root / "output", True, cache_state="disabled"
            )
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
            [
                "analysis.json",
                "profile.json",
                "repository-cache-report.json",
                "repository-evidence.json",
            ],
        )

    def test_process_adapter_rejects_source_corpus_mutation(self):
        scenario = next(
            item
            for item in self.manifest["scenarios"]
            if item["id"] == "repository-evidence-cache-disabled-scale-16"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "corpus"
            corpus.mkdir()
            fake = root / "mutating-swift-debt"
            source = fake_cli_source(
                scenario,
                self.manifest["repositoryConfiguration"],
                self.manifest["repositoryCacheCompatibility"],
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
                run_cli_sample(
                    fake, corpus, root / "output", True, cache_state="disabled"
                )

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

if __name__ == "__main__":
    unittest.main()
