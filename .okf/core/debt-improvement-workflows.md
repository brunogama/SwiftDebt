---
type: Core Capability
title: Debt improvement comparison and validation workflows
description: SwiftDebtCore, SwiftDebtKit, and the swift-debt CLI compare two native debt reports and validate whether total debt score improved by a configured threshold.
resource: Sources/SwiftDebtCore/DebtReportComparator.swift
tags: [swift, debt-analysis, reporting, automation]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`DebtReportComparator` compares two native `DebtReport` values after verifying that both use the current debt report schema version. It matches items and aggregations by ID, computes added, removed, changed, and unchanged groups in sorted order, and returns a schema-versioned `DebtReportComparison`.

The comparison summary records before and after item counts, item change counts, total score delta, unavailable evidence counts, and aggregation change counts. Total score is the sum of item scores, treating missing scores as zero.

# Change model

`DebtReportComparisonModels` defines the JSON-compatible comparison schema. Added and removed items use `DebtReportItemSnapshot`; changed items include movement, before and after locations, score delta, priority delta, evidence ID delta, and unavailable evidence ID delta.

Aggregation changes use `DebtReportAggregationSnapshot` and `DebtReportChangedAggregation`, including member item ID deltas. Missing evidence is compared as sorted `itemID:evidenceID` pairs.

# Service workflow

`DebtImprovementService.compare` loads the before and after debt report JSON files, produces the comparison, and renders pretty-printed sorted-key JSON. It writes to `--output` when requested or returns the JSON on standard output.

`DebtImprovementService.validateImprovement` computes observed improvement as `beforeTotalScore - afterTotalScore`, compares it with the nonnegative minimum improvement threshold, and renders a `DebtImprovementValidation` JSON result. It returns exit status `0` when the improvement gate passes and `1` when it fails.

Both service workflows refuse to overwrite an input report or a Swift source file when writing output.

# Command-line surface

The `swift-debt` executable supports `compare BEFORE_JSON AFTER_JSON [--output PATH]` and `validate-improvement BEFORE_JSON AFTER_JSON [--threshold SCORE] [--output PATH]`. The CLI parser validates arity, duplicate valued options, unknown options, and nonnegative numeric thresholds.

The command dispatcher exits with the service-provided status for compare and validation workflows. CLI help documents the new commands and notes that exit status `1` can represent an opted-in improvement gate failure.

# Citations

[1] [DebtReportComparator.swift](../../Sources/SwiftDebtCore/DebtReportComparator.swift)
[2] [DebtReportComparisonModels.swift](../../Sources/SwiftDebtCore/DebtReportComparisonModels.swift)
[3] [DebtImprovementService.swift](../../Sources/SwiftDebtKit/DebtImprovementService.swift)
[4] [CLIOptions.swift](../../Sources/swift-debt/CLIOptions.swift)
[5] [SwiftDebtCommand.swift](../../Sources/swift-debt/SwiftDebtCommand.swift)
