---
type: Test Coverage
title: Performance profiling and budget tests
description: Swift Testing coverage verifies opt-in profiling output, disabled profiling overhead, incomparable workload rejection, and budget enforcement for equivalent workloads.
resource: Tests/SCMAKitTests/PerformanceProfilingTests.swift
tags: [swift-testing, performance, profiling, budgets, scmakit]
timestamp: 2026-09-13T00:00:00Z
---

# Coverage

`PerformanceProfilingTests` exercises `AnalysisService` with `profileOutputPath` enabled and verifies that a machine-readable profile file is written, decoded as `AnalysisProfile`, and returned in `AnalysisRunResult.profile`.

The profiling test expects schema version `1`, measurement names `wall-clock-nanoseconds` and `peak-resident-memory-bytes`, disabled-overhead fields with zero clock reads, zero peak-memory reads, zero per-source work, and phase-boundary checks matching `AnalysisProfile.disabledInstrumentationOverhead`.

# Phase assertions

The profile output is expected to include elapsed nanoseconds greater than zero for discovery, parsing, structural evidence, graph, coverage, repository history, functional evidence, scoring, aggregation, and rendering when those phases run.

# Disabled default

The default service run without `profileOutputPath` must return `nil` profile while preserving quantified disabled-overhead metadata.

# Budget assertions

The budget tests verify that Debtmap Rust workload comparisons are rejected as incomparable against SwiftSCMA baselines, including analyzer and workload-family mismatch reasons. Equivalent SwiftSCMA workloads are evaluated against wall-clock and peak-memory budget percentages and report budget-exceeded reasons when candidate medians regress beyond configured thresholds.

# Fixture metadata assertions

`DebtmapParityFixtureTests` now asserts that the benchmark methodology includes profile-output commands, phase-wall-clock measurement, platform-variance metadata, disallowed Debtmap Rust comparisons, approved exception evidence, and the two configured SwiftSCMA regression budgets.

# Citations

[1] [PerformanceProfilingTests.swift](../../Tests/SCMAKitTests/PerformanceProfilingTests.swift)
[2] [DebtmapParityFixtureTests.swift](../../Tests/SCMAKitTests/DebtmapParityFixtureTests.swift)
[3] [DebtmapParityFixtures.swift](../../Tests/SCMAKitTests/DebtmapParityFixtures.swift)
[4] [methodology.v1.json](../../benchmarks/debtmap-baseline/methodology.v1.json)
