# Blueprint: source-backed R2 Rule Catalog on current main

Status: approved source and authoring decisions; implementation in progress on a clean worktree from main `84da01c`. The 100-item workflow in the original planning record is superseded, not erased. The original source search is preserved in `source-search.md`, and the branch's accepted ADR is archived without modification. Current-main tests passed (114 tests); the real CLI JSON baseline is stored at `/tmp/swiftdebt-r2-rule-catalog/main-baseline-analysis.json`.
Tracking: [SwiftDebt issue #109](https://github.com/brunogama/SwiftDebt/issues/109). Existing issue #48 owns the remaining Fowler detectors; #60 owns the separate R2 release gate. Neither is closed by this PRD contract.

---

## Agreed language and decisions

- **Source claim**: a named smell in Martin Fowler's *Refactoring*, second edition, chapter 3. The publisher's table of contents lists the 24 names at https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711. Coverage is 24/24 against this fixed source, not 100/100 against an unsupplied document.
- **Swift-specific mapping**: an addendum §J example. First compare it with a Fowler claim. If semantically the same, reuse the Fowler Rule Identity and add Swift evidence/implementation; otherwise register a distinct SwiftDebt-authored extension with an explicit policy rationale and primary citations for technical facts. Platform documentation proves facts, not that a pattern is debt. The nine example headings are candidates, not nine guaranteed new entries; the CI/CD range is one external candidate until separately sourced.
- **Rule Catalog**: one typed, versioned Swift source of truth and public inspection API, extending the existing main-branch Fowler catalog. No separate YAML or second authoritative catalog. Preserve its existing 24-entry report schema 1 byte-for-byte unless a separately versioned schema is deliberately introduced. Preserve AnalysisReport schema 2 behavior and R1 lifecycle/Policy authority.
- **Supported**: an implementation with a satisfiable Evidence Contract and positive/adversarial tests. A source claim or Swift extension is not automatically executable. Missing capability is not a clean result.
- **Accepted ADR**: preserve the old branch's accepted ADR unchanged in `archived-adr-0001-r2-open-questions.md`; new main ADR 0002 supersedes only its 100-item source and YAML ownership decisions, not the unrelated capability/evidence/lifecycle boundaries. Main's ADR 0001 about compiler evidence remains in force. The user chose selective port onto main, not a merge into the divergent feat/debtmap branch.

---

## Acceptance predicate and baseline

A fresh feature worktree from the exact current main SHA preserves baseline tests, existing Fowler schema 1 and AnalysisReport schema 2 examples, actual CLI behavior, and owner changes. A reproducible validator proves all 24 publisher-backed smells have exactly one canonical mapping; every accepted Swift extension has distinct provenance and no duplicate semantic Rule Identity; every catalog entry is Support State-correct; all FR-1 through FR-20 and revised SM-1 through SM-6 have evidence in a traceability matrix. Full `swift build --build-tests && swift test`, relevant format/lint, repository QA when agent infrastructure changes, offline and deterministic CLI tests, and independent diff review pass. Report gaps as NOT VERIFIED, not success.

Before code edits: Git status on both branches, exact main SHA, main build/test result, and a real schema-2 CLI JSON report were captured. The 24-smell ordering and unknown-schema rejection are covered by baseline tests; a byte-exact schema-1 output fixture must still be captured before changing that implementation. Durable outcomes and the schema-2 SHA-256 are in `decisions.tsv` and `traceability.md`; bulky raw logs remain under `/tmp/swiftdebt-r2-rule-catalog/` and are not claimed as committed. Preserve all unrelated owner files.

---

## Implementation sequence, each unit with its own gate

1. **Contract first:** add the superseding ADR and revise `docs/SwiftDebt_R2_Rule_Catalog_Evidence_PRD/prd.md` plus addendum to remove unsupported 100-item numbering, state two provenance kinds and partitioned coverage metrics, remove numeric examples, and map FR/SM acceptance to the current main release contract. Run link, terminology, and no-stale-100-reference checks. Keep `docs/prd-r2.md` as the separate release PRD.
2. **One source of truth:** inspect all affected files, then write failing tests against typed Rule Catalog uniqueness, provenance, support-state consistency, and schema compatibility. Resolve old-branch `RuleDefinition` against main's public `RuleDescriptor`, and old marker `AnalysisContextProtocol` against main's concrete source `AnalysisContext`: keep only one authored definition registry; project existing R1 descriptors and schema-1 catalog from it, preserve R1 rule behavior, and add broader contexts only with real providers. Reuse only needed branch capability/evidence ideas without copying same-named types. Retire branch-only YAML parser/validator/plugin instead of carrying a second authoring path. Verify 24/24 Fowler entries and byte-stable legacy JSON/report fixtures before proceeding.
3. **Selective capability and observability:** audit what main already has; port or deepen only missing capability closure, honest Observation State propagation, and scope-specific contexts. Test syntax-only zero-initialization and unavailable required-capability behavior through the real analysis pipeline and CLI. Do not create a parallel lifecycle or policy path.
4. **Swift mappings:** process addendum §J candidates one at a time. Deduplicate against Fowler identities; distinguish documented language/tool facts from SwiftDebt's normative debt claims. For each accepted implementation use red-positive/adversarial fixtures, typed evidence, actual CLI explanation, offline deterministic output, and a policy consequence test only at the Policy boundary. External/runtime items remain explicit incomplete/unsupported entries, never static detectors by guess.
5. **Coverage and inspection:** expose partitioned 24/24 Fowler and accepted-extension completeness, support state, scope, detection mode, evidence and provenance via library and CLI without changing older report bytes. Add negative Swift-registry fixtures and validate invalid IDs, capabilities, evidence, provenance, and maturity.
6. **Full acceptance:** rerun all focused and full gates, compare snapshots to baseline, update FR/SM traceability with direct evidence paths, independent code review, and publish only actually observed results. CI is NOT VERIFIED unless its exact workflow runs. Do not declare full PRD completion if any required provenance or observation gate remains open.

Only one writer owns the integration worktree. No broad parallel fanout, unrelated release work, issue closure, or destructive Git operations. Each accepted unit is reviewable before the next starts. Use TDD before code and read whole target files before editing. Use Git, never Jujutsu.

---

## Audit trail and stopping rules

The canonical append-only TSV is `docs/SwiftDebt_R2_Rule_Catalog_Evidence_PRD/decisions.tsv` in this worktree. One row per decision, baseline, unit, failure, or pivot with a resolvable artifact path. Temporary baseline logs remain under `/tmp/swiftdebt-r2-rule-catalog/`; do not claim they are committed evidence. The original 100-item source search stays visible and is superseded by user-approved scope changes, never erased. Stop for a new decision if a Swift-specific claim cannot be distinguished from Fowler, schema compatibility cannot be preserved, or a proposed fix would weaken an Evidence Contract.
