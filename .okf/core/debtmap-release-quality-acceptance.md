---
type: Release Acceptance
title: Debtmap release-quality acceptance
description: SwiftDebt records closed Debtmap 0.23.0 Swift workflow and capability parity with release gate evidence and documented scope boundaries.
resource: docs/debtmap/release-quality-acceptance.md
tags: [swift, debt-analysis, debtmap, release]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

SwiftDebt claims `Debtmap 0.23.0 workflow/capability parity for Swift` for the frozen capability matrix in `docs/debtmap/parity-matrix.v0.23.0.json`.

The closed matrix records every in-scope capability as implemented and replaces ticket references with release evidence from tests, golden fixtures, executable checks, gate evidence, or the release-quality acceptance document.

# Release gates

`docs/debtmap/release-gate-evidence.v2.json` records schema version `2` evidence for nine passing gates:

* `swift build --build-tests && swift test`
* `python3 scripts/smoke-test.py --binary .build/debug/swift-debt --plugins`
* baseline-analysis wall-clock and peak-memory budgets
* full-evidence wall-clock and peak-memory budgets
* complete executable domain line coverage
* the SwiftDebtKit iOS, tvOS, watchOS, and visionOS simulator builds with Xcode 27 beta

The parity fixture harness verifies that the gate evidence is wired into the matrix, has zero exit statuses, includes observed timestamps, and records pass summaries. No approved exceptions were recorded for required gates.

# Scope boundaries

The parity target is Swift workflow and capability parity, not a byte-for-byte model of Debtmap internals. `debtmap-json` remains a deterministic compatibility projection, while the native schema is the SwiftDebt debt report.

Documented intentional boundaries include SwiftSyntax-only graph evidence, syntax-observable concurrency and API-risk heuristics, and non-Swift Debtmap parsers being outside the Swift parity target.

# Citations

[1] [Release quality acceptance](../../docs/debtmap/release-quality-acceptance.md)
[2] [Release gate evidence](../../docs/debtmap/release-gate-evidence.v2.json)
[3] [Debtmap parity matrix](../../docs/debtmap/parity-matrix.v0.23.0.json)
[4] [DebtmapParityFixtureTests.swift](../../Tests/SwiftDebtKitTests/DebtmapParityFixtureTests.swift)
