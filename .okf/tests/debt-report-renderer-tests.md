---
type: Test Coverage
title: Debt report renderer tests
description: Swift Testing coverage verifies deterministic native debt reports, Debtmap compatibility projection output, DOT rendering, text renderers, and service-level debt JSON rendering.
resource: Tests/SwiftDebtKitTests/DebtReportRendererTests.swift
tags: [swift, testing, debt-analysis, reporting]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`DebtReportRendererTests` builds a ranked debt analysis fixture with two callable items, one file aggregation, unavailable coverage evidence, and a small Swift dependency graph.

The tests render `debt-json`, `debt-markdown`, `debt-dot`, `debt-text`, `debt-compact`, and `debtmap-json`. The JSON outputs are decoded back into `DebtReport` and `DebtmapCompatibilityProjection` to assert schema version, report kind, projection metadata, missing evidence, and deterministic item order.

# Golden fixtures

Golden fixtures under `Tests/SwiftDebtKitTests/Fixtures/DebtReport/` lock the canonical native JSON report, Markdown report, DOT graph, plain text report, compact text report, and Debtmap compatibility JSON projection.

A shuffled fixture test renders the same formats from differently ordered input and compares every output to the canonical fixtures. This verifies that the projection builder and renderers do not leak source collection order into reports.

# Service-level behavior

The service-level test runs `AnalysisService` with `format: .debtJSON`, debt analysis options, and a missing LCOV path. It decodes standard output as a `DebtReport` and asserts the current schema version, native report kind, top-item bounding, and recorded missing evidence.

# Citations

[1] [DebtReportRendererTests.swift](../../Tests/SwiftDebtKitTests/DebtReportRendererTests.swift)
[2] [canonical-debt-report.golden.json](../../Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json)
[3] [canonical-debt-report.golden.md](../../Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-report.golden.md)
[4] [canonical-debt-graph.golden.dot](../../Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-graph.golden.dot)
[5] [canonical-debt-plain.golden.txt](../../Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-plain.golden.txt)
[6] [canonical-debt-compact.golden.txt](../../Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-compact.golden.txt)
[7] [canonical-debtmap-projection.golden.json](../../Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debtmap-projection.golden.json)
