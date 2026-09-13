---
type: Static Analysis Component
title: Swift functional evidence extraction
description: SCMASyntax extracts syntax-level side-effect, functional-composition, Swift concurrency, and API-risk facts, and SCMACore converts them into deterministic debt evidence.
resource: Sources/SCMASyntax/EffectVisitor.swift
tags: [swift, debt-analysis, syntax, side-effects, functional-composition, concurrency-risk, api-risk]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`EffectVisitor` scans SwiftSyntax function bodies for syntax-level side-effect markers, functional-composition calls, and Swift-specific risk markers. The parser attaches collected facts to `FunctionFacts` values and file-level `ParsedSource` data, and `DebtFunctionalEvidenceBuilder` turns valid parsed sources into deterministic `DebtEvidence` entries.

# Captured facts

`SyntaxEffectFact` records a `SyntaxEffectCategory`, detail text, source location, confidence, and whether the effect was found inside a closure. Categories cover mutation, inout mutation, property writes, global or static state, async effects, throwing effects, and closure effects.

`FunctionalCompositionFact` records recognized operations such as `map`, `compactMap`, `filter`, `reduce`, `flatMap`, and `sorted`, along with the source location, whether a closure appears effectful, and confidence.

`SwiftRiskFact` records Swift concurrency and API risk markers for actor isolation, global actor isolation, Sendable and unchecked Sendable declarations, await isolation crossings, unstructured `Task` creation, nonisolated declarations, mutable shared state, and unsafe escape hatches.

# Evidence generation

`DebtFunctionalEvidenceBuilder` emits `swift.side-effect.<category>` evidence for grouped side-effect facts, `swift.purity.heuristic` evidence when no recognized effects are present, `swift.functional-composition` evidence for composition facts, `swift.pattern-consistency.heuristic` evidence derived from deterministic syntax counts, `swift.concurrency-risk.<category>` or `swift.shared-state.mutable` evidence for grouped Swift risk facts, and API risk evidence for large parameter surfaces and complex public, open, or package callables.

`DebtFunctionalEvidenceOptions` can disable Swift-specific risk evidence while preserving deterministic output.

The generated notes state that syntax findings, Swift-specific risk, and heuristic purity, API-risk, or pattern consistency evidence are not compiler semantic proof.

# Verification coverage

`FunctionalEvidenceTests` covers fixtures for each side-effect and strict-concurrency risk category, benign functional composition that does not become side-effect evidence, explanatory heuristic notes for concurrency and API risk, deterministic evidence and score output when functions are reordered, and deterministic output when Swift-specific risk evidence is disabled.

# Citations

[1] [EffectVisitor.swift](../../Sources/SCMASyntax/EffectVisitor.swift)
[2] [SwiftSyntaxParser.swift](../../Sources/SCMASyntax/SwiftSyntaxParser.swift)
[3] [Models.swift](../../Sources/SCMACore/Models.swift)
[4] [DebtFunctionalEvidence.swift](../../Sources/SCMACore/DebtFunctionalEvidence.swift)
[5] [FunctionalEvidenceTests.swift](../../Tests/SCMASyntaxTests/FunctionalEvidenceTests.swift)
