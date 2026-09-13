---
type: Static Analysis Component
title: Swift functional evidence extraction
description: SCMASyntax extracts syntax-level side-effect and functional-composition facts, and SCMACore converts them into deterministic debt evidence.
resource: Sources/SCMASyntax/EffectVisitor.swift
tags: [swift, debt-analysis, syntax, side-effects, functional-composition]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`EffectVisitor` scans SwiftSyntax function bodies for syntax-level side-effect markers and functional-composition calls. The parser attaches the collected facts to each `FunctionFacts` value, and `DebtFunctionalEvidenceBuilder` turns valid parsed sources into deterministic `DebtEvidence` entries.

# Captured facts

`SyntaxEffectFact` records a `SyntaxEffectCategory`, detail text, source location, confidence, and whether the effect was found inside a closure. Categories cover mutation, inout mutation, property writes, global or static state, async effects, throwing effects, and closure effects.

`FunctionalCompositionFact` records recognized operations such as `map`, `compactMap`, `filter`, `reduce`, `flatMap`, and `sorted`, along with the source location, whether a closure appears effectful, and confidence.

# Evidence generation

`DebtFunctionalEvidenceBuilder` emits `swift.side-effect.<category>` evidence for grouped side-effect facts, `swift.purity.heuristic` evidence when no recognized effects are present, `swift.functional-composition` evidence for composition facts, and `swift.pattern-consistency.heuristic` evidence derived from deterministic syntax counts.

The generated notes state that syntax findings and heuristic purity or pattern consistency are not compiler semantic proof.

# Verification coverage

`FunctionalEvidenceTests` covers fixtures for each side-effect category, benign functional composition that does not become side-effect evidence, explanatory heuristic notes, and deterministic evidence and score output when functions are reordered.

# Citations

[1] [EffectVisitor.swift](../../Sources/SCMASyntax/EffectVisitor.swift)
[2] [SwiftSyntaxParser.swift](../../Sources/SCMASyntax/SwiftSyntaxParser.swift)
[3] [Models.swift](../../Sources/SCMACore/Models.swift)
[4] [DebtFunctionalEvidence.swift](../../Sources/SCMACore/DebtFunctionalEvidence.swift)
[5] [FunctionalEvidenceTests.swift](../../Tests/SCMASyntaxTests/FunctionalEvidenceTests.swift)
