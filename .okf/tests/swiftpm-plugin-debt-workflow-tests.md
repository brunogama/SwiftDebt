---
type: Test Coverage
title: SwiftPM plugin debt workflow tests
description: Swift Testing coverage verifies SwiftPM command and build plugin debt workflows, unavailable evidence propagation, Markdown output, Debtmap projection scores, generated stamps, and validation failures.
resource: Tests/SwiftDebtKitTests/PluginWorkflowTests.swift
tags: [swift, swiftpm, plugins, debt-analysis, tests]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`PluginWorkflowTests` creates a temporary package that depends on SwiftDebt by local path and attaches `SwiftDebtBuildPlugin` to a demo target. The test runs `swift package swift-debt debt analyze --target Demo` through the command plugin and `swift build` through the build plugin.

The implementation range `d39b2a62d59a26a167b0718b38416c6e601498a0..fb33b630f3244effe4676a9be1e2288a6735d9dd` extends this coverage so plugin-mode debt analysis verifies item-level score presence, unavailable LCOV evidence caused by the SwiftPM plugin context, unavailable Git history evidence caused by the temporary non-repository package, and omission of LCOV score contributions when coverage is unavailable.

# Output formats

The tests now exercise Markdown output from the command plugin and assert that the report heading, missing-evidence section, and `coverage.lcov` entry are rendered. The Debtmap compatibility projection is decoded and its first item score is checked against the native JSON report item score, while projection-level missing evidence still includes LCOV and Git history unavailability.

# Build plugin validation

The build plugin path still asserts a single generated `SwiftDebt.analysis.swift` stamp after a successful build. With `debtValidation.maxScore` set to `0`, the same plugin consumer is expected to fail `swift build` with an `SwiftDebt [DEBT]` diagnostic.

# Citations

[1] [PluginWorkflowTests.swift](../../Tests/SwiftDebtKitTests/PluginWorkflowTests.swift)
