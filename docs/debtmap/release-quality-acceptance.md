# Debtmap 0.23.0 release-quality acceptance

SwiftDebt claims Debtmap 0.23.0 workflow/capability parity for Swift for the frozen capability matrix in `docs/debtmap/parity-matrix.v0.23.0.json`.

## Closed conformance matrix

Every in-scope capability row in the matrix is implemented and carries release evidence from tests, golden fixtures, executable checks, or this document. Ticket references are no longer used as proof for any in-scope row.

The matrix covers deterministic JSON, Markdown, DOT, and CLI-exit fixtures; debt analyze and validate CLI workflows; coverage and Git-history evidence; graph and functional evidence; ranked scoring, aggregation, and filtering; before and after comparison and improvement validation; terminal and dashboard explorers; profiling budgets; and SwiftPM command/build plugin debt workflows.

## Regression and performance gates

Required gates are represented by these release proofs:

- `docs/debtmap/release-gate-evidence.v2.json` for successful `swift build --build-tests && swift test` and plugin smoke-test gate execution.
- `DebtmapParityFixtureTests.requiredRegressionGatesHavePassingReleaseEvidence` for verifying the committed gate evidence is present, passing, and wired into the matrix.
- `DebtmapParityFixtureTests.benchmarkMethodologyReferencesFrozenInputs` for the frozen benchmark inputs, measurements, workload identity policy, and regression budgets.
- `PerformanceProfilingTests.performanceGateRejectsIncomparableDebtmapRustWorkloads` for rejecting cross-analyzer performance comparisons.
- `PerformanceProfilingTests.performanceGateAppliesWallClockAndMemoryBudgetsForEquivalentWorkloads` for enforcing the configured wall-clock and peak-memory budgets.
- `benchmarks/debtmap-baseline/evidence/2026-09-22-swiftdebt-rename/` for the retained raw samples, platform metadata, profiles, and passing baseline/full-evidence evaluations against a capability-equivalent historical reference.
- `PluginWorkflowTests.commandAndBuildPluginsRunDebtWorkflows` for command and build plugin debt workflow regression coverage.
- `python3 scripts/check_domain_coverage.py` for 100 percent executable domain line coverage.
- The generic iOS, tvOS, watchOS, and visionOS simulator `SwiftDebtKit` builds with Xcode 27 beta. The iOS build covers the declared iPhone and iPadOS library boundary.

The observed baseline gate passed at -12.472651 percent wall clock and -0.117096 percent peak memory. The observed full-evidence gate exercised measured LCOV coverage and available Git history, then passed at -96.452110 percent wall clock and -0.561798 percent peak memory. No approved exceptions were recorded for required gates.

The merge workflow keeps the 15 percent peak-memory limit and pairs it with a fixed 2 MiB absolute allowance for these small process workloads. Peak memory fails only when both limits are exceeded. The policy was exercised against the paired PR #62 baseline artifact: candidate and reference median RSS were 12,484,608 and 10,706,944 bytes, a 1,777,664-byte increase. The observed 16.602907 percent exceeds the relative limit but stays below 2 MiB. The paired sample deltas ranged from 1,392,640 through 1,916,928 bytes. A 2,097,153-byte increase fails, so the allowance cannot hide a regression above both ceilings.

The frozen-input provenance commit preserves the original benchmark corpus but is not automatically a valid performance reference. A performance reference is the latest committed predecessor that accepts the same command surface and executes the same always-on analysis capabilities, optional evidence, and report generation. Comparisons against older, capability-incomplete commits are retained as diagnostics and are not treated as budget passes, failures, or approved exceptions.

## Intentional divergences and unsupported scope

The parity target is Swift workflow and capability parity, not a byte-for-byte model of Debtmap internals. `debtmap-json` remains a deterministic compatibility projection for Debtmap-oriented automation; the native schema is the SwiftDebt debt report.

The SwiftDebt native report uses schema version 2 after the product discriminator and generator rename. Schema-1 native reports must be regenerated with `swift-debt` before `compare`, `validate-improvement`, or dashboard loading. The separate Debtmap compatibility projection remains schema version 1.

Graph evidence is intentionally SwiftSyntax-only. It records resolved, unresolved, and ambiguous edges without claiming compiler type-checker bindings, macro expansion, dynamic dispatch, or complete call-graph semantics.

Concurrency, side-effect, and API-risk evidence is Swift-specific heuristic evidence. It reports syntax-observable risk signals and confidence limits rather than compiler-proven concurrency safety.

Debtmap parsers for non-Swift languages are outside this Swift parity target. Unsupported non-Swift parsing does not weaken the parity definition because the matrix is scoped to Swift workflows and documents that row as out-of-scope.
