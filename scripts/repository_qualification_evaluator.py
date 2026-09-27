"""Evaluation engine for the frozen repository rule qualification corpus."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from repository_qualification_cases import (
    PATTERNS,
    case_pattern,
    normalized_rendered_case,
    render_case,
)


DATA_CLUMPS = "swiftdebt.refactoring.data-clumps"
REPEATED_SWITCHES = "swiftdebt.refactoring.repeated-switches"
RULE_IDENTITIES = (DATA_CLUMPS, REPEATED_SWITCHES)


class QualificationError(RuntimeError):
    pass


@dataclass(frozen=True)
class CorpusCase:
    case_id: str
    rule_identity: str
    author_label: str
    repository_shape: str
    ambiguity_or_benign_pattern: str
    rationale: str
    source_digest: str
    source_paths: tuple[str, ...]
    source_spans: tuple[tuple[str, int, int], ...]


@dataclass
class MaterializedShape:
    definition: dict[str, Any]
    root: Path
    cli_input: list[str]
    cases: list[CorpusCase]
    source_to_case: dict[str, str]


def evaluate(
    manifest_path: Path,
    swift_debt: Path,
    working_root: Path,
    determinism_runs: int,
    parse_jobs: list[int],
    verify_network_denied: bool,
) -> dict[str, Any]:
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    _validate_manifest(manifest)
    swift_debt = swift_debt.resolve()
    if not swift_debt.is_file() or not os.access(swift_debt, os.X_OK):
        raise QualificationError(f"swift-debt executable is unavailable: {swift_debt}")

    fixture_root = manifest_path.parent
    synthetic_root = working_root / "synthetic"
    sidecar_root = working_root / "sidecars"
    synthetic_root.mkdir(parents=True)
    sidecar_root.mkdir(parents=True)

    all_cases: list[CorpusCase] = []
    shape_reports: list[dict[str, Any]] = []
    materialized_shapes: list[MaterializedShape] = []
    detections_by_case: dict[tuple[str, str], list[dict[str, Any]]] = {}
    evaluation_issues: list[str] = []

    for shape_definition in manifest["repositoryShapes"]:
        shape = _materialize_shape(shape_definition, synthetic_root)
        materialized_shapes.append(shape)
        all_cases.extend(shape.cases)
        sidecar = sidecar_root / f"{shape.definition['id']}.json"
        report, _ = _run_cli(swift_debt, shape.cli_input, sidecar, jobs=1)
        rule_map = {rule["ruleIdentity"]: rule for rule in report["rules"]}
        for identity in RULE_IDENTITIES:
            rule = rule_map.get(identity)
            if rule is None:
                evaluation_issues.append(f"{shape.definition['id']}: missing rule {identity}")
                continue
            if rule["completionState"] != "complete":
                evaluation_issues.append(f"{shape.definition['id']}: incomplete rule {identity}")
            for detection in rule["detections"]:
                case_ids = _detection_case_ids(detection, shape.source_to_case)
                if not case_ids:
                    evaluation_issues.append(
                        f"{shape.definition['id']}: {identity} detection has no corpus case location"
                    )
                if len(case_ids) > 1:
                    evaluation_issues.append(
                        f"{shape.definition['id']}: {identity} detection crosses cases {sorted(case_ids)}"
                    )
                for case_id in case_ids:
                    detections_by_case.setdefault((identity, case_id), []).append(
                        _published_detection(detection)
                    )
        shape_reports.append(
            {
                "id": shape.definition["id"],
                "layout": shape.definition["layout"],
                "description": shape.definition["description"],
                "analyzerGenerator": report["generator"],
                "caseCount": len(shape.cases),
                "sourceFileCount": report["summary"]["sourceFileCount"],
                "sourceTreeDigest": _tree_digest(shape.root),
                "repositorySnapshotDigest": report["snapshot"]["contentDigest"],
                "ruleCompletion": {
                    identity: rule_map[identity]["completionState"] for identity in RULE_IDENTITIES
                },
            }
        )

    rule_reports = _evaluate_cases(manifest, all_cases, detections_by_case, evaluation_issues)
    snapshot_reports = [
        _evaluate_snapshot(swift_debt, fixture_root, definition, sidecar_root)
        for definition in manifest["realWorldSnapshots"]
    ]

    determinism = {"status": "not-run", "requiredRunsPerJobCount": 10}
    network_isolation = {"status": "not-run"}
    if determinism_runs:
        flat = next(shape for shape in materialized_shapes if shape.definition["layout"] == "flat")
        determinism, baseline = _verify_determinism(
            swift_debt, flat.root, sidecar_root, determinism_runs, parse_jobs
        )
        if verify_network_denied:
            network_isolation = _verify_network_isolation(
                swift_debt, flat.root, sidecar_root, baseline
            )
    elif verify_network_denied:
        raise QualificationError("network isolation verification requires determinism runs")

    engineering_passed = not evaluation_issues and all(
        rule["engineeringThresholds"]["status"] == "pass" for rule in rule_reports
    )
    if determinism_runs:
        engineering_passed = engineering_passed and determinism["status"] == "pass"
    if verify_network_denied:
        engineering_passed = engineering_passed and network_isolation["status"] == "pass"

    return {
        "schemaVersion": 1,
        "reportKind": "swiftdebt-repository-rule-qualification",
        "corpus": {
            "id": manifest["corpusID"],
            "manifestDigest": _digest(manifest_bytes),
            "authorLabelState": manifest["authorLabelState"],
            "review": manifest["review"],
        },
        "qualificationState": "blocked-pending-independent-review",
        "gate": {
            "syntheticEngineeringEvidence": "pass" if engineering_passed else "fail",
            "releaseQualification": "blocked",
            "blockingReasons": [
                "Two qualified Swift reviewers have not independently adjudicated the labels.",
                "Research support state remains required until every R2 release gate passes.",
            ],
            "evaluationIssues": sorted(evaluation_issues),
        },
        "rules": rule_reports,
        "repositoryShapes": shape_reports,
        "realWorldSnapshots": snapshot_reports,
        "determinism": determinism,
        "networkIsolation": network_isolation,
    }


def canonical_json(report: dict[str, Any]) -> bytes:
    return (json.dumps(report, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode()


def _validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("schemaVersion") != 1:
        raise QualificationError("corpus schemaVersion must be 1")
    if manifest.get("authorLabelState") != "provisional-pending-independent-review":
        raise QualificationError("corpus labels must remain pending independent review")
    review = manifest.get("review", {})
    slots = review.get("reviewerSlots", [])
    if review.get("requiredQualifiedSwiftReviewers") != 2 or len(slots) != 2:
        raise QualificationError("corpus must reserve exactly two qualified reviewer slots")
    if any(slot.get("status") != "pending" for slot in slots):
        raise QualificationError("reviewer slots must stay pending until real reviews are recorded")
    if review.get("adjudicationStatus") != "pending":
        raise QualificationError("adjudication must stay pending")
    rule_revisions = {rule["identity"]: rule["semanticRevision"] for rule in manifest["rules"]}
    if rule_revisions != {DATA_CLUMPS: 2, REPEATED_SWITCHES: 2}:
        raise QualificationError("corpus rule identities and semantic revisions are not frozen")
    seen_families: set[str] = set()
    seen_rendered_sources: dict[str, str] = {}
    counts = {
        identity: {"positive": 0, "negative": 0, "out-of-scope": 0}
        for identity in RULE_IDENTITIES
    }
    shape_counts = {identity: set() for identity in RULE_IDENTITIES}
    for shape in manifest["repositoryShapes"]:
        if shape["layout"] not in {"flat", "nested", "manifest"}:
            raise QualificationError(f"unknown repository layout: {shape['layout']}")
        for family in shape["families"]:
            if family["id"] in seen_families:
                raise QualificationError(f"duplicate family id: {family['id']}")
            seen_families.add(family["id"])
            if family["ruleIdentity"] not in RULE_IDENTITIES:
                raise QualificationError(f"unknown rule identity: {family['ruleIdentity']}")
            if family["authorLabel"] not in {"positive", "negative", "out-of-scope"}:
                raise QualificationError(f"unknown author label: {family['authorLabel']}")
            template = family["template"]
            if template not in PATTERNS or len(PATTERNS[template]) != family["count"]:
                raise QualificationError(f"template count is not frozen: {template}")
            if len(set(PATTERNS[template])) != family["count"]:
                raise QualificationError(f"case patterns must be behaviorally distinct: {template}")
            for ordinal in range(family["count"]):
                case_id = f"{family['id']}-{ordinal + 1:02d}"
                normalized = normalized_rendered_case(template, ordinal)
                if previous := seen_rendered_sources.get(normalized):
                    raise QualificationError(
                        "rendered cases must be behaviorally distinct after salt normalization: "
                        f"{previous} and {case_id}"
                    )
                seen_rendered_sources[normalized] = case_id
            counts[family["ruleIdentity"]][family["authorLabel"]] += family["count"]
            if family["authorLabel"] != "out-of-scope":
                shape_counts[family["ruleIdentity"]].add(shape["id"])
    for identity in RULE_IDENTITIES:
        if counts[identity]["positive"] < 30 or counts[identity]["negative"] < 60:
            raise QualificationError(f"{identity} requires at least 30 positive and 60 negative cases")
        if len(shape_counts[identity]) < 3:
            raise QualificationError(f"{identity} requires at least three repository shapes")
    if len(manifest["realWorldSnapshots"]) < 2:
        raise QualificationError("at least two real-world snapshots are required")
    for snapshot in manifest["realWorldSnapshots"]:
        notes = snapshot.get("provisionalAuditNotes")
        if (
            not isinstance(notes, list)
            or not notes
            or not all(isinstance(note, str) and note.strip() for note in notes)
        ):
            raise QualificationError(
                f"snapshot requires provisional audit notes: {snapshot.get('id', '<unknown>')}"
            )


def _materialize_shape(definition: dict[str, Any], synthetic_root: Path) -> MaterializedShape:
    shape_root = synthetic_root / definition["id"]
    shape_root.mkdir(parents=True)
    cases: list[CorpusCase] = []
    source_to_case: dict[str, str] = {}
    manifest_entries: list[dict[str, str]] = []
    module_names = ("Accounts", "Fulfillment", "Payments")
    for family_index, family in enumerate(definition["families"]):
        for ordinal in range(family["count"]):
            case_id = f"{family['id']}-{ordinal + 1:02d}"
            rendered = render_case(family["template"], ordinal)
            logical_bytes = {path: content.encode() for path, content in rendered.items()}
            written_paths: list[str] = []
            written_spans: list[tuple[str, int, int]] = []
            for source_name, content in rendered.items():
                relative = _layout_path(definition["layout"], case_id, source_name, family_index)
                destination = shape_root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(content)
                normalized = relative.as_posix()
                source_to_case[normalized] = case_id
                written_paths.append(normalized)
                written_spans.append((normalized, 1, len(content.splitlines())))
                if definition["layout"] == "manifest":
                    manifest_entries.append(
                        {"path": normalized, "module": module_names[family_index % len(module_names)]}
                    )
            cases.append(
                CorpusCase(
                    case_id=case_id,
                    rule_identity=family["ruleIdentity"],
                    author_label=family["authorLabel"],
                    repository_shape=definition["id"],
                    ambiguity_or_benign_pattern=case_pattern(family["template"], ordinal),
                    rationale=family["rationale"],
                    source_digest=_framed_digest(logical_bytes),
                    source_paths=tuple(sorted(written_paths)),
                    source_spans=tuple(sorted(written_spans)),
                )
            )
    if definition["layout"] == "manifest":
        source_manifest = shape_root.parent / f"{definition['id']}-sources.json"
        source_manifest.write_text(
            json.dumps({"root": str(shape_root), "sources": manifest_entries}, indent=2, sort_keys=True) + "\n"
        )
        cli_input = ["analyze", "--manifest", str(source_manifest)]
    else:
        cli_input = ["analyze", str(shape_root)]
    return MaterializedShape(definition, shape_root, cli_input, cases, source_to_case)


def _layout_path(layout: str, case_id: str, source_name: str, family_index: int) -> Path:
    if layout == "flat":
        return Path(f"{case_id}--{source_name}")
    if layout == "nested":
        return Path("Sources") / f"Feature{family_index + 1}" / case_id / source_name
    return Path("Modules") / f"Module{family_index % 3 + 1}" / case_id / source_name


def _run_cli(
    swift_debt: Path,
    cli_input: list[str],
    sidecar: Path,
    jobs: int,
    prefix: list[str] | None = None,
) -> tuple[dict[str, Any], bytes]:
    sidecar.parent.mkdir(parents=True, exist_ok=True)
    command = (prefix or []) + [str(swift_debt)] + cli_input + [
        "--jobs", str(jobs), "--repository-evidence", str(sidecar),
    ]
    environment = os.environ.copy()
    environment.update({"CI": "1", "TERM": "dumb"})
    result = subprocess.run(command, capture_output=True, env=environment, check=False)
    if result.returncode != 0:
        raise QualificationError(
            f"CLI failed ({result.returncode}): {' '.join(command)}\n{result.stderr.decode(errors='replace')}"
        )
    if result.stderr:
        raise QualificationError(f"CLI wrote stderr: {result.stderr.decode(errors='replace')}")
    data = sidecar.read_bytes()
    return json.loads(data), data


def _detection_case_ids(detection: dict[str, Any], source_to_case: dict[str, str]) -> set[str]:
    locations = [unit["location"] for unit in detection["explanation"]["comparedUnits"]]
    return {source_to_case[location["file"]] for location in locations if location["file"] in source_to_case}


def _published_detection(detection: dict[str, Any]) -> dict[str, Any]:
    return {
        "primaryLocation": detection["primaryLocation"],
        "selectorFingerprint": detection["selector"]["evidenceFingerprint"],
        "decisiveFacts": detection["explanation"]["decisiveFacts"],
        "comparedUnits": detection["explanation"]["comparedUnits"],
    }


def _evaluate_cases(
    manifest: dict[str, Any],
    cases: list[CorpusCase],
    detections: dict[tuple[str, str], list[dict[str, Any]]],
    issues: list[str],
) -> list[dict[str, Any]]:
    metadata = {rule["identity"]: rule for rule in manifest["rules"]}
    reports = []
    for identity in RULE_IDENTITIES:
        rule_cases = sorted((case for case in cases if case.rule_identity == identity), key=lambda item: item.case_id)
        matrix = {"truePositive": 0, "falsePositive": 0, "trueNegative": 0, "falseNegative": 0}
        case_results = []
        false_positive_ids = []
        false_negative_ids = []
        out_of_scope_ids = []
        for case in rule_cases:
            observed = detections.get((identity, case.case_id), [])
            detected = bool(observed)
            if case.author_label == "out-of-scope":
                classification = "excluded-out-of-scope"
                out_of_scope_ids.append(case.case_id)
            elif case.author_label == "positive" and detected:
                classification = "true-positive"
                matrix["truePositive"] += 1
            elif case.author_label == "positive":
                classification = "false-negative"
                matrix["falseNegative"] += 1
                false_negative_ids.append(case.case_id)
            elif detected:
                classification = "false-positive"
                matrix["falsePositive"] += 1
                false_positive_ids.append(case.case_id)
            else:
                classification = "true-negative"
                matrix["trueNegative"] += 1
            if case.author_label == "positive" and len(observed) != 1:
                issues.append(f"{case.case_id}: expected exactly one detection, observed {len(observed)}")
            if case.author_label == "negative" and observed:
                issues.append(f"{case.case_id}: expected no detection, observed {len(observed)}")
            case_results.append(
                {
                    "id": case.case_id,
                    "ruleIdentity": identity,
                    "semanticRevision": metadata[identity]["semanticRevision"],
                    "repositoryShape": case.repository_shape,
                    "authorLabel": case.author_label,
                    "labelStatus": "pending-two-qualified-reviewers",
                    "ambiguityOrBenignPattern": case.ambiguity_or_benign_pattern,
                    "rationale": case.rationale,
                    "sourceIdentity": {
                        "algorithm": "sha256-framed-path-and-bytes-v1",
                        "value": case.source_digest,
                    },
                    "sourcePaths": list(case.source_paths),
                    "sourceSpans": [
                        {"file": file, "startLine": start, "endLine": end}
                        for file, start, end in case.source_spans
                    ],
                    "classificationAgainstAuthorLabel": classification,
                    "provisionalMetricsInclusion": (
                        "excluded-out-of-scope"
                        if case.author_label == "out-of-scope"
                        else "included"
                    ),
                    "detections": observed,
                }
            )
        precision = _ratio(matrix["truePositive"], matrix["truePositive"] + matrix["falsePositive"])
        false_positive_rate = _ratio(
            matrix["falsePositive"], matrix["falsePositive"] + matrix["trueNegative"]
        )
        recall = _ratio(matrix["truePositive"], matrix["truePositive"] + matrix["falseNegative"])
        thresholds_pass = precision >= 0.90 and false_positive_rate <= 0.05 and recall >= 0.80
        rule = metadata[identity]
        reports.append(
            {
                "ruleIdentity": identity,
                "semanticRevision": rule["semanticRevision"],
                "supportState": "Research",
                "observableScope": rule["observableScope"],
                "scopeExclusions": rule["scopeExclusions"],
                "knownFalsePositiveRisks": rule["knownFalsePositiveRisks"],
                "knownFalseNegativeRisks": rule["knownFalseNegativeRisks"],
                "authoredCaseCounts": {
                    "positive": sum(case.author_label == "positive" for case in rule_cases),
                    "adversarialNegative": sum(
                        case.author_label == "negative" for case in rule_cases
                    ),
                    "outOfScope": sum(
                        case.author_label == "out-of-scope" for case in rule_cases
                    ),
                    "repositoryShapes": len(
                        {
                            case.repository_shape
                            for case in rule_cases
                            if case.author_label != "out-of-scope"
                        }
                    ),
                },
                "provisionalConfusionMatrix": matrix,
                "provisionalMetricsPopulation": "positive-and-adversarial-negative-cases-only",
                "provisionalMetrics": {
                    "precision": f"{precision:.6f}",
                    "falsePositiveRate": f"{false_positive_rate:.6f}",
                    "recall": f"{recall:.6f}",
                },
                "engineeringThresholds": {
                    "status": "pass" if thresholds_pass else "fail",
                    "precisionMinimum": "0.900000",
                    "falsePositiveRateMaximum": "0.050000",
                    "recallMinimum": "0.800000",
                    "qualificationEffect": "none-until-independent-review",
                },
                "falsePositiveCaseIDs": false_positive_ids,
                "falseNegativeCaseIDs": false_negative_ids,
                "outOfScopeCaseIDs": out_of_scope_ids,
                "caseResults": case_results,
            }
        )
    return reports


def _evaluate_snapshot(
    swift_debt: Path,
    fixture_root: Path,
    definition: dict[str, Any],
    sidecar_root: Path,
) -> dict[str, Any]:
    source_root = fixture_root / definition["sourceRoot"]
    license_path = fixture_root / definition["licensePath"]
    if not license_path.is_file():
        raise QualificationError(f"snapshot license is missing: {license_path}")
    snapshot_files: dict[str, bytes] = {}
    for source in definition["includedSources"]:
        vendored = source_root / source["vendoredPath"]
        data = vendored.read_bytes()
        if _digest(data) != source["sha256"]:
            raise QualificationError(
                f"snapshot source does not match its pinned digest: {definition['id']}/{source['vendoredPath']}"
            )
        snapshot_files[source["analysisPath"]] = data
    actual_digest = _framed_digest(snapshot_files)
    if actual_digest != definition["sourceTreeDigest"]:
        raise QualificationError(f"snapshot source digest changed: {definition['id']}")
    analysis_root = sidecar_root / f"snapshot-input-{definition['id']}"
    analysis_root.mkdir()
    for relative, data in snapshot_files.items():
        destination = analysis_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    report, _ = _run_cli(
        swift_debt,
        ["analyze", str(analysis_root)],
        sidecar_root / f"snapshot-{definition['id']}.json",
        jobs=1,
    )
    observed_rules = []
    for rule in report["rules"]:
        observed_rules.append(
            {
                "ruleIdentity": rule["ruleIdentity"],
                "semanticRevision": rule["semanticRevision"],
                "completionState": rule["completionState"],
                "detectionCount": len(rule["detections"]),
                "detections": [_published_detection(item) for item in rule["detections"]],
                "issues": rule["issues"],
                "labelStatus": "pending-two-qualified-reviewers",
            }
        )
    return {
        "id": definition["id"],
        "repositoryURL": definition["repositoryURL"],
        "commit": definition["commit"],
        "license": definition["license"],
        "licensePath": definition["licensePath"],
        "checkout": definition["checkout"],
        "analyzerGenerator": report["generator"],
        "includedSources": definition["includedSources"],
        "sourceIdentity": {
            "vendoredTree": {"algorithm": "sha256-framed-path-and-bytes-v1", "value": actual_digest},
            "repositorySnapshot": report["snapshot"]["contentDigest"],
        },
        "observedRules": observed_rules,
        "metricsInclusion": "excluded-until-independent-case-labeling",
        "provisionalAuditNotes": definition["provisionalAuditNotes"],
    }


def _verify_determinism(
    swift_debt: Path,
    source_root: Path,
    sidecar_root: Path,
    runs: int,
    parse_jobs: list[int],
) -> tuple[dict[str, Any], bytes]:
    if runs != 10 or parse_jobs != [1, 2, 8]:
        raise QualificationError("the release determinism gate requires 10 runs at jobs 1,2,8")
    _initialize_frozen_git_repository(source_root)
    baseline: bytes | None = None
    job_reports = []
    for jobs in parse_jobs:
        digests = []
        for index in range(runs):
            _require_clean_git(source_root)
            _, data = _run_cli(
                swift_debt,
                ["analyze", str(source_root)],
                sidecar_root / f"determinism-j{jobs}-r{index + 1}.json",
                jobs=jobs,
            )
            _require_clean_git(source_root)
            if baseline is None:
                baseline = data
            elif data != baseline:
                raise QualificationError(f"repository evidence differs at jobs={jobs}, run={index + 1}")
            digests.append(_digest(data))
        job_reports.append(
            {
                "parseJobs": jobs,
                "runs": runs,
                "byteDigest": digests[0],
                "allByteIdentical": len(set(digests)) == 1,
                "gitStateBeforeAndAfterEveryRun": "clean",
            }
        )
    assert baseline is not None
    return (
        {
            "status": "pass",
            "runsPerJobCount": runs,
            "parseJobCounts": parse_jobs,
            "totalRuns": runs * len(parse_jobs),
            "allRunsByteIdentical": True,
            "evidenceByteCount": len(baseline),
            "evidenceByteDigest": _digest(baseline),
            "runs": job_reports,
        },
        baseline,
    )


def _verify_network_isolation(
    swift_debt: Path,
    source_root: Path,
    sidecar_root: Path,
    expected: bytes,
) -> dict[str, Any]:
    if platform.system() != "Darwin" or not Path("/usr/bin/sandbox-exec").is_file():
        raise QualificationError("network-denied verification currently requires macOS sandbox-exec")
    profile = "(version 1)\n(allow default)\n(deny network*)"
    _, data = _run_cli(
        swift_debt,
        ["analyze", str(source_root)],
        sidecar_root / "network-denied.json",
        jobs=1,
        prefix=["/usr/bin/sandbox-exec", "-p", profile],
    )
    if data != expected:
        raise QualificationError("network-denied output differs from the deterministic baseline")
    return {
        "status": "pass",
        "harness": "macOS sandbox-exec deny network wildcard",
        "defaultCLIConfiguration": True,
        "outputMatchesUnsandboxedBaseline": True,
        "evidenceByteDigest": _digest(data),
    }


def _initialize_frozen_git_repository(root: Path) -> None:
    subprocess.run(["git", "init", "--quiet", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "SwiftDebt Qualification"], check=True)
    subprocess.run(
        ["git", "-C", str(root), "config", "user.email", "qualification@swiftdebt.invalid"], check=True
    )
    subprocess.run(["git", "-C", str(root), "config", "commit.gpgsign", "false"], check=True)
    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
    environment = os.environ.copy()
    environment.update(
        {
            "GIT_AUTHOR_DATE": "2026-09-25T12:00:00Z",
            "GIT_COMMITTER_DATE": "2026-09-25T12:00:00Z",
        }
    )
    subprocess.run(
        ["git", "-C", str(root), "commit", "--quiet", "-m", "Freeze qualification fixture"],
        check=True,
        env=environment,
    )
    _require_clean_git(root)


def _require_clean_git(root: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"],
        capture_output=True,
        check=True,
    )
    if result.stdout:
        raise QualificationError(f"determinism fixture is not clean: {result.stdout.decode()}")


def _tree_digest(root: Path) -> dict[str, str]:
    files = {item.relative_to(root).as_posix(): item.read_bytes() for item in sorted(root.rglob("*.swift"))}
    return {"algorithm": "sha256-framed-path-and-bytes-v1", "value": _framed_digest(files)}


def _framed_digest(files: dict[str, bytes]) -> str:
    hasher = hashlib.sha256()
    for relative, data in sorted(files.items()):
        path_bytes = relative.encode()
        hasher.update(len(path_bytes).to_bytes(8, "big"))
        hasher.update(path_bytes)
        hasher.update(len(data).to_bytes(8, "big"))
        hasher.update(data)
    return hasher.hexdigest()


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _ratio(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0
