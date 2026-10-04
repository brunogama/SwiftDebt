---
title: R2 Rule Catalog source, ownership, and provenance
status: accepted
date: 2026-10-04
---

# ADR 0002: One Swift-authored, source-backed Rule Catalog

---

## Context

The draft [R2 Rule Catalog and Evidence PRD](../SwiftDebt_R2_Rule_Catalog_Evidence_PRD/prd.md) and the old branch's [accepted R2 open-questions ADR](../SwiftDebt_R2_Rule_Catalog_Evidence_PRD/archived-adr-0001-r2-open-questions.md) presumed an authoritative numbered set of 100 research claims. The draft, its ZIP, repository history, and source search did not yield that set. The old branch has a YAML manifest and parser, but only three sample entries. Its numbered examples also disagree: item 12 is both a long-method placeholder and an async semaphore claim. Neither number nor manifest is a defensible catalog source.

Current `main` already publishes 24 second-edition Fowler smells through `RefactoringCodeSmellCatalog` and a versioned report, as well as Swift-specific built-in rules, `AnalysisReport` schema 2, lifecycle reconciliation, and the compiler-evidence sidecar. The old branch diverged before several of these releases. Merging it wholesale would replace public behavior.

The publisher's [*Refactoring*, second-edition table of contents](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) supplies the 24 named Chapter 3 smells. It does not endorse Swift-specific debt judgments. Swift and tooling documentation may substantiate language and tool behavior but does not, by itself, establish that a pattern is debt.

---

## Decision

1. **Use one authoritative Swift-authored catalog.** The canonical registry is typed Swift, rooted in current main's Fowler catalog and rule identity system. Definitions declare identity, provenance, scope, observation requirements, evidence, and support state. A rule implementation observes; the engine reconciles; policy decides consequences. Do not port the old YAML manifest, parser, validator plugin, or a second authored list of rule definitions. The published 24-smell catalog/report remains an adapter over canonical definitions, not another source of truth.
2. **Track provenance in two explicit partitions.** Every one of the 24 named Fowler smells has one stable canonical identity and a publisher-backed source claim. Every distinct SwiftDebt-authored extension has a rationale and primary citations for factual Swift/tooling premises; its normative debt judgment is labeled project-authored. First compare a proposed Swift example to the Fowler claims. If it instantiates an existing smell, map it to that identity instead of adding a duplicate extension. An external or runtime-dependent claim may be listed as unsupported or unavailable without pretending to have a static detector.
3. **Measure the partitions separately.** Fowler coverage uses the verified fixed denominator 24. Extension coverage uses the set of accepted, individually recorded SwiftDebt-authored entries; the draft examples are candidates, not a predeclared count. Do not report 100-item completeness, convert missing evidence into clean absence, or count a rule as supported until its evidence contract and positive/adversarial verification are real.
4. **Preserve existing public contracts.** `RefactoringCodeSmellCatalogReport` schema 1 keeps its existing ordered 24-entry serialization and meaning. `AnalysisReport` schema 2, current CLI behavior, lifecycle identity/reconciliation, and the [compiler-evidence sidecar ADR](0001-compiler-evidence-sidecar-boundary.md) stay authoritative. Add a separately versioned view if the wider registry needs a public serialization; do not silently change either old report. Reuse main's `RuleIdentity`, `SemanticRevision`, and evidence models. Main's `RuleDescriptor` and its R1 `defaultSeverity` remain an execution compatibility projection from accepted supported definitions; they are not a second authored catalog or a universal severity contract. Existing concrete `AnalysisContext` and `DebtRule` remain source-rule interfaces until a broader concrete context is implemented. Do not copy same-named old-branch types or marker-only protocols.
5. **Port selectively.** Reuse only domain, capability, evidence, observation, and validation ideas or code that pass tests against current main. The old branch's marker-only analysis contexts and unregistered rule conformers are not finished detectors. Capabilities are demand-driven and failures are observable, not negative evidence.
6. **Replace the YAML-specific validation path.** Swift types provide compile-time shape checks; deterministic registry validation in the test/build gate rejects duplicate identity, invalid capability/evidence contracts, inconsistent support state, and missing provenance. At runtime, configuration-dependent validation still runs. An offending rule becomes Disabled with an inspectable reason and never establishes clean absence; unrelated rules continue. This supersedes the archived ADR's Q12 YAML-to-Swift codegen mechanism, not its fail-closed observation boundary.

---

## Supersession and consequences

This decision supersedes the unverified 100-item source/numbering premise in the draft PRD and archived ADR, and the archived ADR's Q9 catalog-authoring choice favoring a YAML manifest plus its Q12 YAML code-generation validator. Q12's runtime fail-closed and per-rule Disabled behavior remains required. The remaining capability, evidence, observation, lifecycle, and policy boundaries in that ADR remain design input unless they conflict with current main's released contracts. Main's ADR 0001 is unrelated and is **not** superseded.

A source claim does not automatically become a supported detector. Full R2 completion requires a traceability matrix for every revised PRD requirement, real end-to-end evidence, validation of identity/provenance and support state, unchanged legacy serialization, and actual offline tests. A green type layer or a catalog entry alone is not a passed acceptance gate. The original source search and three compared design options are retained with the PRD for audit.
