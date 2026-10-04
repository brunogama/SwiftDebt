---
title: SwiftDebt R2 - Rule Catalog & Evidence-Driven Analysis
created: 2026-09-27
updated: 2026-10-04
status: implementation-draft
---

# PRD: SwiftDebt R2 - Rule Catalog & Evidence-Driven Analysis

---

## 0. Document Purpose
R2 turns the publisher-backed 24 Chapter 3 code smells in Fowler's *Refactoring*, second edition, plus explicitly recorded SwiftDebt-authored Swift extensions into an honest, executable analysis model. The publisher's [table of contents](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) fixes the Fowler denominator; it does not establish Swift-specific debt judgments. The original draft's numbered 100-item research source could not be authenticated and is not an acceptance baseline. This companion PRD elaborates `docs/prd-r2.md`; [ADR 0002](../adr/0002-r2-rule-catalog-source-and-authoring.md) records the source and single Swift-authoring decision. Requirements describe capabilities; proposed mechanisms live in `prd-addendum.md`. R2 preserves R1 authority: rules observe, the engine owns lifecycle, policy owns consequences, location is evidence rather than identity, and failure to observe is not verified absence. A catalog entry does not automatically become a supported detector.

---

## 1. Vision
SwiftDebt R2 must answer: **which debt claims does SwiftDebt understand, which can it observe, what evidence is required, what was actually observed, and which claims remain incomplete or unavailable?** Coverage becomes auditable rather than a count of rule types.

The thesis is separation between debt claim, observability, evidence, implementation, and policy. `try!` may be syntactically observable; actor reentrancy requires isolation/control-flow/data-flow; CI toolchain pinning requires project/external configuration; systematic Instruments usage cannot be proven from ordinary source. R2 preserves these distinctions rather than forcing every item into SwiftSyntax.

R2 remains local-first, fast, deterministic where possible, and CI-suitable. Expensive capabilities execute only when active rules require them. Missing evidence never becomes negative evidence. The capability vocabulary is forward-compatible with R3 but R3 is not required.

---

## 2. Target User
### 2.1 Jobs To Be Done
- Audit a repository against all 24 Fowler claims and every accepted SwiftDebt-authored extension without confusing unobservable claims with clean code.
- Understand evidence supporting each Detection.
- Add a rule without inventing a new execution architecture.
- Know which claims are Supported, Partial, Research, External/Runtime Required, or Not Reliably Observable.
- Execute only capabilities required by enabled rules.
- Consume typed observations without parsing prose.

### 2.2 Non-Users
R2 is not an LLM reviewer, automatic refactoring engine, runtime profiler, replacement for Instruments/Thread Sanitizer, CI provider, or architecture visualization product. It may model claims from those domains but cannot fabricate evidence. Automatic remediation and repository chat are out of scope.

### 2.3 Key User Journeys
**UJ-1 - Bruno audits the catalog.** He runs SwiftDebt and receives evaluated, partial, unavailable, failed, disabled, and detected states separately. The value moment is distinguishing “no detection” from “could not observe.” Capability failure only makes dependent rules incomplete.

**UJ-2 - Maya implements actor-reentrancy detection.** She starts from an accepted source claim or project-authored Swift extension, sees required isolation/control-flow/data-flow evidence, implements/reuses analyzers, adds positive/adversarial fixtures, and promotes Support State only after the Evidence Contract passes.

**UJ-3 - Renata diagnoses CI cost.** She inspects active Rule Requirements, identifies which rule requested expensive analysis, changes scope/configuration, and verifies unrelated capabilities no longer execute.

**UJ-4 - Alex consumes results programmatically.** Stable Rule Identity, Observation State, Detection Mode, typed Evidence, and snapshot provenance let automation distinguish detections from unavailable observations.

---

## 3. Glossary
- **Source Claim**: One of the 24 named Fowler smells; not automatically executable. The publisher's table of contents authenticates names, while Swift examples and explanations are original.
- **SwiftDebt Extension**: An individually accepted, project-authored debt claim with an explicit rationale and citations for its Swift/tooling facts. Match it to an existing Fowler identity first if the underlying smell is the same.
- **Provenance**: The claim's source kind and citation or project rationale, queryable by Rule Identity. Numbering in the unverified draft is not provenance.
- **Rule Definition**: Stable definition containing identity, category, scope, requirements, Evidence Contract, revisions, and Support State.
- **Rule Implementation**: Executable logic evaluating a Rule Definition.
- **Rule Catalog**: One Swift-authored, typed, versioned collection of Rule Definitions; the published 24-smell report is an adapter, not a second authored catalog.
- **Rule Identity**: Stable semantic identifier; a claimed source or project-authored rationale is provenance, not an unstable number.
- **Analysis Capability**: Kind of observation/derived analysis a rule may require.
- **Rule Requirements**: Capabilities required for evaluation.
- **Evidence**: Typed, snapshot-local support for a Detection.
- **Evidence Contract**: Required/optional Evidence for evaluating a rule.
- **Detection**: Snapshot observation emitted by a Rule Implementation.
- **Finding**: R1 lifecycle entity reconciled across snapshots.
- **Observation State**: Complete, Partial, Unavailable, Failed, or Disabled.
- **Support State**: Supported, Partial, Research, External/Runtime Required, or Not Reliably Observable.
- **Detection Mode**: Deterministic, Derived, Heuristic, Historical, Runtime-Dependent, or External.
- **Policy**: Authority determining consequences.
- **Semantic/Implementation/Evidence Revision**: Independent compatibility axes.

