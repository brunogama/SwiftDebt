---
type: Test Coverage
title: Ranked debt analysis composition tests
description: Swift Testing coverage verifies deterministic ranked debt analysis composition, provider evidence, unavailable evidence, filters, aggregation, and configuration activation.
resource: Tests/SCMAKitTests/RankedDebtAnalysisTests.swift
tags: [swift-testing, debt-analysis, ranking, scmakit]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`RankedDebtAnalysisTests` exercises the SCMAKit service path that produces ranked debt analysis from a temporary Git repository, Swift source, LCOV coverage data, Git history, functional evidence, and dependency evidence.

The tests assert stable repeated output, nonempty ranked items and file aggregations, nonempty score contribution breakdowns, available Git history evidence, available LCOV coverage evidence, and Swift functional evidence with side-effect or API-risk kinds.

# Provider unavailability

Coverage-provider failure and a non-Git workspace are represented as unavailable evidence, not fabricated zero-risk evidence. The tests assert unavailable coverage and Git history evidence have configured weights and that the summary unavailable-evidence count matches the scored breakdown.

# Ranking options

The tests cover deterministic filtering by minimum priority and category, disabled aggregation, aggregate-only output, problematic-item aggregation thresholds, tail limiting, configuration-driven preset activation, and the legacy report path where ranked debt analysis remains absent when no debt options are requested.

# Citations

[1] [RankedDebtAnalysisTests.swift](../../Tests/SCMAKitTests/RankedDebtAnalysisTests.swift)
