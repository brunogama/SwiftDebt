---
type: Test Coverage
title: Debt dashboard renderer tests
description: Swift Testing coverage verifies deterministic self-contained debt dashboard HTML, local report loading controls, comparison behavior, filtering, and schema validation.
resource: Tests/SCMAKitTests/DebtDashboardRendererTests.swift
tags: [swift, testing, debt-analysis, reporting, dashboard]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`DebtDashboardRendererTests` renders the canonical debt-report fixture through both JSON data and decoded `DebtReport` entry points. The output must match the canonical `canonical-debt-dashboard.golden.html` fixture and contain the SwiftSCMA debt dashboard marker and native debt-report kind.

The tests assert that the HTML remains self-contained: it includes embedded report JSON, file inputs for replacement and comparison reports, priority, category, level, and query filters, a Content Security Policy, no network URLs, no external script tags, and no stylesheet links.

# Browser behavior

JavaScriptCore-based tests exercise the dashboard script without rerunning analysis. They validate file-selected report loading, comparison report rendering, filtering controls, search behavior, keyboard shortcuts, summary rendering, drilldown output, aggregation graph rendering, empty graph messaging, schema validation errors, and unsupported schema or report-kind rejection.

# Golden fixtures

`canonical-debt-dashboard.golden.html` locks the deterministic dashboard output for the canonical debt report fixture.

# Citations

[1] [DebtDashboardRendererTests.swift](../../Tests/SCMAKitTests/DebtDashboardRendererTests.swift)
[2] [canonical-debt-dashboard.golden.html](../../Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-dashboard.golden.html)
[3] [canonical-debt-report.golden.json](../../Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json)
