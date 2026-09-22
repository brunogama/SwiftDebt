---
type: Domain Model
title: Debt analysis domain model and deterministic scoring
description: SwiftDebtCore models debt entities, evidence, aggregations, scoring policies, deterministic weighted scoring, and priority classification.
resource: Sources/SwiftDebtCore/DebtModels.swift
tags: [swift, debt-analysis, scoring, scmacore]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`SwiftDebtCore` defines debt analysis as `Codable`, `Sendable` value types for entities, evidence, aggregations, score contributions, unavailable evidence, score breakdowns, scores, syntax effects, Swift risk facts, and functional-composition facts.

`DebtAggregationLevel` supports `callable`, `type`, `file`, and `module` scopes. `DebtLocation` records optional module, file, line, and column coordinates, including an initializer from `SourceLocation`. `DebtEntity` identifies the scored entity, `DebtItem` pairs an entity with evidence, and `DebtAggregation` groups member item IDs with an optional `DebtScore`.

# Evidence model

`DebtEvidence` records an evidence ID, kind, requirement, availability, configured weight, optional normalized score, raw value, optional location, and optional note.

`DebtEvidenceRequirement` distinguishes `required` from `optional` evidence. `DebtEvidenceAvailability` records `available` or `unavailable` state plus an optional reason, exposes `.available`, `.unavailable(reason:)`, and `isAvailable`.

`SwiftRiskCategory` enumerates Swift-specific risk categories including isolation crossings, actor and global actor isolation, Sendable declarations, unchecked Sendable, unstructured tasks, nonisolated declarations, mutable shared state, and unsafe escape hatches. `FunctionFacts` carries optional access level and per-function risk facts, and `ParsedSource` carries file-level risk facts.

# Scoring model

`DebtScoring` sorts evidence deterministically before scoring. Optional unavailable evidence is excluded and remaining available evidence is renormalized by positive weight. Required unavailable evidence, missing normalized scores, non-positive weights, or no available weight withhold the composite score by returning `nil` value and priority while preserving breakdown details.

Available normalized scores are clamped to `0...100`; clamping is reflected in contribution notes. Contributions preserve evidence ID, kind, raw value, normalized score, configured weight, effective weight, contribution, and note.

# Priority classification

`PriorityThresholds` defaults to medium `40`, high `70`, and critical `85`. Classification returns low below medium, medium at or above `40`, high at or above `70`, and critical at or above `85`.

# Verification coverage

`DebtScoringTests` covers import-free SwiftDebtCore sources, no ambient clock or mutable shared state in debt scoring sources, optional evidence renormalization, required evidence withholding, deterministic ordering, priority boundaries, explanation preservation, input clamping, separation from `PaperScoring`, and aggregation contracts for callable, type, file, and module scopes.

# Citations

[1] [DebtModels.swift](../../Sources/SwiftDebtCore/DebtModels.swift)
[2] [DebtScoreModels.swift](../../Sources/SwiftDebtCore/DebtScoreModels.swift)
[3] [DebtScoring.swift](../../Sources/SwiftDebtCore/DebtScoring.swift)
[4] [Models.swift](../../Sources/SwiftDebtCore/Models.swift)
[5] [DebtScoringTests.swift](../../Tests/SwiftDebtCoreTests/DebtScoringTests.swift)
