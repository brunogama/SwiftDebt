import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

from repository_qualification_cases import (  # noqa: E402
    PATTERNS,
    normalized_rendered_case,
    render_case,
)
from repository_qualification_evaluator import (  # noqa: E402
    DATA_CLUMPS,
    REPEATED_SWITCHES,
    CorpusCase,
    QualificationError,
    _evaluate_cases,
    _validate_manifest,
)


class RepositoryQualificationTests(unittest.TestCase):
    def setUp(self) -> None:
        manifest_path = (
            REPOSITORY_ROOT
            / "Tests/SwiftDebtKitTests/Fixtures/RepositoryQualification/corpus-v1.json"
        )
        self.manifest = json.loads(manifest_path.read_text())

    def test_rendered_variants_are_behaviorally_distinct_after_case_salt_normalization(self) -> None:
        rendered: dict[str, tuple[str, int]] = {}
        for template, patterns in PATTERNS.items():
            for ordinal in range(len(patterns)):
                normalized = normalized_rendered_case(template, ordinal)
                self.assertNotIn(
                    normalized,
                    rendered,
                    f"{rendered.get(normalized)} and {(template, ordinal + 1)} are equivalent",
                )
                rendered[normalized] = (template, ordinal + 1)

    def test_manifest_validation_accepts_true_negatives_and_out_of_scope_cases(self) -> None:
        _validate_manifest(self.manifest)

        counts = {
            identity: {"positive": 0, "negative": 0, "out-of-scope": 0}
            for identity in (DATA_CLUMPS, REPEATED_SWITCHES)
        }
        for shape in self.manifest["repositoryShapes"]:
            for family in shape["families"]:
                counts[family["ruleIdentity"]][family["authorLabel"]] += family["count"]
        self.assertEqual(
            counts[DATA_CLUMPS],
            {"positive": 30, "negative": 60, "out-of-scope": 0},
        )
        self.assertEqual(
            counts[REPEATED_SWITCHES],
            {"positive": 30, "negative": 60, "out-of-scope": 30},
        )

    def test_corrected_and_replacement_cases_are_compile_valid(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc)
        templates = (
            "data-clumps-unnamed-parameters",
            "repeated-switches-case-set-mismatch",
            "repeated-switches-associated-pattern-mismatch",
            "repeated-switches-branch-partition-mismatch",
        )
        rendered_sources = []
        for template in templates:
            for ordinal in range(len(PATTERNS[template])):
                rendered_sources.extend(render_case(template, ordinal).values())

        with tempfile.TemporaryDirectory(prefix="swiftdebt-qualification-typecheck-") as temporary:
            source = Path(temporary) / "CorrectedCases.swift"
            source.write_text("\n".join(rendered_sources))
            result = subprocess.run(
                [swiftc, "-swift-version", "6", "-typecheck", str(source)],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_out_of_scope_cases_cannot_replace_the_negative_threshold(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        family = next(
            family
            for shape in manifest["repositoryShapes"]
            for family in shape["families"]
            if family["id"] == "rs-flat-case-set-mismatch"
        )
        family["authorLabel"] = "out-of-scope"

        with self.assertRaisesRegex(QualificationError, "at least 30 positive and 60 negative"):
            _validate_manifest(manifest)

    def test_rule_identity_is_part_of_the_detection_key(self) -> None:
        cases = [
            self.case("shared-case", DATA_CLUMPS, "positive"),
            self.case("shared-case", REPEATED_SWITCHES, "positive"),
        ]
        detections = {
            (DATA_CLUMPS, "shared-case"): [{"selectorFingerprint": "data"}],
            (REPEATED_SWITCHES, "shared-case"): [{"selectorFingerprint": "switch"}],
        }

        reports = _evaluate_cases(self.manifest, cases, detections, [])

        by_rule = {report["ruleIdentity"]: report for report in reports}
        self.assertEqual(by_rule[DATA_CLUMPS]["provisionalConfusionMatrix"]["truePositive"], 1)
        self.assertEqual(
            by_rule[REPEATED_SWITCHES]["provisionalConfusionMatrix"]["truePositive"], 1
        )
        self.assertEqual(
            by_rule[DATA_CLUMPS]["caseResults"][0]["detections"],
            detections[(DATA_CLUMPS, "shared-case")],
        )
        self.assertEqual(
            by_rule[REPEATED_SWITCHES]["caseResults"][0]["detections"],
            detections[(REPEATED_SWITCHES, "shared-case")],
        )

    def test_out_of_scope_cases_are_published_but_excluded_from_the_matrix(self) -> None:
        cases = [self.case("unsupported-switch", REPEATED_SWITCHES, "out-of-scope")]
        detections = {
            (REPEATED_SWITCHES, "unsupported-switch"): [{"selectorFingerprint": "observed"}]
        }

        reports = _evaluate_cases(self.manifest, cases, detections, [])

        report = next(item for item in reports if item["ruleIdentity"] == REPEATED_SWITCHES)
        self.assertEqual(report["authoredCaseCounts"]["outOfScope"], 1)
        self.assertEqual(report["outOfScopeCaseIDs"], ["unsupported-switch"])
        self.assertEqual(
            report["provisionalMetricsPopulation"],
            "positive-and-adversarial-negative-cases-only",
        )
        self.assertEqual(
            report["provisionalConfusionMatrix"],
            {"truePositive": 0, "falsePositive": 0, "trueNegative": 0, "falseNegative": 0},
        )
        self.assertEqual(
            report["caseResults"][0]["classificationAgainstAuthorLabel"],
            "excluded-out-of-scope",
        )
        self.assertEqual(
            report["caseResults"][0]["provisionalMetricsInclusion"],
            "excluded-out-of-scope",
        )
        self.assertEqual(
            report["caseResults"][0]["detections"],
            detections[(REPEATED_SWITCHES, "unsupported-switch")],
        )

    @staticmethod
    def case(case_id: str, rule_identity: str, author_label: str) -> CorpusCase:
        return CorpusCase(
            case_id=case_id,
            rule_identity=rule_identity,
            author_label=author_label,
            repository_shape="test-shape",
            ambiguity_or_benign_pattern="test pattern",
            rationale="test rationale",
            source_digest="digest",
            source_paths=("Case.swift",),
            source_spans=(("Case.swift", 1, 1),),
        )


if __name__ == "__main__":
    unittest.main()
