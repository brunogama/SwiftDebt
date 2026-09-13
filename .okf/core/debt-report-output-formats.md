---
type: Core Capability
title: Debt report output formats
description: SwiftSCMA renders ranked debt analysis as native debt JSON, Markdown, DOT, text, compact text, and a Debtmap compatibility JSON projection.
resource: Sources/SCMACore/DebtReport.swift
tags: [swift, debt-analysis, reporting, debtmap]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`ReportFormat` includes debt-specific formats: `debt-json`, `debt-markdown`, `debt-dot`, `debt-text`, `debt-compact`, and `debtmap-json`. The `isDebtReportFormat` helper separates ranked debt output from the existing SCMA-paper report formats.

`AnalysisService` renders debt report formats only when ranked debt analysis is available. Selecting a debt report format without `debtAnalysis` configuration raises an invalid configuration error instead of rendering a non-debt report.

# Native debt schema

`DebtReport` is the native SwiftSCMA debt-report schema. It records schema version, report kind, generator, debt analysis options, summary, ranked items, aggregations, compact items, and missing evidence.

`DebtReportItem` carries ranked item identity, display name, aggregation level, location, category, score, priority, explanation, recommendation, evidence, and score breakdown. `DebtReportAggregation` records deterministic aggregate membership and score facts. `DebtReportMissingEvidence` preserves unavailable evidence identity, requirement, configured weight, and reason.

# Debtmap compatibility projection

`DebtmapCompatibilityProjection` is a deterministic projection for Debtmap-oriented automation, not the native SwiftSCMA debt model. It contains projection metadata, ranked compatibility items, and missing evidence.

Each compatibility item preserves the ranked item ID, entity, level, location, priority, score, sorted evidence kinds, and recommended action.

# Rendered formats

`DebtReportProjectionBuilder` sorts ranked items by descending score, then priority rank, then item ID. It also sorts evidence, score breakdown entries, aggregations, compact items, and missing evidence for deterministic output.

`ReportRenderer.renderDebt` emits:

* `debt-json` as the native `DebtReport` JSON schema.
* `debt-markdown` as a human-readable priority-grouped report.
* `debt-dot` as a deterministic Graphviz dependency graph.
* `debt-text` as a pipe-delimited plain text report.
* `debt-compact` as one compact remediation line per item.
* `debtmap-json` as the Debtmap compatibility projection.

# Command-line surface

The CLI help lists the debt formats alongside the existing report formats. The README distinguishes SCMA-paper formats from ranked debt analysis formats and documents `debtmap-json` as a compatibility projection rather than the native model.

# Citations

[1] [Configuration.swift](../../Sources/SCMACore/Configuration.swift)
[2] [DebtReport.swift](../../Sources/SCMACore/DebtReport.swift)
[3] [DebtReportProjectionBuilder.swift](../../Sources/SCMAReporting/DebtReportProjectionBuilder.swift)
[4] [DebtReportRenderer.swift](../../Sources/SCMAReporting/DebtReportRenderer.swift)
[5] [AnalysisService.swift](../../Sources/SCMAKit/AnalysisService.swift)
[6] [CLIOptions.swift](../../Sources/scma/CLIOptions.swift)
[7] [README.md](../../README.md)