---

## 4. Features
### 4.1 Canonical Rule Catalog
The single Swift-authored Rule Catalog is the source of truth for the 24 publisher-backed Fowler smells and each accepted SwiftDebt extension, including unsupported, partial, external, and not reliably observable claims. If a Swift example expresses an existing Fowler smell, reuse its identity; do not inflate either catalog partition. Stable IDs do not depend on list order or implementation type. Provenance is queryable, and published schema 1 projects the original ordered 24 Fowler entries without changed bytes or meaning. This realizes UJ-1/UJ-2.

**FR-1 - Catalog accepted source claims.** Each of the 24 named Fowler smells maps to exactly one canonical identity; every accepted SwiftDebt-authored extension has a distinct identity, rationale, and citations for technical facts. No unsourced research numbers count toward coverage. Fowler and extension completeness are reported separately; no claim is silently dropped.

**FR-2 - Stable Rule Identity.** Identity is independent of list order, source file, and implementation type; duplicates are rejected.

**FR-3 - Explicit Support State.** Every definition exposes maturity; implementation existence alone cannot imply Supported.

### 4.2 Capability-Aware Requirements
Rules declare what must be observable. Requirements describe capabilities, not concrete analyzers. Cheap rules stay cheap; advanced capabilities remain demand-driven.

**FR-4 - Declare Analysis Capabilities.** Requirements can include syntax, symbols, types, references, ownership, isolation, control flow, data flow, project/build, history, semantic similarity, runtime, and external evidence.

**FR-5 - Resolve shared requirements.** SwiftDebt computes union/dependency closure for enabled rules; disabled rules contribute nothing; the set is inspectable.

**FR-6 - Avoid unrelated work.** Syntax-only configurations initialize no semantic/history/CI subsystem; removing the last consumer removes that work.

### 4.3 Evidence Contracts
Evidence is first-class, typed, and snapshot-local. Rule Definitions declare sufficient evidence; Detections retain evidence for explanation. Opaque confidence is not evidence.

**FR-7 - Evidence Contract.** Required/optional evidence and valid conjunction/disjunction can be declared; unavailable required evidence prevents complete evaluation.

**FR-8 - Typed Evidence.** Reporters and tools interpret evidence without parsing messages; Evidence never owns Finding identity.

**FR-9 - Explain Detection.** Explanations distinguish observed facts, derived evidence, and rule conclusion.

### 4.4 Honest Observability
“No Detection” means verified absence only when observation is sufficient.

**FR-10 - Observation State.** Reports distinguish Complete, Partial, Unavailable, Failed, and Disabled.

**FR-11 - Snapshot completeness.** Capability failures make dependent rules incomplete; reconciliation cannot infer resolution from insufficient observation.

**FR-12 - External/runtime honesty.** Such claims remain cataloged without fabricated static detectors and can later gain providers without changing identity.

### 4.5 Scope-Aware Evaluation
Accepted claims span source, repository, project/build, history, runtime, and external systems.

**FR-13 - Declare Rule Scope.** Definitions state evaluation scope; implementations cannot silently require broader scope.

**FR-14 - Multiple Analysis Contexts.** Rules receive scope-appropriate context; project rules do not fabricate meaningless syntax nodes.

### 4.6 Detection Modes
**FR-15 - Declare Detection Mode.** Executable rules identify deterministic/derived/heuristic/historical/runtime/external mode.

**FR-16 - No fabricated confidence.** Similarity values may be evidence but not probability unless a calibrated model exists.

### 4.7 Policy Separation
**FR-17 - Consequence outside Rule Definition.** Policy can warn/fail differently by scope; policy changes do not alter Semantic Revision; implementations do not enforce consequences.

### 4.8 Coverage Reporting
**FR-18 - Coverage report.** Group catalog by Support State, category, scope, and Detection Mode.

**FR-19 - Rule inspection.** Expose provenance, requirements, Evidence Contract, revisions, and implementation state.

**FR-20 - Catalog validation.** Reject duplicate IDs, invalid capability references, inconsistent maturity, missing provenance, and incompatible evidence metadata.

---

