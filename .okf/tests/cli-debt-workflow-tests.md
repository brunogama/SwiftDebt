---
type: Test Coverage
title: CLI debt workflow subprocess tests
description: Swift Testing coverage verifies deterministic debt analyze output, validation gate exits, argument errors, and preservation of existing analyze forms.
resource: Tests/SwiftDebtKitTests/CLIWorkflowTests.swift
tags: [swift, testing, debt-analysis, cli]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`CLIWorkflowTests` runs the built `swift-debt` executable in subprocesses with `CI=1` and `TERM=dumb`. Each test creates temporary Swift input where needed and captures process status, stdout, and stderr.

The debt analyze test runs `swift-debt debt analyze` twice with JSON output, `--top 2`, `--jobs 1`, and `--coverage coverage.info`. It asserts successful exits, empty stderr, identical stdout, and a decoded `DebtReport` with report kind `swiftdebt-report`.

# Validation assertions

Validation coverage asserts that `swift-debt debt validate --max-score 100` exits `0` and prints a passing summary. It also asserts that `--max-score 0 --quiet` exits `1` with no stdout or stderr.

Invalid debt analyze arguments are covered by `--top nope`, which must exit `2`, write no stdout, and report the invalid integer error on stderr.

# Compatibility assertions

Existing explicit and implicit analyze forms still decode as `AnalysisReport` JSON. A directory named `debt` used as an implicit input path remains an SCMA JSON workflow rather than being mistaken for the debt namespace.

# Citations

[1] [CLIWorkflowTests.swift](../../Tests/SwiftDebtKitTests/CLIWorkflowTests.swift)
