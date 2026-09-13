---
okf_version: "0.1"
---

# Swift Deep Research Knowledge Bundle

# Core

* [Debt analysis domain model and deterministic scoring](core/debt-analysis-domain-model.md) - SCMACore models debt entities, evidence, aggregations, scoring policies, deterministic weighted scoring, and priority classification.
* [LCOV coverage matching and score dampening](core/lcov-coverage-matching.md) - SCMACore parses LCOV reports, matches coverage to debt entities, emits coverage diagnostics, and treats coverage as a score dampener.
* [Swift functional evidence extraction](core/swift-functional-evidence-extraction.md) - SCMASyntax extracts syntax-level side-effect and functional-composition facts, and SCMACore converts them into deterministic debt evidence.

# Tests

* [Debtmap parity fixture harness](tests/debtmap-parity-fixture-harness.md) - Test harness coverage for the debtmap parity matrix, golden fixture determinism, and benchmark methodology metadata.
