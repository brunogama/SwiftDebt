import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from r2_benchmark_cache import (  # noqa: E402
    prepare_repository_seed,
    run_repository_sample,
    validate_cache_sample,
)
from r2_benchmark_cli import (  # noqa: E402
    comparable_cache_report_sha256,
    run_cli_sample,
)
from r2_benchmark_support import (  # noqa: E402
    apply_standard_one_file_edit,
    generate_scale_corpus,
    tree_sha256,
)
from r2_benchmark_test_support import fake_cli_source, stateful_fake_cli_source  # noqa: E402


class R2ReleaseBenchmarkCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(
            (REPOSITORY_ROOT / "benchmarks/r2-release/manifest.v1.json").read_text()
        )

    def test_manifest_pins_cache_head_and_exposes_incremental_states(self):
        sources = self.manifest["sources"]
        self.assertEqual(
            sources["candidateImplementationCommit"],
            "4b9db979e7dc0f870d00f6cae9dcab37528bffb4",
        )
        self.assertEqual(sources["candidateEngineVersion"], "0.10.0")
        observed = {
            (scenario["sourceFileCount"], scenario["cacheState"])
            for scenario in self.manifest["scenarios"]
            if scenario["repositoryEvidence"]
        }
        self.assertEqual(
            observed,
            {
                (source_count, cache_state)
                for source_count in (16, 128, 1_024)
                for cache_state in ("disabled", "cold", "warm", "one-file-edit")
            },
        )
        blocked = {scenario["id"] for scenario in self.manifest["blockedScenarios"]}
        self.assertNotIn("unchanged-warm-cache", blocked)
        self.assertNotIn("standard-one-file-edit", blocked)
        self.assertIn("embedding-incremental-telemetry", blocked)
        sqvector = next(
            scenario
            for scenario in self.manifest["blockedScenarios"]
            if scenario["id"] == "sqvector-exact-index"
        )
        self.assertEqual(
            sqvector["upstreamPin"],
            {
                "url": "https://github.com/brunogama/sqvector-swift.git",
                "revision": "aafd9ae601826112978127c7cb611c94ab8a2e06",
                "product": "SQVectorStatic",
                "module": "SQVector",
            },
        )

    def test_standard_one_file_edit_is_deterministic_and_changes_one_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            generated = generate_scale_corpus(root, 16)
            edit = apply_standard_one_file_edit(root)
            edited = {
                "sourceFileCount": len(list(root.glob("*.swift"))),
                "utf8ByteCount": sum(path.stat().st_size for path in root.glob("*.swift")),
                "snapshotSHA256": tree_sha256(root),
            }
        self.assertEqual(edit["relativePath"], "Scale0000.swift")
        self.assertEqual(edit["changedSourceCount"], 1)
        self.assertEqual(edited["sourceFileCount"], generated["sourceFileCount"])
        self.assertGreater(edited["utf8ByteCount"], generated["utf8ByteCount"])
        self.assertNotEqual(edited["snapshotSHA256"], generated["snapshotSHA256"])

    def test_cache_report_comparison_ignores_only_storage_location(self):
        report = {
            "mode": "reuse",
            "storage": {"location": "/first/cache.json", "byteCount": 42},
        }
        relocated = copy.deepcopy(report)
        relocated["storage"]["location"] = "/second/cache.json"
        changed = copy.deepcopy(report)
        changed["storage"]["byteCount"] = 43
        self.assertEqual(
            comparable_cache_report_sha256(report),
            comparable_cache_report_sha256(relocated),
        )
        self.assertNotEqual(
            comparable_cache_report_sha256(report),
            comparable_cache_report_sha256(changed),
        )

    def test_repository_evidence_rejects_implicit_default_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "corpus"
            corpus.mkdir()
            with self.assertRaisesRegex(RuntimeError, "explicit cache state"):
                run_cli_sample(
                    root / "swift-debt",
                    corpus,
                    root / "output",
                    True,
                )

    def test_repository_process_adapter_controls_every_cache_state(self):
        scenarios = {
            item["cacheState"]: item
            for item in self.manifest["scenarios"]
            if item["repositoryEvidence"] and item["sourceFileCount"] == 16
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "corpus"
            generate_scale_corpus(corpus, 16)
            fake = root / "stateful-swift-debt"
            fake.write_text(
                stateful_fake_cli_source(
                    scenarios["disabled"],
                    self.manifest["repositoryConfiguration"],
                    self.manifest["repositoryCacheCompatibility"],
                ),
                encoding="utf-8",
            )
            fake.chmod(0o755)

            samples = {
                state: run_repository_sample(
                    fake,
                    corpus,
                    root / f"sample-{state}",
                    scenario,
                    self.manifest["repositoryConfiguration"],
                    self.manifest["providerIdentities"]["repositorySyntax"],
                    self.manifest["repositoryRules"],
                    self.manifest["repositoryCacheCompatibility"],
                )
                for state, scenario in scenarios.items()
            }
            prepared_seed = prepare_repository_seed(
                fake,
                corpus,
                root / "prepared-seed",
                scenarios["warm"],
                self.manifest["repositoryConfiguration"],
                self.manifest["providerIdentities"]["repositorySyntax"],
                self.manifest["repositoryRules"],
                self.manifest["repositoryCacheCompatibility"],
            )
            prepared_warm = run_repository_sample(
                fake,
                corpus,
                root / "prepared-warm",
                scenarios["warm"],
                self.manifest["repositoryConfiguration"],
                self.manifest["providerIdentities"]["repositorySyntax"],
                self.manifest["repositoryRules"],
                self.manifest["repositoryCacheCompatibility"],
                prepared_seed,
            )

        self.assertIsNone(samples["disabled"]["cacheStoreSHA256After"])
        self.assertIsNotNone(samples["cold"]["cacheStoreSHA256After"])
        self.assertEqual(
            samples["warm"]["cacheStoreSHA256Before"],
            samples["warm"]["cacheStoreSHA256After"],
        )
        self.assertNotEqual(
            samples["one-file-edit"]["cacheStoreSHA256Before"],
            samples["one-file-edit"]["cacheStoreSHA256After"],
        )
        self.assertEqual(
            samples["warm"]["cacheSetup"]["cacheStoreSHA256After"],
            samples["warm"]["cacheStoreSHA256Before"],
        )
        self.assertEqual(
            samples["one-file-edit"]["cacheSetup"]["cacheStoreSHA256After"],
            samples["one-file-edit"]["cacheStoreSHA256Before"],
        )
        self.assertEqual(
            prepared_warm["cacheSetup"]["preparation"], "copied-scenario-seed"
        )
        self.assertEqual(
            prepared_warm["cacheSetup"]["cacheStoreSHA256After"],
            prepared_warm["cacheStoreSHA256Before"],
        )
        self.assertFalse(
            any(path.startswith("seed/") for path in prepared_warm["controlledStateFiles"])
        )

        mismatched_identity = copy.deepcopy(samples["cold"])
        mismatched_identity["repositoryCacheActivity"]["sourceSnapshotDigest"][
            "value"
        ] = "f" * 64
        with self.assertRaisesRegex(RuntimeError, "different source snapshots"):
            validate_cache_sample(
                mismatched_identity,
                scenarios["cold"],
                self.manifest["repositoryConfiguration"],
                self.manifest["providerIdentities"]["repositorySyntax"],
                self.manifest["repositoryRules"],
                self.manifest["repositoryCacheCompatibility"],
            )

        mismatched_storage = copy.deepcopy(samples["cold"])
        mismatched_storage["repositoryCacheActivity"]["storage"]["dataClasses"] = []
        with self.assertRaisesRegex(RuntimeError, "storage provenance mismatch"):
            validate_cache_sample(
                mismatched_storage,
                scenarios["cold"],
                self.manifest["repositoryConfiguration"],
                self.manifest["providerIdentities"]["repositorySyntax"],
                self.manifest["repositoryRules"],
                self.manifest["repositoryCacheCompatibility"],
            )

    def test_repository_sample_rejects_unexpected_controlled_state_file(self):
        scenario = next(
            item
            for item in self.manifest["scenarios"]
            if item["id"] == "repository-evidence-cold-cache-scale-16"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "corpus"
            generate_scale_corpus(corpus, 16)
            fake = root / "stateful-swift-debt"
            source = stateful_fake_cli_source(
                scenario,
                self.manifest["repositoryConfiguration"],
                self.manifest["repositoryCacheCompatibility"],
            ).replace(
                'cache_path = value("--repository-cache") if "--repository-cache" in arguments else None',
                'cache_path = value("--repository-cache") if "--repository-cache" in arguments else None\n'
                '(cache_path.parent / "unexpected.index").write_text("unexpected")',
            )
            fake.write_text(source, encoding="utf-8")
            fake.chmod(0o755)

            with self.assertRaisesRegex(RuntimeError, "controlled state mismatch"):
                run_repository_sample(
                    fake,
                    corpus,
                    root / "sample",
                    scenario,
                    self.manifest["repositoryConfiguration"],
                    self.manifest["providerIdentities"]["repositorySyntax"],
                    self.manifest["repositoryRules"],
                    self.manifest["repositoryCacheCompatibility"],
                )

    def test_process_adapter_rejects_noncanonical_invalidation_order(self):
        scenario = copy.deepcopy(
            next(
                item
                for item in self.manifest["scenarios"]
                if item["id"] == "repository-evidence-cache-disabled-scale-16"
            )
        )
        scenario["expectedCacheActivity"]["invalidations"] = {
            "z-last": 1,
            "a-first": 1,
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "corpus"
            corpus.mkdir()
            fake = root / "noncanonical-swift-debt"
            fake.write_text(
                fake_cli_source(
                    scenario,
                    self.manifest["repositoryConfiguration"],
                    self.manifest["repositoryCacheCompatibility"],
                ),
                encoding="utf-8",
            )
            fake.chmod(0o755)

            with self.assertRaisesRegex(RuntimeError, "unique and canonical"):
                run_cli_sample(
                    fake,
                    corpus,
                    root / "sample",
                    True,
                    cache_state="disabled",
                )


if __name__ == "__main__":
    unittest.main()
