# Core

* [Debt analysis domain model and deterministic scoring](debt-analysis-domain-model.md) - SCMACore models debt entities, evidence, aggregations, scoring policies, deterministic weighted scoring, and priority classification.
* [Swift call graph and coupling risk analysis](swift-call-graph-analysis.md) - SCMACore builds deterministic Swift dependency graphs with syntax-level type references, calls, module dependencies, coupling risks, and explicit confidence notes.
* [LCOV coverage matching and score dampening](lcov-coverage-matching.md) - SCMACore parses LCOV reports, matches coverage to debt entities, emits coverage diagnostics, and treats coverage as a score dampener.
* [Git history risk evidence](git-history-risk-evidence.md) - SCMAKit derives deterministic debt evidence from bounded local Git history for file-level entities.
* [Swift functional evidence extraction](swift-functional-evidence-extraction.md) - SCMASyntax extracts syntax-level side-effect and functional-composition facts, and SCMACore converts them into deterministic debt evidence.
* [Ranked debt analysis composition](ranked-debt-analysis-composition.md) - SCMACore and SCMAKit compose structural, functional, coverage, Git history, and dependency evidence into deterministic ranked debt analysis results.
* [Debt report output formats](debt-report-output-formats.md) - SwiftSCMA renders ranked debt analysis as native debt JSON, Markdown, DOT, text, compact text, and a Debtmap compatibility JSON projection.
* [Debt improvement comparison and validation workflows](debt-improvement-workflows.md) - SCMACore, SCMAKit, and the scma CLI compare two native debt reports and validate whether total debt score improved by a configured threshold.
