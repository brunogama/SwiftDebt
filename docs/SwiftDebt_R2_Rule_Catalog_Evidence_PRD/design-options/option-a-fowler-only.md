# A: Fowler-only catalog

Source: Martin Fowler, Refactoring, Second Edition, chapter 3; the main branch already has a 24-entry documented and typed catalog. Replace the unproven 100-item source assumption with coverage of those 24 named smells. Keep Swift-specific addendum examples only as unnumbered illustration of capability/evidence mechanics, outside the completeness metric.

Contract: FR-1 and SM-1 become 24/24 stable mappings, preserving Support State and missing-evidence honesty. All original researchItem numbers are removed from this PRD's source claims. A new ADR supersedes accepted ADR 0001's source-number-dependent decisions without rewriting its history. Port only needed Rule Catalog infrastructure onto main, avoiding a second conflicting catalog.

Upside: exact bounded external source, existing main code and tests, smallest reconciliation surface. Downside: drops Swift-specific repository/concurrency acceptance examples from the PRD's product scope, contrary to its original differentiation; addendum and existing branch examples need heavy reclassification. Risks making the new PRD redundant with docs/prd-r2.md and issue #48.
