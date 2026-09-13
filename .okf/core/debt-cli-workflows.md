---
type: Core Capability
title: Debt analyze and validate CLI workflows
description: SwiftSCMA exposes namespaced debt analyze and validate commands with deterministic filtering, formatting, coverage, and score-gate options.
resource: Sources/scma/DebtCLIOptions.swift
tags: [swift, debt-analysis, cli]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

The `scma` executable accepts a `debt` namespace when the next argument is `analyze`, `validate`, help, or a help flag. Other invocations such as an input path named `debt` continue through the existing implicit analyze workflow.

`scma debt analyze` parses debt-specific analysis options and returns the existing `.analyze` action with `enableDebtAnalysis` set. `AnalysisService` now creates default `DebtAnalysisOptions` when debt analysis is enabled without explicit options, so the namespaced debt workflow can produce ranked debt output without requiring configuration-file activation.

# Analyze options

Debt analysis accepts standard input, configuration, output, job, manifest, stamp, exclude, and LCOV options. `--coverage` is an alias for `--lcov` in debt workflows.

Debt-specific filters and bounds include `--preset`, `--aggregation`, `--top`, `--head`, `--tail`, `--min-score`, `--min-priority`, repeatable `--category`, and repeatable `--level`. Supported debt formats include native JSON, Markdown, DOT, text, compact text, and Debtmap compatibility JSON aliases.

# Validate workflow

`scma debt validate` requires `--max-score` and uses compact debt output internally by default. It analyzes ranked debt, computes the worst scored item, and exits with status `0` when no scored item exceeds the threshold or status `1` when any item exceeds it.

Validation exits with status `2` when ranked debt analysis is unavailable. `--quiet` suppresses the validation summary and is only valid for the validate command.

# Citations

[1] [CLIOptions.swift](../../Sources/scma/CLIOptions.swift)
[2] [DebtCLIOptions.swift](../../Sources/scma/DebtCLIOptions.swift)
[3] [DebtValidationOutcome.swift](../../Sources/scma/DebtValidationOutcome.swift)
[4] [SCMACommand.swift](../../Sources/scma/SCMACommand.swift)
[5] [WorkspaceConfiguration.swift](../../Sources/SCMAKit/WorkspaceConfiguration.swift)
[6] [AnalysisService.swift](../../Sources/SCMAKit/AnalysisService.swift)
