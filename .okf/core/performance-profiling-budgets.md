---
type: Feature
title: Performance profiling and regression budgets
description: SwiftSCMA records opt-in phase profiling output and evaluates comparable benchmark results against wall-clock and peak-memory regression budgets.
resource: Sources/SCMAKit/AnalysisProfiler.swift
tags: [swift, performance, profiling, budgets, scmacore, scmakit]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

SwiftSCMA supports opt-in analysis profiling through `AnalysisRequest.profileOutputPath` and the CLI `--profile-output` option. Profiling is absent by default; when enabled, `AnalysisService` creates an `AnalysisProfiler`, passes it through analysis, and writes pretty-printed sorted JSON after protecting source, configuration, manifest, report, and Swift file paths from being overwritten.

`AnalysisProfile` schema version `1` reports `wall-clock-nanoseconds` and `peak-resident-memory-bytes`. It records profiled phases using `AnalysisPhase`: discovery, parsing, structural evidence, graph, coverage, repository history, functional evidence, scoring, aggregation, and rendering.

# Disabled overhead

`AnalysisProfile.disabledInstrumentationOverhead` documents disabled profiling as no profiler allocation, no clock reads, no peak-memory reads, no per-source work, and at most 24 optional phase-boundary checks.

# Regression budgets

`PerformanceBudgetGate` compares a baseline and candidate only when their `PerformanceWorkloadIdentity` values match for analyzer, workload family, input SHA-256, command fingerprint, analysis mode, and optional context. Incomparable workloads fail with reasons such as differing analyzer, workload family, checksum, command fingerprint, analysis mode, or optional context.

Comparable workloads are evaluated by percentage regression against `PerformanceRegressionBudget` maximum wall-clock and peak-memory thresholds. The evaluation reports comparability, pass/fail, wall-clock regression percent, peak-memory regression percent, and budget-exceeded reasons.

# Benchmark methodology

`benchmarks/debtmap-baseline/methodology.v1.json` now includes phase-wall-clock nanosecond measurement, profile-output arguments for measured commands, noise controls, required platform metadata, disallowed cross-workload comparisons, exception evidence, and two SwiftSCMA workload budgets: `baseline-analysis` and `full-evidence-analysis`.

# Citations

[1] [AnalysisProfiling.swift](../../Sources/SCMACore/AnalysisProfiling.swift)
[2] [PerformanceBudgetGate.swift](../../Sources/SCMACore/PerformanceBudgetGate.swift)
[3] [AnalysisProfiler.swift](../../Sources/SCMAKit/AnalysisProfiler.swift)
[4] [AnalysisService.swift](../../Sources/SCMAKit/AnalysisService.swift)
[5] [WorkspaceConfiguration.swift](../../Sources/SCMAKit/WorkspaceConfiguration.swift)
[6] [CLIOptions.swift](../../Sources/scma/CLIOptions.swift)
[7] [DebtCLIOptions.swift](../../Sources/scma/DebtCLIOptions.swift)
[8] [methodology.v1.json](../../benchmarks/debtmap-baseline/methodology.v1.json)
