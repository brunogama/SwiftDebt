---
type: Core Capability
title: Interactive browser debt dashboard
description: SwiftSCMA renders ranked debt analysis as a self-contained browser dashboard over the native debt-report schema.
resource: Sources/SCMAReporting/DebtDashboardRenderer.swift
tags: [swift, debt-analysis, reporting, dashboard]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`ReportFormat` includes `debt-dashboard` as a ranked debt analysis format. Like the other debt formats, it is rejected by the standard report renderer when ranked debt analysis results are not available.

`ReportRenderer.renderDebt` renders `debt-dashboard` from the native `DebtReport` projection. `DebtDashboardRenderer` can also render from encoded debt-report JSON by decoding `DebtReport` before building the dashboard.

# Dashboard contract

The dashboard accepts only the current `DebtReport` schema version and the `swiftscma-debt-report` report kind. Unsupported schema versions or report kinds raise invalid configuration errors.

The generated HTML is self-contained and embeds the native debt report as sorted, pretty-printed JSON in an `application/json` script tag. Embedded JSON escapes `<`, `>`, and `&` before insertion into the document.

The page includes browser controls for loading another debt report JSON, loading a comparison report JSON, filtering by priority, category, level, and search text, and rendering ranked items, evidence drilldowns, summary cards, aggregation graph edges, and comparison deltas.

# Command-line surface

The README and CLI help list `debt-dashboard` with the other ranked debt analysis formats. The README describes it as a self-contained browser dashboard over the native debt-report schema.

# Citations

[1] [Configuration.swift](../../Sources/SCMACore/Configuration.swift)
[2] [DebtDashboardRenderer.swift](../../Sources/SCMAReporting/DebtDashboardRenderer.swift)
[3] [DebtReportRenderer.swift](../../Sources/SCMAReporting/DebtReportRenderer.swift)
[4] [ReportRenderer.swift](../../Sources/SCMAReporting/ReportRenderer.swift)
[5] [CLIOptions.swift](../../Sources/scma/CLIOptions.swift)
[6] [README.md](../../README.md)
