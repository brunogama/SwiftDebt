---
title: R2 Rule Catalog & Evidence — resolving the PRD's 12 open questions
status: accepted
date: 2026-09-27
---

# ADR 0001: R2 open-question resolutions

`docs/SwiftDebt_R2_Rule_Catalog_Evidence_PRD/prd.md` section 9 lists 12 open
questions blocking implementation. This ADR settles each one so R2 work can
be sequenced without re-litigating design during ticket work. Rationale
draws on the addendum's proposed mechanisms, which already answer most of
these implicitly.

## 1. Can one Research Claim decompose into multiple Rule Definitions?

Yes. A Research Claim is provenance, not identity (Invariant Q1). A claim may
back multiple Rule Definitions with distinct stable IDs (e.g.
`errors.force-try` for the broad syntax rule and
`errors.force-try-external-boundary` for the symbol-classified variant, per
addendum J/#28). Governance: every decomposed definition must cite the same
`researchItem` in provenance, and the catalog validator (FR-20) must reject
two definitions with identical `(researchItem, evidenceContract)` pairs as
duplicates disguised as decomposition.

## 2. Which Support State names belong in the public API?

All five from the glossary are public: `supported`, `partial`, `research`,
`externalRuntimeRequired`, `notReliablyObservable`. Coverage reporting
(FR-18) requires grouping by all of them, so hiding any defeats SM-2/SM-1.

## 3. Minimum Evidence Contract that promotes Partial to Supported

A definition promotes to Supported only when: every `EvidencePredicate`
required-fact leaf has a shipped implementation; positive and adversarial
fixtures both pass; and the Evidence Contract is satisfiable under at least
one enabled capability set with no fabricated evidence substituted for an
unavailable fact. Promotion is a catalog-validation-time check (FR-20), not
a manual flag, so `SM-C1` (don't inflate Supported by weakening contracts)
holds mechanically.

## 4. Which capabilities are public vs internal?

`AnalysisCapability` case names are public (rules declare requirements
against them, FR-4/FR-19). The resolution mechanism — the dependency DAG,
closure computation, and any concrete sensor/provider behind a capability —
is internal. Consumers see "this rule requires `isolation` + `controlFlow`",
never which sensor class backs `isolation`.

## 5. How do project-level Detections represent location?

Project-scope Detections (package manifest, Xcode project) carry a
`ProjectLocation` evidence-adjacent value (target name, manifest path, and
optionally a manifest line/plist key when the format supports it) rather
than a `SourceLocation`. `RuleScope.project` implementations never fabricate
a `SourceFileSyntax` location to satisfy a reporter expecting source spans
(addendum D/N-71).

## 6. Are runtime/external provider protocols in R2 scope?

Deferred to R3. R2 catalogs `runtimeDependent`/`external` claims (FR-12) and
defines the `DetectionMode` cases for them, but ships no provider protocol.
Adding a provider later must not change Rule Identity or Semantic Revision
(cross-cutting NFR), which is why the catalog/provider split exists now.

## 7. How do generated/test/vendor sources affect scope/policy?

Source classification (generated/test/vendor/production) is a Policy
concern, not a Rule Definition concern (Invariant Q5, addendum M). Rules
observe uniformly; Policy may warn-only or ignore a Detection sourced from
test/vendor code without touching the rule's Semantic Revision. R2 must
expose the classification as part of scope-appropriate context (FR-14) so
Policy can act on it.

## 8. What control/data-flow sufficiency is required for actor reentrancy?

R2 ships intraprocedural analysis only: single-function CFG plus
suspension-point tracking and post-suspension-use detection within that
function's body. Interprocedural data flow (tracking invariants across
call boundaries) is out of scope for R2 and deferred to R3's richer
planner (addendum P). A reentrancy rule that cannot establish sufficient
in-function evidence reports `ObservationState.partial`, never a
false-negative "clean."

## 9. Is the catalog authored in Swift, YAML, generated Swift, or hybrid?

Hybrid, per addendum H/H-note: YAML is the source of truth for contract
metadata (identity, scope, mode, requirements, evidence predicate,
provenance, support state). A build-time plugin validates and generates
Swift metadata types from the YAML so the catalog is compile-time checked
(answers Q12 together with this). Executable detection logic is always
hand-written Swift — the manifest never carries expressions (addendum H
explicit prohibition).

## 10. How does Evidence Revision compatibility work without Semantic Revision changes?

Evidence Revision increments when *how* evidence is extracted changes
(a sensor bug fix, a broader syntax match) while the rule's semantic claim
is untouched. Two Detections with the same Semantic Revision but different
Evidence Revisions are comparable as the same claim with different
observation fidelity; reconciliation (R1) treats them as the same Finding
lineage. A Semantic Revision bump is required only when the claim itself
changes (what counts as a violation).

## 11. Which claims form the implementation acceptance corpus beyond catalog completeness?

The MVP acceptance corpus is the addendum J example set plus enough breadth
to cover every `DetectionMode` and every `RuleScope` at least once:
`try!` (#28, deterministic/syntax), `DispatchSemaphore.wait` in async (#12,
derived/syntax+symbols), actor reentrancy (#19, derived/sourceUnit,
multi-capability), mixed responsibilities (#1, heuristic/symbols),
`static let shared` (#3, heuristic with negative-evidence guard), primitive
identifiers (#40, heuristic + similarity-as-evidence-not-detection),
`@ObservedObject` ownership (#46, deterministic/sourceUnit), SwiftPM
`unsafeFlags` (#71, deterministic/project scope), and one CI/CD item from
#86-92 cataloged as `external` with no detector. This corpus exercises
every Detection Mode and Scope combination the PRD commits to for MVP
(section 6.1).

## 12. Is catalog validation compile-time, startup-time, or both?

Both. Compile-time: the YAML-to-Swift codegen plugin validates identity
uniqueness, capability references, and evidence-predicate shape, and fails
the build on violation. Startup-time: the running catalog re-validates
support-state consistency and provenance coverage against the currently
enabled rule set, because codegen alone cannot see runtime configuration
(SM-5). Startup validation failure disables the offending rule
(`ObservationState.disabled`) rather than crashing the whole run.

## Consequences

These resolutions unblock Frame/track decomposition for R2 implementation.
Any future change to a resolution here is a new ADR, not a silent edit —
research numbers and rule IDs already minted under this ADR's decisions
must keep working per Invariant Q6/Q10.
