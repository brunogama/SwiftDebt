# R2 Rule Catalog acceptance traceability

This is a baseline gap inventory for current main `84da01c`, **not** a completion certificate. Status `PARTIAL` means a released mechanism exists but the revised PRD's acceptance evidence is missing. `OPEN` means the required integration is not present in the inspected source tree. Old `feat/debtmap` prototypes are not evidence that main ships a feature. Update each row only after a real test or CLI artifact demonstrates its acceptance predicate.
Tracking: [#109](https://github.com/brunogama/SwiftDebt/issues/109). Existing [#48](https://github.com/brunogama/SwiftDebt/issues/48) and [#60](https://github.com/brunogama/SwiftDebt/issues/60) own complementary detector and release gates.

---

## Requirements

| Requirement | Status | Released main evidence | Remaining acceptance gate |
| --- | --- | --- | --- |
| FR-1 source-backed catalog | PARTIAL | `Sources/SwiftDebtCore/RefactoringCodeSmellCatalog.swift`, its four entry extensions, `Tests/SwiftDebtCoreTests/RefactoringCodeSmellCatalogTests.swift`: 24 named Fowler entries | One typed canonical identity and explicit provenance for each Fowler claim and accepted SwiftDebt extension, with no duplicate authored catalog |
| FR-2 stable identity | PARTIAL | `Sources/SwiftDebtCore/RuleIdentity.swift`, `Tests/SwiftDebtCoreTests/RuleIdentityTests.swift`: validated identity | Apply identity to every canonical entry; reject duplicate definitions, preserve released IDs |
| FR-3 Support State | PARTIAL | `Sources/SwiftDebtCore/RefactoringCodeSmellCatalog.swift`: supported/partially supported/research/not reliably observable | Add external/runtime-required case and validate maturity against real implementation/evidence |
| FR-4 capabilities | OPEN | `Sources/SwiftDebtSyntax/DebtRule.swift`: existing context is source-local | Declare capability requirements with executable providers and honest unavailable states |
| FR-5 shared requirements | OPEN | `Sources/SwiftDebtSyntax/RuleEngine.swift`: runs rules per parsed source | Compute enabled-rule union and dependency closure with inspectable contributors |
| FR-6 selective execution | OPEN | Source-only analysis is inexpensive but has no capability planner | Prove syntax-only executions initialize zero unused semantic/history/CI providers |
| FR-7 Evidence Contract | PARTIAL | `RefactoringCodeSmellCatalog.swift` records human-readable required/optional evidence; `Sources/SwiftDebtCore/DebtModels.swift` models evidence availability | Typed required/optional predicates, logical alternatives, missing-required gate |
| FR-8 typed evidence | PARTIAL | `DebtModels.swift`: typed availability and requirement, string-valued kind and raw value | Typed facts usable by reporters without parsing prose; no Finding identity in snapshot evidence |
| FR-9 explanation | PARTIAL | `Sources/SwiftDebtKit/CoverageExplanationService.swift`, rule messages and notes | End-to-end separation of observed fact, derived evidence, and conclusion |
| FR-10 Observation State | PARTIAL | `Sources/SwiftDebtLifecycle/ObservationOutcome.swift`, `ObservationScope.swift`: parse/snapshot and absence semantics | Per-rule Complete/Partial/Unavailable/Failed/Disabled wired to real reports |
| FR-11 snapshot completeness | PARTIAL | `ObservationOutcome.swift`: absence gate; main lifecycle acceptance tests | Required-capability failure blocks dependent rule completion and resolution through real CLI |
| FR-12 external/runtime honesty | PARTIAL | `Sources/SwiftDebtCore/CompilerEvidenceAvailability.swift`, main compiler sidecar ADR | Catalog external claims with stable identity and unavailable provider state, not fabricated static detection |
| FR-13 Rule Scope | PARTIAL | `RefactoringCodeSmellCatalog.swift`: human-readable scope text | Typed source/repository/project/history/runtime scope on canonical definitions |
| FR-14 multiple contexts | OPEN | `DebtRule.swift`: source-only context | Real broader context with a non-source provider and positive/negative CLI fixtures |
| FR-15 Detection Mode | OPEN | Existing detectors imply syntax/derived work, not catalog metadata | Declare deterministic/derived/heuristic/historical/runtime/external modes per definition |
| FR-16 no fabricated confidence | PARTIAL | Compiler availability and repository-evidence classes are non-probability states | End-to-end test that similarity is evidence, never an uncalibrated probability claim |
| FR-17 policy boundary | PARTIAL | Existing R1 rule metadata carries `defaultSeverity` in `RuleIdentity.swift`; lifecycle/policy already distinct | New catalog definition has no universal severity; policy changes do not change semantic revision |
| FR-18 coverage report | OPEN | Existing LCOV coverage is code coverage, not rule-catalog coverage | Partitioned source/extension coverage by support, category, scope, mode |
| FR-19 rule inspection | PARTIAL | `Sources/SwiftDebtReporting/RuleAnalysisRenderer.swift` reports detection identity/outcome | Queryable provenance, requirements, evidence, revisions, and implementation state |
| FR-20 catalog validation | PARTIAL | 24-smell schema rejects changed catalog snapshots in `RefactoringCodeSmellCatalogTests.swift` | Reject duplicate/missing provenance, invalid capability/evidence references and inconsistent maturity in the Swift registry |

---

## Success metrics

| Metric | Status | Verification still required |
| --- | --- | --- |
| SM-1 catalog completeness | OPEN | Demonstrate 24/24 distinct publisher-backed identities and 100% of individually accepted extensions mapped or explicitly deduplicated; separate denominators |
| SM-2 honest observability | OPEN | All active rules whose required capability is unavailable report non-complete and cannot prove absence |
| SM-3 explainability | OPEN | Every Supported rule has machine-readable evidence and a fact/derived/conclusion explanation |
| SM-4 capability selectivity | OPEN | Measured syntax-only path starts zero unrelated semantic/history/external providers |
| SM-5 catalog integrity | OPEN | Negative Swift-registry tests for every required invalidity class |
| SM-6 mode coverage | OPEN | Real deterministic and derived detections with fixtures; separately cataloged external/runtime claims |

---

## Fixed compatibility baseline

Before document edits, `swift build --build-tests && swift test` passed all 114 main tests in the isolated worktree. The real `swift-debt analyze Examples/Sources --format json` completed with `AnalysisReport.schemaVersion == 2` and was saved at `/tmp/swiftdebt-r2-rule-catalog/main-baseline-analysis.json` (temporary, not committed; SHA-256 `2645843e8cf3fedad95f6d2643feae3b6c891b2d6a016bce13d6259d9c648603`). The build and test transcripts are at `/tmp/swiftdebt-r2-rule-catalog/main-baseline-{build,tests}.log`. `RefactoringCodeSmellCatalogTests.swift` enforces the 24 ordered schema-1 entries and reject-unknown-schema behavior; capture byte-exact schema-1 output before changing their implementation. The old branch's YAML pilot and marker-only rule contexts do not satisfy any row here. No CI workflow was executed.
