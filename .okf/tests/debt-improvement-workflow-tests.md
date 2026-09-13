---
type: Test Coverage
title: Debt improvement workflow tests
description: Swift Testing coverage verifies deterministic debt report comparison, schema rejection, validation JSON output, and failing improvement-gate exit status.
resource: Tests/SCMAKitTests/DebtImprovementWorkflowTests.swift
tags: [swift, testing, debt-analysis, automation]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`DebtImprovementWorkflowTests` loads before and after native debt report fixtures and verifies that `DebtReportComparator` renders the committed `comparison.golden.json` deterministically. The test also compares reversed fixture ordering to confirm stable sorted output.

The comparator coverage asserts schema version `1`, current before and after debt report schema versions, expected added, removed, changed, and moved item behavior, removed unavailable evidence, and changed aggregation IDs. It also verifies that an unsupported input debt report schema throws `AnalysisFailure`.

# Validation workflow

Service-level validation tests call `DebtImprovementService.validateImprovement` with passing and failing thresholds. They assert exit statuses `0` and `1` and compare the rendered JSON with `validation-pass.golden.json` and `validation-fail.golden.json`.

Executable-level coverage runs the built `scma` command with `validate-improvement` and a failing threshold. It asserts exit status `1`, exact failing validation JSON on standard output, and empty standard error.

# Fixtures

The fixture set under `Tests/SCMAKitTests/Fixtures/DebtImprovement/` includes before and after debt reports plus golden comparison and validation outputs. The fixture reports exercise added, removed, changed, unchanged, moved, aggregation, unavailable-evidence, and total-score improvement behavior.

# Citations

[1] [DebtImprovementWorkflowTests.swift](../../Tests/SCMAKitTests/DebtImprovementWorkflowTests.swift)
[2] [Debt improvement fixtures](../../Tests/SCMAKitTests/Fixtures/DebtImprovement/)
