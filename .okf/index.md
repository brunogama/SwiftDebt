---
okf_version: "0.1"
---

# Swift Deep Research Knowledge Bundle

# Core

* [Debt analysis domain model and deterministic scoring](core/debt-analysis-domain-model.md) - SwiftDebtCore models debt entities, evidence, aggregations, scoring policies, deterministic weighted scoring, and priority classification.
* [Swift call graph and coupling risk analysis](core/swift-call-graph-analysis.md) - SwiftDebtCore builds deterministic Swift dependency graphs with syntax-level type references, calls, module dependencies, coupling risks, and explicit confidence notes.
* [LCOV coverage matching and score dampening](core/lcov-coverage-matching.md) - SwiftDebtCore parses LCOV reports, matches coverage to debt entities, emits coverage diagnostics, and treats coverage as a score dampener.
* [Git history risk evidence](core/git-history-risk-evidence.md) - SwiftDebtKit derives deterministic debt evidence from bounded local Git history for file-level entities.
* [Swift functional evidence extraction](core/swift-functional-evidence-extraction.md) - SwiftDebtSyntax extracts syntax-level side-effect and functional-composition facts, and SwiftDebtCore converts them into deterministic debt evidence.
* [Ranked debt analysis composition](core/ranked-debt-analysis-composition.md) - SwiftDebtCore and SwiftDebtKit compose structural, functional, coverage, Git history, and dependency evidence into deterministic ranked debt analysis results.
* [Debt report output formats](core/debt-report-output-formats.md) - SwiftDebt renders ranked debt analysis as native debt JSON, Markdown, DOT, text, compact text, a Debtmap compatibility JSON projection, and a browser dashboard.
* [Debt analyze and validate CLI workflows](core/debt-cli-workflows.md) - SwiftDebt exposes namespaced debt analyze and validate commands with deterministic filtering, formatting, coverage, and score-gate options.
* [Debt improvement comparison and validation workflows](core/debt-improvement-workflows.md) - SwiftDebtCore, SwiftDebtKit, and the swift-debt CLI compare two native debt reports and validate whether total debt score improved by a configured threshold.
* [Interactive terminal debt explorer](core/interactive-terminal-debt-explorer.md) - SwiftDebtInteractive renders ranked debt analysis as a terminal debt explorer with deterministic selection, filtering, detail context, and non-TTY fallback behavior.
* [Interactive browser debt dashboard](core/debt-dashboard-browser-report.md) - SwiftDebt renders ranked debt analysis as a self-contained browser dashboard over the native debt-report schema.
* [Performance profiling and regression budgets](core/performance-profiling-budgets.md) - SwiftDebt records opt-in phase profiling output and evaluates comparable benchmark results against wall-clock and peak-memory regression budgets.
* [Debtmap release-quality acceptance](core/debtmap-release-quality-acceptance.md) - SwiftDebt records closed Debtmap 0.23.0 Swift workflow and capability parity with release gate evidence and documented scope boundaries.

# Tests

* [Debtmap parity fixture harness](tests/debtmap-parity-fixture-harness.md) - Test harness coverage for the debtmap parity matrix, release acceptance evidence, golden fixture determinism, and benchmark methodology metadata.
* [Swift structural debt evidence assertions](tests/swift-structural-debt-evidence.md) - Swift Testing coverage asserts structural debt evidence locations, raw values, and nested callable metrics.
* [Git history evidence provider tests](tests/git-history-evidence-provider-tests.md) - Swift Testing coverage validates deterministic Git history evidence, unavailable-history handling, and structured Git process arguments.
* [Ranked debt analysis composition tests](tests/ranked-debt-analysis-tests.md) - Swift Testing coverage verifies deterministic ranked debt analysis composition, provider evidence, unavailable evidence, filters, aggregation, and configuration activation.
* [Debt report renderer tests](tests/debt-report-renderer-tests.md) - Swift Testing coverage verifies deterministic native debt reports, Debtmap compatibility projection output, DOT rendering, text renderers, and service-level debt JSON rendering.
* [CLI debt workflow subprocess tests](tests/cli-debt-workflow-tests.md) - Swift Testing coverage verifies deterministic debt analyze output, validation gate exits, argument errors, and preservation of existing analyze forms.
* [Debt improvement workflow tests](tests/debt-improvement-workflow-tests.md) - Swift Testing coverage verifies deterministic debt report comparison, schema rejection, validation JSON output, and failing improvement-gate exit status.
* [Interactive terminal debt explorer tests](tests/interactive-terminal-debt-explorer-tests.md) - Swift Testing coverage verifies deterministic debt explorer reducer behavior, terminal fallback detection, CLI fallback output, and large-result reducer performance.
* [Debt dashboard renderer tests](tests/debt-dashboard-renderer-tests.md) - Swift Testing coverage verifies deterministic self-contained debt dashboard HTML, local report loading controls, comparison behavior, filtering, and schema validation.
* [Performance profiling and budget tests](tests/performance-profiling-tests.md) - Swift Testing coverage verifies opt-in profiling output, disabled profiling overhead, incomparable workload rejection, and budget enforcement for equivalent workloads.
* [SwiftPM plugin debt workflow tests](tests/swiftpm-plugin-debt-workflow-tests.md) - Swift Testing coverage verifies SwiftPM command and build plugin debt workflows, unavailable evidence propagation, Markdown output, Debtmap projection scores, generated stamps, and validation failures.
