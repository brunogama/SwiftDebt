---
type: Core Capability
title: Interactive terminal debt explorer
description: SCMAInteractive renders ranked debt analysis as a terminal debt explorer with deterministic selection, filtering, detail context, and non-TTY fallback behavior.
resource: Sources/SCMAInteractive/TerminalDebtExplorer.swift
tags: [swift, debt-analysis, terminal, interactive]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`SCMAInteractive` is a SwiftPM target that depends on `SCMACore` and is linked into the `scma` executable. It adds an interactive terminal view for ranked debt analysis without changing the native debt report schemas.

`TerminalDebtExplorer.render` detects whether stdin and stdout are TTYs, rejects CI terminals, rejects missing `TERM`, and rejects `TERM=dumb`. When interactive output is unsafe, it returns the already-rendered fallback debt report text with `usedFallback: true` and a reason.

# Explorer state and detail

`DebtExplorerState` stores ranked debt items, visible item IDs, the selected item, the selected visible index, an optional priority filter, and a search query. `DebtExplorerReducer` handles deterministic actions for moving selection, selecting by visible offset or item ID, setting and cycling priority filters, setting search text, and clearing filters.

Search matching covers item ID, display name, file path, category, explanation, recommendation, evidence kind, evidence raw value, and evidence note. Priority cycling moves from all to critical, high, medium, low, then back to all.

`DebtExplorerDetail` derives the selected item's title, source location, priority, formatted score, explanation, recommendation, score explanation, copyable source/context text, and optional editor jump command. Editor jump commands are emitted only when an editor is configured and the debt location has a file.

# Command-line surface

The CLI adds `--interactive-debt` for `analyze`. The option is mutually exclusive with `--output`, requires a debt report format when `--format` is supplied, defaults to `debt-compact` output, and supplies debt analysis options so ranked debt analysis is produced.

`SCMACommand` invokes the terminal explorer only when `--interactive-debt` was requested and the analysis result contains ranked debt analysis. Otherwise it writes the normal analysis standard output.

# Citations

[1] [Package.swift](../../Package.swift)
[2] [DebtExplorerDetail.swift](../../Sources/SCMAInteractive/DebtExplorerDetail.swift)
[3] [DebtExplorerReducer.swift](../../Sources/SCMAInteractive/DebtExplorerReducer.swift)
[4] [TerminalDebtExplorer.swift](../../Sources/SCMAInteractive/TerminalDebtExplorer.swift)
[5] [CLIOptions.swift](../../Sources/scma/CLIOptions.swift)
[6] [SCMACommand.swift](../../Sources/scma/SCMACommand.swift)
