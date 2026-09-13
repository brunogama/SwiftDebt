# Core

* [Debt analysis domain model and deterministic scoring](debt-analysis-domain-model.md) - SCMACore models debt entities, evidence, aggregations, scoring policies, deterministic weighted scoring, and priority classification.
* [Swift call graph and coupling risk analysis](swift-call-graph-analysis.md) - SCMACore builds deterministic Swift dependency graphs with syntax-level type references, calls, module dependencies, coupling risks, and explicit confidence notes.
* [LCOV coverage matching and score dampening](lcov-coverage-matching.md) - SCMACore parses LCOV reports, matches coverage to debt entities, emits coverage diagnostics, and treats coverage as a score dampener.
* [Swift functional evidence extraction](swift-functional-evidence-extraction.md) - SCMASyntax extracts syntax-level side-effect and functional-composition facts, and SCMACore converts them into deterministic debt evidence.
