---
title: SwiftDebt R2 — Rule Catalog & Evidence-Driven Analysis
created: 2026-09-27
updated: 2026-09-27
status: draft
---

# PRD: SwiftDebt R2 — Rule Catalog & Evidence-Driven Analysis

## 0. Document Purpose
R2 converts the 100-item Swift technical-debt research catalog into an honest, executable analysis model. It is for the product owner, maintainers, rule authors, CI/tooling consumers, and downstream architecture/story workflows. Requirements describe capabilities; proposed Swift mechanisms live in `prd-addendum.md`. R2 preserves R1 authority: Rules observe, Engine owns lifecycle, Policy owns consequences, location is evidence rather than identity, and failure to observe is not verified absence. The central constraint is that 100 researched characteristics do not automatically mean 100 executable static rules.

## 1. Vision
SwiftDebt R2 must answer: **which debt claims does SwiftDebt understand, which can it observe, what evidence is required, what was actually observed, and which claims remain incomplete or unavailable?** Coverage becomes auditable rather than a count of rule types.

The thesis is separation between debt claim, observability, evidence, implementation, and policy. `try!` may be syntactically observable; actor reentrancy requires isolation/control-flow/data-flow; CI toolchain pinning requires project/external configuration; systematic Instruments usage cannot be proven from ordinary source. R2 preserves these distinctions rather than forcing every item into SwiftSyntax.

R2 remains local-first, fast, deterministic where possible, and CI-suitable. Expensive capabilities execute only when active rules require them. Missing evidence never becomes negative evidence. The capability vocabulary is forward-compatible with R3 but R3 is not required.

## 2. Target User
### 2.1 Jobs To Be Done
- Audit a repository against all 100 claims without confusing unobservable claims with clean code.
- Understand evidence supporting each Detection.
- Add a rule without inventing a new execution architecture.
- Know which claims are Supported, Partial, Research, External/Runtime Required, or Not Reliably Observable.
- Execute only capabilities required by enabled rules.
- Consume typed observations without parsing prose.

### 2.2 Non-Users
R2 is not an LLM reviewer, automatic refactoring engine, runtime profiler, replacement for Instruments/Thread Sanitizer, CI provider, or architecture visualization product. It may model claims from those domains but cannot fabricate evidence. Automatic remediation and repository chat are out of scope.

### 2.3 Key User Journeys
**UJ-1 — Bruno audits the catalog.** He runs SwiftDebt and receives evaluated, partial, unavailable, failed, disabled, and detected states separately. The value moment is distinguishing “no detection” from “could not observe.” Capability failure only makes dependent rules incomplete.

**UJ-2 — Maya implements actor-reentrancy detection.** She starts from an existing Research Claim, sees required isolation/control-flow/data-flow evidence, implements/reuses analyzers, adds positive/adversarial fixtures, and promotes Support State only after the Evidence Contract passes.

**UJ-3 — Renata diagnoses CI cost.** She inspects active Rule Requirements, identifies which rule requested expensive analysis, changes scope/configuration, and verifies unrelated capabilities no longer execute.

**UJ-4 — Alex consumes results programmatically.** Stable Rule Identity, Observation State, Detection Mode, typed Evidence, and snapshot provenance let automation distinguish detections from unavailable observations.

## 3. Glossary
- **Research Claim**: One characteristic from the 100-item research set; not automatically executable.
- **Rule Definition**: Stable definition containing identity, category, scope, requirements, Evidence Contract, revisions, and Support State.
- **Rule Implementation**: Executable logic evaluating a Rule Definition.
- **Rule Catalog**: Canonical collection of Rule Definitions.
- **Rule Identity**: Stable semantic identifier; research numbering is provenance.
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

## 4. Features
### 4.1 Canonical Rule Catalog
The Rule Catalog is the source of truth for what SwiftDebt understands. It contains all Research Claims even when implementation is absent, partial, external, or not reliably observable. Stable IDs prevent list order or Swift type names becoming identity. Provenance links definitions to research. This realizes UJ-1/UJ-2.

**FR-1 — Catalog all research claims.** All 100 items are traceable to catalog entries or explicit decompositions; none is silently dropped; provenance is queryable.

**FR-2 — Stable Rule Identity.** Identity is independent of list order, source file, and implementation type; duplicates are rejected.

**FR-3 — Explicit Support State.** Every definition exposes maturity; implementation existence alone cannot imply Supported.

### 4.2 Capability-Aware Requirements
Rules declare what must be observable. Requirements describe capabilities, not concrete analyzers. Cheap rules stay cheap; advanced capabilities remain demand-driven.

**FR-4 — Declare Analysis Capabilities.** Requirements can include syntax, symbols, types, references, ownership, isolation, control flow, data flow, project/build, history, semantic similarity, runtime, and external evidence.

**FR-5 — Resolve shared requirements.** SwiftDebt computes union/dependency closure for enabled rules; disabled rules contribute nothing; the set is inspectable.

**FR-6 — Avoid unrelated work.** Syntax-only configurations initialize no semantic/history/CI subsystem; removing the last consumer removes that work.

### 4.3 Evidence Contracts
Evidence is first-class, typed, and snapshot-local. Rule Definitions declare sufficient evidence; Detections retain evidence for explanation. Opaque confidence is not evidence.

**FR-7 — Evidence Contract.** Required/optional evidence and valid conjunction/disjunction can be declared; unavailable required evidence prevents complete evaluation.

**FR-8 — Typed Evidence.** Reporters and tools interpret evidence without parsing messages; Evidence never owns Finding identity.

**FR-9 — Explain Detection.** Explanations distinguish observed facts, derived evidence, and rule conclusion.

### 4.4 Honest Observability
“No Detection” means verified absence only when observation is sufficient.

