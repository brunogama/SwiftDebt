---
okf_version: "0.1"
---

# Swift Deep Research Knowledge Bundle

# Core

* [Debt analysis domain model and deterministic scoring](core/debt-analysis-domain-model.md) - SCMACore models debt entities, evidence, aggregations, scoring policies, deterministic weighted scoring, and priority classification.
* [Git history risk evidence](core/git-history-risk-evidence.md) - SCMAKit derives deterministic debt evidence from bounded local Git history for file-level entities.
* [Swift functional evidence extraction](core/swift-functional-evidence-extraction.md) - SCMASyntax extracts syntax-level side-effect and functional-composition facts, and SCMACore converts them into deterministic debt evidence.

# Tests

* [Debtmap parity fixture harness](tests/debtmap-parity-fixture-harness.md) - Test harness coverage for the debtmap parity matrix, golden fixture determinism, and benchmark methodology metadata.
* [Git history evidence provider tests](tests/git-history-evidence-provider-tests.md) - Swift Testing coverage validates deterministic Git history evidence, unavailable-history handling, and structured Git process arguments.
