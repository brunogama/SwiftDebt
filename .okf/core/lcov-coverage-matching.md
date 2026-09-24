---
type: Feature
title: LCOV coverage matching and score dampening
description: SwiftDebtCore parses LCOV reports, matches coverage to debt entities, emits coverage diagnostics, and treats coverage as a score dampener.
resource: Sources/SwiftDebtCore/CoverageMatcher.swift
tags: [swift, coverage, lcov, debt-analysis, swiftdebtcore]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`SwiftDebtCore` adds LCOV coverage models, an `LcovParser`, and `CoverageMatcher` to convert LCOV source, function, and executable-line data into optional `DebtEvidence` with kind `coverage.lcov`.

`CoverageMatcher.match(report:entities:repositoryRoot:)` normalizes repository-root-relative paths, sorts inputs deterministically, attempts source-path exact and suffix matching, then matches callable entities by exact function name, function-name suffix, a unique LCOV function definition at the entity start line, or executable line fallback. File, module, and type entities are scored from line coverage in the matched source file.

# Availability and diagnostics

Coverage evidence uses the `DebtEvidenceAvailability.State` values `measuredCoverage`, `zeroCoverage`, `missingFile`, and `unmatchedEntity`; only measured and zero coverage are treated as available evidence.

The matcher returns `CoverageDiagnostic` values for every debt entity and for LCOV records that did not match any entity. `renderDiagnostics(_:)` emits deterministic text that names the subject, availability, confidence, source, matched function when present, attempted strategies, and explanation message.

# Score dampening

`DebtScoring` treats evidence whose kind starts with `coverage.` as a dampener instead of primary weighted evidence. Coverage dampeners use effective weight `0`, cannot increase the base debt score, preserve contribution details, and reduce the score in proportion to normalized coverage when coverage is below full coverage.

# CLI workflow

The `swift-debt explain coverage [path] --lcov PATH [options]` command runs source discovery, configuration and exclusion handling, Swift syntax parsing, LCOV parsing, entity matching, and diagnostic rendering through `CoverageExplanationService`.

# Verification coverage

`CoverageMatchingTests` covers LCOV parsing, source path and function matching, readable and mangled start-line fallback names, zero-hit functions, ambiguous same-line definitions, definitions without hit records, missing-file and unmatched-entity availability, rendered strategy explanations, unmatched LCOV records, and the rule that coverage dampeners cannot increase scores. `AnalyzerTests.coverageExplanationWorkflowReportsMatchingStrategies` covers the end-to-end explanation service path.

# Citations

[1] [CoverageModels.swift](../../Sources/SwiftDebtCore/CoverageModels.swift)
[2] [LcovParser.swift](../../Sources/SwiftDebtCore/LcovParser.swift)
[3] [CoverageMatcher.swift](../../Sources/SwiftDebtCore/CoverageMatcher.swift)
[4] [DebtModels.swift](../../Sources/SwiftDebtCore/DebtModels.swift)
[5] [DebtScoring.swift](../../Sources/SwiftDebtCore/DebtScoring.swift)
[6] [CoverageExplanationService.swift](../../Sources/SwiftDebtKit/CoverageExplanationService.swift)
[7] [CLIOptions.swift](../../Sources/swift-debt/CLIOptions.swift)
[8] [CoverageMatchingTests.swift](../../Tests/SwiftDebtCoreTests/CoverageMatchingTests.swift)
[9] [AnalyzerTests.swift](../../Tests/SwiftDebtKitTests/AnalyzerTests.swift)
