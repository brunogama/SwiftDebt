---
type: Core Capability
title: Debt analyze and validate CLI workflows
description: SwiftDebt exposes namespaced debt analyze and validate commands with deterministic filtering, formatting, coverage, and score-gate options.
resource: Sources/swift-debt/DebtCLIOptions.swift
tags: [swift, debt-analysis, cli]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

The `swift-debt` executable accepts a `debt` namespace when the next argument is `analyze`, `validate`, help, or a help flag. Other invocations such as an input path named `debt` continue through the existing implicit analyze workflow.

`swift-debt debt analyze` parses debt-specific analysis options and returns the existing `.analyze` action with `enableDebtAnalysis` set. `AnalysisService` now creates default `DebtAnalysisOptions` when debt analysis is enabled without explicit options, so the namespaced debt workflow can produce ranked debt output without requiring configuration-file activation.

# Analyze options

Debt analysis accepts standard input, configuration, output, job, manifest, stamp, exclude, and LCOV options. `--coverage` is an alias for `--lcov` in debt workflows.

Debt-specific filters and bounds include `--preset`, `--aggregation`, `--top`, `--head`, `--tail`, `--min-score`, `--min-priority`, repeatable `--category`, and repeatable `--level`. Supported debt formats include native JSON, Markdown, DOT, text, compact text, and Debtmap compatibility JSON aliases.

# Validate workflow

`swift-debt debt validate` requires `--max-score` and uses compact debt output internally by default. It analyzes ranked debt, computes the worst scored item, and exits with status `0` when no scored item exceeds the threshold or status `1` when any item exceeds it.

Validation exits with status `2` when ranked debt analysis is unavailable. `--quiet` suppresses the validation summary and is only valid for the validate command.

# Citations

[1] [CLIOptions.swift](../../Sources/swift-debt/CLIOptions.swift)
[2] [DebtCLIOptions.swift](../../Sources/swift-debt/DebtCLIOptions.swift)
[3] [DebtValidationOutcome.swift](../../Sources/swift-debt/DebtValidationOutcome.swift)
[4] [SwiftDebtCommand.swift](../../Sources/swift-debt/SwiftDebtCommand.swift)
[5] [WorkspaceConfiguration.swift](../../Sources/SwiftDebtKit/WorkspaceConfiguration.swift)
[6] [AnalysisService.swift](../../Sources/SwiftDebtKit/AnalysisService.swift)