**FR-10 — Observation State.** Reports distinguish Complete, Partial, Unavailable, Failed, and Disabled.

**FR-11 — Snapshot completeness.** Capability failures make dependent rules incomplete; reconciliation cannot infer resolution from insufficient observation.

**FR-12 — External/runtime honesty.** Such claims remain cataloged without fabricated static detectors and can later gain providers without changing identity.

### 4.5 Scope-Aware Evaluation
Research spans source, repository, project/build, history, runtime, and external systems.

**FR-13 — Declare Rule Scope.** Definitions state evaluation scope; implementations cannot silently require broader scope.

**FR-14 — Multiple Analysis Contexts.** Rules receive scope-appropriate context; project rules do not fabricate meaningless syntax nodes.

### 4.6 Detection Modes
**FR-15 — Declare Detection Mode.** Executable rules identify deterministic/derived/heuristic/historical/runtime/external mode.

**FR-16 — No fabricated confidence.** Similarity values may be evidence but not probability unless a calibrated model exists.

### 4.7 Policy Separation
**FR-17 — Consequence outside Rule Definition.** Policy can warn/fail differently by scope; policy changes do not alter Semantic Revision; implementations do not enforce consequences.

### 4.8 Coverage Reporting
**FR-18 — Coverage report.** Group catalog by Support State, category, scope, and Detection Mode.

**FR-19 — Rule inspection.** Expose provenance, requirements, Evidence Contract, revisions, and implementation state.

**FR-20 — Catalog validation.** Reject duplicate IDs, invalid capability references, inconsistent maturity, missing provenance, and incompatible evidence metadata.

## 5. Non-Goals
- Guarantee executable static detection for all 100 claims.
- Treat missing runtime/external evidence as clean code.
- Make vector similarity authoritative.
- Automatic fixes/source mutation.
- Replace Instruments, TSan, compiler diagnostics, CI, or security scanners.
- Make severity intrinsic to rules.
- Universal debt/quality score.
- Require R3 for source-local rules.

## 6. MVP Scope
### 6.1 In Scope
All 100 claims cataloged; stable identity/provenance; Support State; Rule Scope; Detection Mode; capability vocabulary; Evidence Contract; typed Evidence; Observation State; completeness propagation; source-local plus one broader scope contract; coverage APIs/CLI; R1 compatibility; representative Deterministic/Derived implementations; selective capability resolution.

### 6.2 Out of Scope
Full implementation of all claims; R3 RepositoryGraph/EvidenceGraph; remediation; IDE GUI; cloud analysis; LLM inference; full CI-provider integrations; runtime profiler; architecture visualization.

## 7. Success Metrics
**SM-1 — Catalog completeness:** 100% of source claims traceable to entries/decompositions. Validates FR-1/FR-20.  
**SM-2 — Honest observability:** 100% of active rules with unavailable required capability are non-complete, never verified absence. Validates FR-10/FR-11/FR-12.  
**SM-3 — Explainability:** 100% of Supported rules satisfy Evidence Contract and explain without string parsing. Validates FR-7/FR-8/FR-9.  
**SM-4 — Capability selectivity:** syntax-only benchmarks execute zero unrelated semantic/history/external capabilities. Validates FR-5/FR-6.  
**SM-5 — Catalog integrity:** invalid identity/capability/evidence fixtures are rejected. Validates FR-2/FR-20.  
**SM-6 — Mode coverage:** validated Deterministic and Derived examples plus cataloged External/Runtime claims. Validates FR-12/FR-15.

**SM-C1:** Do not inflate Supported count by weakening Evidence Contracts.  
**SM-C2:** Do not optimize capability richness by executing every analyzer.  
**SM-C3:** Do not optimize numeric confidence theater.

## 8. Cross-Cutting NFRs and Impact
Performance requires lazy capability execution and separate baselines for syntax-only and derived workloads. Deterministic rules must be materially reproducible for equivalent inputs/configuration/revisions. Default analysis remains local; cataloging external claims does not authorize transmission. Capability/cache failures degrade Observation State rather than fabricate absence. New capabilities must not change existing Rule Identity. Supported rules must expose testable evidence.

R2 depends on R1 Rule/Detection/Reconciler/Finding/AnalysisSnapshot/Policy separation. SwiftSyntax remains the main source sensor, while advanced capabilities may use specialized providers. Rule authoring changes substantially because metadata, observability, and Evidence Contracts become first-class. Reporters and machine schemas evolve to expose Observation State and Evidence. Future R3 can consume the same requirements for a richer planner.

## 9. Open Questions
1. Can one Research Claim decompose into multiple Rule Definitions, and under what governance?
2. Which Support State names belong in public API?
3. What minimum Evidence Contract promotes Partial to Supported?
4. Which capabilities are public versus internal?
5. How do project-level Detections represent location?
6. Are runtime/external provider protocols R2 or deferred?
7. How do generated/test/vendor sources affect scope/policy?
8. What control/data-flow implementation is sufficient for actor reentrancy?
9. Is catalog authored in Swift, YAML, generated Swift, or hybrid?
10. How does Evidence Revision compatibility work without Semantic Revision changes?
11. Which claims form the implementation acceptance corpus beyond catalog completeness?
12. Is catalog validation compile-time, startup-time, or both?

## 10. Assumptions Index
- [ASSUMPTION] R1 authority boundaries remain prerequisites.
- [ASSUMPTION] The supplied 100-item research set is the initial catalog baseline.
- [ASSUMPTION] Some claims are inherently external/runtime or not reliably observable.
- [ASSUMPTION] Capability selectivity is required for acceptable performance.
- [ASSUMPTION] R3 will reuse, not replace, R2 capability semantics.
