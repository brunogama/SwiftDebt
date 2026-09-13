---
type: Core Capability
title: Ranked debt analysis composition
description: SCMACore and SCMAKit compose structural, functional, coverage, Git history, and dependency evidence into deterministic ranked debt analysis results.
resource: Sources/SCMACore/RankedDebtAnalysis.swift
tags: [swift, debt-analysis, ranking, evidence, scmakit]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`DebtAnalysisOptions` configures ranked debt analysis with a `strict`, `balanced`, or `lenient` preset, an aggregation strategy of `none`, `file`, or `aggregateOnly`, optional minimum score and priority filters, category and level filters, head, top, and tail limits, a problematic-item threshold, and a scoring policy.

`DebtAnalysisBuilder` scores each `DebtItem`, assigns a category from the first evidence kind prefix, builds an explanation from the strongest normalized evidence, adds a recommendation, applies filters and limits, and returns a `RankedDebtAnalysis` containing ranked items, file aggregations, compact items, and summary counts.

# Evidence composition

`MetricsCalculator` enriches structural debt items with functional evidence from `DebtFunctionalEvidenceBuilder` and dependency evidence from dependency contexts before returning analysis metrics.

`AnalysisService` creates ranked debt analysis only when request or workspace configuration supplies debt analysis options. It composes report debt items with LCOV coverage evidence when an LCOV path is configured, Git history evidence from the repository root and reference time, and unavailable evidence records when coverage or Git history providers cannot provide evidence.

# Configuration surface

`WorkspaceConfiguration` decodes `debtAnalysis` and `lcovPath`. Relative LCOV paths must be nonempty paths without parent-directory traversal or glob metacharacters; request-level absolute LCOV paths are permitted.

`AnalysisRequest` carries optional debt analysis options, LCOV path, and debt reference time. `AnalysisRunResult` carries an optional `rankedDebtAnalysis` while preserving existing report rendering behavior when ranked debt analysis is not requested.

# Determinism and aggregation

Ranked output sorts scored items by descending score, then priority rank, then debt item ID. File aggregations collect problematic scored items by file path and score the merged evidence for each file. Compact items expose ID, display name, level, score, priority, and location for bounded downstream consumption.

# Citations

[1] [RankedDebtAnalysis.swift](../../Sources/SCMACore/RankedDebtAnalysis.swift)
[2] [DebtAnalysisBuilder.swift](../../Sources/SCMACore/DebtAnalysisBuilder.swift)
[3] [MetricsCalculator.swift](../../Sources/SCMACore/MetricsCalculator.swift)
[4] [AnalysisService.swift](../../Sources/SCMAKit/AnalysisService.swift)
[5] [WorkspaceConfiguration.swift](../../Sources/SCMAKit/WorkspaceConfiguration.swift)
