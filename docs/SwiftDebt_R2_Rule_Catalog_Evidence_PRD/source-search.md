# Original 100-item catalog provenance gate

Historical pre-rescope checkpoint. All file paths and line references below describe the old `feat/debtmap` branch **before** the PRD was revised; the final "do not proceed" instruction was superseded by the explicit source/catalog decision in [ADR 0002](../adr/0002-r2-rule-catalog-source-and-authoring.md). This record is retained as evidence of why the original 100-item claim was not accepted.

Verdict: **INCONCLUSIVE**. No original, attributable 100-item Swift technical-debt catalog was located or authenticated. This does not prove no such catalog exists. Do not substitute a similar public list or synthesize the missing entries.

---

## Required identity test

An eligible source must provide 100 numbered original claims and preserve at least three separated mappings from the same document, including #12 DispatchSemaphore.wait in async, #19 actor reentrancy, #28 try!, #46 @ObservedObject ownership, #71 SwiftPM unsafeFlags, and #86-92 CI/CD. The PRD's FR-1/SM-1 explicitly require traceability to the **source** claims, not merely matching category names.

---

## Local checks

- `docs/SwiftDebt_R2_Rule_Catalog_Evidence_PRD/prd.md:168` says the 100-item research set was **supplied**, but gives no author, title, URL, DOI, or original list. `prd-addendum.md:209-235` supplies only nine numbered example headings; accepted `docs/adr/0001-r2-open-questions.md:109-115` repeats them.
- `docs/SwiftDebt_R2_Rule_Catalog_Evidence_PRD.zip` has exactly two members, `prd.md` and `prd-addendum.md`; `unzip -p ... | cmp` confirmed both are byte-identical to the tracked files, so the archive supplies no missing source.
- `Sources/SwiftDebtCore/RuleCatalog/Manifest/RuleCatalogManifest.yaml` has three entries, not 100. Its `quality.long-method` placeholder claims `researchItem: 12` (lines 63-80), inconsistent with accepted ADR Q11 and the addendum's #12 blocking semaphore. This is an implementation provenance defect, not proof that the source never existed.
- `docs/PAPER_MAPPING.md:5-7` identifies a separate four-page SCMA metrics paper and explicitly says that PDF is not redistributed. Its ten metrics are not this 100-item catalog. Current main's `docs/REFACTORING_CODE_SMELLS.md` is a separate Fowler-derived 24-smell lineage, not this numbered Swift research set.
- GitHub issue and tracked-file searches found no attached original list. A read-only independent source audit corroborated local absence but had no public web-search tool, so it did not independently validate the public search.

---

## Public searches

- Anysearch response `muudw4tt5uh2v6`: three exact multi-anchor queries (including DispatchSemaphore, actor reentrancy, @ObservedObject, unsafeFlags, 100) returned no results.
- Anysearch response `muudwd7511bqdn`: broad Swift debt/100 queries returned generic technical-debt articles, a 56-smell catalog, and individual actor-reentrancy tutorials. None had the required 100 numbered anchors.
- Anysearch response `muudyq4sqbuvi1`: exact `researchItem: 71` + unsafeFlags, primitive identifiers + @ObservedObject + actor reentrancy, and exact 100-item phrase returned no results.
- GitHub code search for the paired numbered anchors returned no matching source. Brave and SearXNG providers were not configured; an OpenAI-provider search timed out. These access limits narrow the search confidence but do not justify treating unrelated results as the original.

---

## Consequence

Source-identity predicate is not met. No integration worktree, manifest edits, PRD edits, issue changes, or code implementation were started. To proceed with the requested **full** PRD without fabricated provenance, obtain the original supplied 100-item document or an exact verifiable URL from its author/owner. An alternate public catalog would require an explicit change to the PRD and accepted decision boundaries; it cannot silently satisfy FR-1 or SM-1.
