---
type: Test Harness
title: Debtmap parity fixture harness
description: Swift Testing coverage validates the debtmap parity matrix, golden fixture determinism, and benchmark methodology metadata.
resource: Tests/SCMAKitTests/DebtmapParityFixtureTests.swift
tags: [swift-testing, debtmap, parity, fixtures]
timestamp: 2026-09-12T00:00:00Z
---

# Overview

`DebtmapParityFixtureTests` validates that the debtmap parity matrix declares debtmap version `0.23.0`, matrix schema version `1`, the expected statuses, non-empty status definitions, and the validation test filter `DebtmapParityFixtureTests.parityMatrixRequiresProofForEveryInScopeCapability`.

The golden debtmap parity fixture is asserted to use schema version `1`, generated time `2026-09-12T00:00:00Z`, and the same Git history reference time. The test captures JSON, Markdown, DOT, and CLI render output twice from the same fixture and expects matching outputs, then compares shuffled fixture rendering to the canonical JSON and CLI outputs.

Benchmark methodology coverage checks baseline commit `b0ae66be2065084b29b8b5da0a86d5cd049feced`, schema version `1`, output directory `.scma/benchmarks/debtmap-baseline`, the `wall-clock-seconds` and `peak-memory-bytes` measurements, one warmup run, five measured runs, non-empty methodology entries, and non-empty command arguments.

# Fixture model fields

`DebtmapParityFixtures.swift` decodes the additional fields required by these assertions: `matrixSchemaVersion`, `statusDefinition`, `validation.testFilter`, benchmark `schemaVersion`, `outputDirectory`, `methodology`, and benchmark input `sha256`.

# Integrity checks

For each benchmark input, the harness reads the referenced file and checks byte count, line count, and SHA-256 digest against the metadata.

# Citations

[1] [DebtmapParityFixtureTests.swift](../../Tests/SCMAKitTests/DebtmapParityFixtureTests.swift)
[2] [DebtmapParityFixtures.swift](../../Tests/SCMAKitTests/DebtmapParityFixtures.swift)
