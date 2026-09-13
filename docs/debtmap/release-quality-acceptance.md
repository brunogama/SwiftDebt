# Debtmap 0.23.0 release-quality acceptance

SwiftSCMA claims Debtmap 0.23.0 workflow/capability parity for Swift for the frozen capability matrix in `docs/debtmap/parity-matrix.v0.23.0.json`.

## Closed conformance matrix

Every in-scope capability row in the matrix is implemented and carries release evidence from tests, golden fixtures, executable checks, or this document. Ticket references are no longer used as proof for any in-scope row.

The matrix covers deterministic JSON, Markdown, DOT, and CLI-exit fixtures; debt analyze and validate CLI workflows; coverage and Git-history evidence; graph and functional evidence; ranked scoring, aggregation, and filtering; before and after comparison and improvement validation; terminal and dashboard explorers; profiling budgets; and SwiftPM command/build plugin debt workflows.

## Regression and performance gates

Required gates are represented by these release proofs:

- `docs/debtmap/release-gate-evidence.v1.json` for successful `swift build --build-tests && swift test` and plugin smoke-test gate execution.
- `DebtmapParityFixtureTests.requiredRegressionGatesHavePassingReleaseEvidence` for verifying the committed gate evidence is present, passing, and wired into the matrix.
- `DebtmapParityFixtureTests.benchmarkMethodologyReferencesFrozenInputs` for the frozen benchmark inputs, measurements, workload identity policy, and regression budgets.
- `PerformanceProfilingTests.performanceGateRejectsIncomparableDebtmapRustWorkloads` for rejecting cross-analyzer performance comparisons.
- `PerformanceProfilingTests.performanceGateAppliesWallClockAndMemoryBudgetsForEquivalentWorkloads` for enforcing the configured wall-clock and peak-memory budgets.
- `PluginWorkflowTests.commandAndBuildPluginsRunDebtWorkflows` for command and build plugin debt workflow regression coverage.

No approved exceptions were recorded for required gates.

## Intentional divergences and unsupported scope

The parity target is Swift workflow and capability parity, not a byte-for-byte model of Debtmap internals. `debtmap-json` remains a deterministic compatibility projection for Debtmap-oriented automation; the native schema is the SwiftSCMA debt report.

Graph evidence is intentionally SwiftSyntax-only. It records resolved, unresolved, and ambiguous edges without claiming compiler type-checker bindings, macro expansion, dynamic dispatch, or complete call-graph semantics.

Concurrency, side-effect, and API-risk evidence is Swift-specific heuristic evidence. It reports syntax-observable risk signals and confidence limits rather than compiler-proven concurrency safety.

Debtmap parsers for non-Swift languages are outside this Swift parity target. Unsupported non-Swift parsing does not weaken the parity definition because the matrix is scoped to Swift workflows and documents that row as out-of-scope.