## 5. Non-Goals
- Guarantee executable static detection for every cataloged claim.
- Treat missing runtime/external evidence as clean code.
- Make vector similarity authoritative.
- Automatic fixes/source mutation.
- Replace Instruments, TSan, compiler diagnostics, CI, or security scanners.
- Make severity intrinsic to rules.
- Universal debt/quality score.
- Require R3 for source-local rules.

---

## 6. MVP Scope
### 6.1 In Scope
All 24 Fowler smells plus individually accepted SwiftDebt extensions cataloged with separate provenance and coverage; stable identity/provenance; Support State; Rule Scope; Detection Mode; capability vocabulary; Evidence Contract; typed Evidence; Observation State; completeness propagation; source-local plus one broader scope contract; coverage APIs/CLI; R1 compatibility; representative Deterministic/Derived implementations; selective capability resolution.

### 6.2 Out of Scope
Full implementation of all claims; R3 RepositoryGraph/EvidenceGraph; remediation; IDE GUI; cloud analysis; LLM inference; full CI-provider integrations; runtime profiler; architecture visualization.

---

## 7. Success Metrics
- **SM-1 - Catalog completeness:** 24/24 Fowler smells mapped once, and 100% of individually accepted SwiftDebt extensions traceable to distinct entries or explicit mappings to existing Fowler identities; report the two partitions separately. Validates FR-1/FR-20.
- **SM-2 - Honest observability:** 100% of active rules with unavailable required capability are non-complete, never verified absence. Validates FR-10/FR-11/FR-12.
- **SM-3 - Explainability:** 100% of Supported rules satisfy Evidence Contract and explain without string parsing. Validates FR-7/FR-8/FR-9.
- **SM-4 - Capability selectivity:** syntax-only benchmarks execute zero unrelated semantic/history/external capabilities. Validates FR-5/FR-6.
- **SM-5 - Catalog integrity:** invalid identity/capability/evidence fixtures are rejected. Validates FR-2/FR-20.
- **SM-6 - Mode coverage:** validated Deterministic and Derived examples plus cataloged External/Runtime claims. Validates FR-12/FR-15.

- **SM-C1:** Do not inflate Supported count by weakening Evidence Contracts.
- **SM-C2:** Do not optimize capability richness by executing every analyzer.
- **SM-C3:** Do not optimize numeric confidence theater.

---

## 8. Cross-Cutting NFRs and Impact
Performance requires lazy capability execution and separate baselines for syntax-only and derived workloads. Deterministic rules must be materially reproducible for equivalent inputs/configuration/revisions. Default analysis remains local; cataloging external claims does not authorize transmission. Capability/cache failures degrade Observation State rather than fabricate absence. New capabilities must not change existing Rule Identity. Supported rules must expose testable evidence.

R2 depends on R1 Rule/Detection/Reconciler/Finding/AnalysisSnapshot/Policy separation. SwiftSyntax remains the main source sensor, while advanced capabilities may use specialized providers. Rule authoring changes substantially because metadata, observability, and Evidence Contracts become first-class. New versioned reporting exposes Observation State and Evidence while the existing 24-entry `RefactoringCodeSmellCatalogReport` schema 1, `AnalysisReport` schema 2, main CLI behavior, and compiler-evidence sidecar remain unchanged unless independently versioned and verified. Future R3 can consume the same requirements for a richer planner.

---

## 9. Decision history and implementation checks

The [archived branch ADR](archived-adr-0001-r2-open-questions.md) settled the original twelve questions for its draft. [ADR 0002](../adr/0002-r2-rule-catalog-source-and-authoring.md) supersedes only the unauthenticated 100-item source, YAML authoring, and YAML-specific compile-time validation mechanism. Runtime validation still fails closed per rule. Main's [compiler-evidence sidecar ADR](../adr/0001-compiler-evidence-sidecar-boundary.md) remains authoritative for its scope. The old branch's examples are candidate mappings, not a numbered acceptance corpus.

Before enabling a Swift-specific claim, establish whether it maps to an existing Fowler identity or deserves a distinct project-authored extension, document the technical citations and normative rationale, and prove its Evidence Contract with positive and adversarial real-CLI fixtures. Version any wider catalog report separately; preserve the public 24-entry schema 1 and `AnalysisReport` schema 2. A rule with an unavailable capability stays non-complete and cannot cause lifecycle resolution.

---

## 10. Assumptions Index
- [ASSUMPTION] R1 authority boundaries remain prerequisites.
- [VERIFIED SOURCE] The publisher's Chapter 3 table of contents names 24 Fowler smells; the existing main catalog reports 24 entries. No authoritative 100-item research set was supplied or authenticated.
- [PRODUCT DECISION] Accepted SwiftDebt extensions carry a project rationale and technical citations; the catalog is typed Swift and has one source of truth.
- [ASSUMPTION] Some claims are inherently external/runtime or not reliably observable.
- [ASSUMPTION] Capability selectivity is required for acceptable performance.
- [ASSUMPTION] R3 will reuse, not replace, R2 capability semantics.
