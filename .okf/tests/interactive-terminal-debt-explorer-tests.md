---
type: Test Coverage
title: Interactive terminal debt explorer tests
description: Swift Testing coverage verifies deterministic debt explorer reducer behavior, terminal fallback detection, CLI fallback output, and large-result reducer performance.
resource: Tests/SwiftDebtInteractiveTests/DebtExplorerTests.swift
tags: [swift, testing, debt-analysis, terminal]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`DebtExplorerTests` builds ranked debt analysis fixtures and verifies that repeated reducer action sequences produce identical state, visible item IDs, selected item IDs, detail source context, score explanation content, and editor jump commands.

Terminal capability tests cover CI terminals, `TERM=dumb`, and capable TTY environments. Unsafe environments return the fallback report text, while capable environments render the debt explorer header and command help.

# Command fallback

The CLI integration test creates a temporary Swift source file, runs `swift-debt analyze` with `--interactive-debt` and `--format debt-compact`, and verifies that a non-TTY process receives debt compact output rather than the interactive explorer screen.

# Performance budget

The large-result test constructs 12,000 ranked debt items, applies a search query, moves selection 4,000 times, and asserts the reducer remains within a 750 millisecond budget while preserving the full visible result set.

# Citations

[1] [DebtExplorerTests.swift](../../Tests/SwiftDebtInteractiveTests/DebtExplorerTests.swift)
