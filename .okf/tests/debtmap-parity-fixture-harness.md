---
type: Test Harness
title: Debtmap parity fixture harness
description: Swift Testing coverage validates the debtmap parity matrix, release acceptance evidence, golden fixture determinism, and benchmark methodology metadata.
resource: Tests/SwiftDebtKitTests/DebtmapParityFixtureTests.swift
tags: [swift-testing, debtmap, parity, fixtures]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`DebtmapParityFixtureTests` validates that the debtmap parity matrix declares debtmap version `0.23.0`, matrix schema version `1`, the expected statuses, non-empty status definitions, and the validation test filter `DebtmapParityFixtureTests.parityMatrixRequiresProofForEveryInScopeCapability`.

Release acceptance coverage requires every in-scope parity matrix capability to be implemented, to carry an executable test proof, and to avoid ticket references as release proof. Intentional divergences must cite [Debtmap release-quality acceptance](/core/debtmap-release-quality-acceptance.md).

The golden debtmap parity fixture is asserted to use schema version `1`, generated time `2026-09-12T00:00:00Z`, and the same Git history reference time. The test captures JSON, Markdown, DOT, and CLI render output twice from the same fixture and expects matching outputs, then compares shuffled fixture rendering to the canonical JSON and CLI outputs.

Benchmark methodology coverage distinguishes the frozen input provenance commit `b0ae66be2065084b29b8b5da0a86d5cd049feced` from the capability-equivalent performance reference commit, checks schema version `2`, output directory `.swift-debt/benchmarks/debtmap-baseline`, the `wall-clock-seconds` and `peak-memory-bytes` measurements, one warmup run, fifteen measured runs, non-empty methodology entries, and non-empty command arguments.

# Fixture model fields

`DebtmapParityFixtures.swift` decodes the additional fields required by these assertions: `matrixSchemaVersion`, `statusDefinition`, `validation.testFilter`, capability `implementationState`, proof `kind`, release gate evidence, benchmark `schemaVersion`, `outputDirectory`, `methodology`, and benchmark input `sha256`.

# Integrity checks

For each benchmark input, the harness reads the referenced file and checks byte count, line count, and SHA-256 digest against the metadata.

Release gate evidence checks require schema version `2`, passing `swift build --build-tests && swift test`, passing plugin smoke-test execution, passing baseline and full-evidence performance budgets, zero exit statuses, observed timestamps, and pass summaries. Full-evidence artifacts must contain measured LCOV evidence and available Git-history evidence for both analyzers.

# Citations

[1] [DebtmapParityFixtureTests.swift](../../Tests/SwiftDebtKitTests/DebtmapParityFixtureTests.swift)
[2] [DebtmapParityFixtures.swift](../../Tests/SwiftDebtKitTests/DebtmapParityFixtures.swift)
