# R2 and R3 execution record

This record tracks implementation against `docs/prd-r2.md` and
`docs/prd-r3.md`. A release is complete only when every acceptance and release
gate in its PRD passes on the public library and CLI surfaces. A passing build
alone does not qualify a release.

## Sequence

1. Capture the current `origin/main` build, test, CLI, and schema-2 baseline.
2. Implement deterministic repository evidence and the Data Clumps and Repeated
   Switches rules. Verify both through the CLI and adversarial fixtures.
3. Qualify the optional `SQVectorStatic` product. Keep its dependency outside
   the base SwiftDebt targets and verify the actual static link.
4. Implement R3 Observation Snapshots and append-only persistence. Verify
   atomicity, idempotency, corruption rejection, and schema isolation.
5. Implement conservative reconciliation and resolution coverage. Exercise
   every ambiguity and incomplete-analysis acceptance fixture.
6. Implement bounded Git introduction inference and read-only lifecycle
   reporting. Exercise real temporary Git histories.
7. Integrate the independent branches, run both complete PRD matrices, and
   record accuracy and performance evidence before declaring either release
   ready.

---

## Verification contract

| Release | Completion predicate |
| --- | --- |
| R2 | All 14 Acceptance Criteria and the accuracy, explanation, similarity, index, and calibrated performance gates pass. |
| R3 | AT-1 through AT-27, SM-1 through SM-6, schema isolation, persistence interruption, corruption, and three repository-size performance gates pass. |

Each unit must have a real CLI or public-library fixture, an inspected diff,
and `swift build --build-tests && swift test` before its verdict is recorded.
The decision trail is `.audit/r2-r3-decisions.tsv`.

---

## Current status

| Workstream | Evidence | Release verdict |
| --- | --- | --- |
| Fowler catalog | PR #56, local build/tests and a real CLI run; exact-head CI pending | Partial R2 |
| Repository evidence | Draft PR #58, 22 focused tests and positive/adversarial/conditional CLI fixtures | Blocked by five independent review findings and R2 qualification gates |
| Optional SQVector link | Draft PR #55, local static link and smoke test | Published exact-revision dependency and index contract open |
| Finding lifecycle | Draft PR #57, 21 focused tests and persisted CLI queries | Partial R3; analyze-to-store, continuity, introduction, and acceptance matrix open |

The interrupted prechange `origin/main` build is inconclusive. A later green
catalog build cannot stand in for that baseline. The primary checkout was
already dirty, so implementation was isolated in Git worktrees.
