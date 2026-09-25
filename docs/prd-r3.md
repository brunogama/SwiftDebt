# SwiftDebt R3 - Persistent Finding Lifecycle

**Status:** Draft | **Release:** R3 | **Created:** 2026-09-24 | **Predecessors:** R1 trustworthy observations and the R2 hybrid-analysis draft

---

## 1. Document purpose

This PRD defines how SwiftDebt turns trustworthy observations from individual analyses into an auditable history of persistent Findings. It is for product, rule, engine, reporting, and downstream architecture owners. It states which lifecycle claims SwiftDebt may make, the evidence each claim requires, and how uncertainty must appear to users.

R3 is deliberately a product contract rather than an implementation design. It does not select a database, storage schema, Git library, matching algorithm, fingerprint format, or search index. Those mechanisms are acceptable only when they preserve the requirements and invariants in this document.

---

## 2. Product decision

R3 will answer four questions without manufacturing certainty:

1. Where and under which analysis conditions was this debt observed?
2. Is a later Detection evidence of the same Finding, a new Finding, or an unresolved ambiguity?
3. Has the Finding been verified as absent by a complete comparable observation?
4. What, if anything, can Git history establish about when the Finding was introduced?

The product thesis is that a useful debt history must preserve uncertainty instead of converting missing evidence into a clean result. A partial analysis can add positive knowledge because an observed Detection remains a fact. It cannot erase prior knowledge. Continuity, resolution, and introduction are conclusions with stronger evidence requirements than first observation.

R3 adds persistence and lifecycle reporting around canonical engine-owned Detections. It does not change what a rule is allowed to observe, and it does not let persistence, Git, similarity retrieval, or a vector store author a Detection.

### 2.1 Settled decisions

| Decision | Product consequence |
| --- | --- |
| Detection remains the canonical current-source observation owned by the engine. | Lifecycle processing consumes committed Detections and cannot recreate or rewrite them. |
| A rule and SourceUnit execution commits atomically. | Parse failure, unsupported analysis, failed analysis, and excluded analysis for that pair cannot prove absence. |
| Location is evidence, not identity. | Line movement, formatting, and file rename do not automatically create or close a Finding. |
| First observation is a fact; introduction is a conclusion. | Every Finding can report when SwiftDebt first saw it, while Git introduction may remain bounded or unavailable. |
| Resolution requires complete comparable observation. | Missing, partial, ambiguous, or semantically incomparable evidence leaves the prior Finding unresolved. |
| Ambiguity is a valid result. | Reconciliation never selects a candidate only to keep history visually continuous. |
| Policy enforcement is deferred. | R3 exposes truthful lifecycle facts and does not define debt budgets, age gates, waivers, or lifecycle-based CI failure. |

### 2.2 Relationship to earlier releases

- R1 supplies the trustworthy observation boundary: rules propose observations, the engine validates and commits canonical Detections, and each rule by SourceUnit result is independently committed or explicitly non-committed.
- R2 may add repository-aware, relational, and semantic evidence. Its optional `sqvector-swift` candidate retrieval can propose candidates, but similarity is never Finding identity or lifecycle proof. R2 does not rely on Git history; Git-backed lifecycle inference begins in R3, while history-based smell detection remains deferred.
- Current code-smell findings remain advisory by default, as documented in [Refactoring second-edition code smells](REFACTORING_CODE_SMELLS.md). The existing `--fail-on-violation` option evaluates the current run. R3 history and resolution are a separate concern and do not silently change that gate.
- Existing `AnalysisReport` schema 2 and `DebtReport` schema 2 keep their released byte shape and meaning. The compiler evidence sidecar keeps its independent contract under [ADR 0001](adr/0001-compiler-evidence-sidecar-boundary.md).

---

## 3. Target users and jobs

### 3.1 Primary users

- Repository maintainers who need to know which debt is currently observed, which debt was verified as resolved, and which debt has uncertain status.
- Staff and principal engineers who need an evidence-backed history for refactoring and architecture discussions.
- CI and platform owners who need stable machine-readable lifecycle facts for later policy consumers.
- Coding agents and automation that need to explain a Finding without guessing from a line number or comparing report rows heuristically.

### 3.2 Jobs to be done

- Track one Finding through ordinary edits, line movement, and uniquely evidenced renames.
- Distinguish a verified resolution from a run that did not successfully look.
- See why SwiftDebt continued, opened, resolved, reopened, or declined to reconcile a Finding.
- Determine the earliest supportable Git introduction conclusion and understand its limits.
- Audit the source, rule semantics, configuration, capabilities, scope, and observation outcome behind every lifecycle event.
- Export deterministic lifecycle data for reports and future policy systems.

### 3.3 Primary user journey

**UJ-1 - A repository maintainer verifies the life of a debt item.**

1. The maintainer analyzes a repository revision. A committed Detection has no credible predecessor, so SwiftDebt opens a Finding and records that snapshot as its first observation.
2. A later commit moves the enclosing declaration and changes its line number. SwiftDebt finds one sufficiently supported continuation, keeps the Finding identity, and records the new observation and location.
3. A changed-files run cannot analyze one relevant SourceUnit. The Finding remains open, and the report says its latest absence is unverified rather than resolved.
4. A later repository-scope run uses comparable rule semantics and commits every required rule by SourceUnit observation. The Finding has no continuing or ambiguous Detection, so SwiftDebt records verified resolution.
5. The maintainer asks for an explanation. SwiftDebt shows the timeline, the snapshots and provenance behind each event, why the incomplete run could not resolve the Finding, and the Git introduction conclusion as exact, bounded, or unavailable.
6. If a later Detection uniquely reconciles to the resolved Finding, SwiftDebt records a reopen event. If several histories are plausible, it reports continuity ambiguity and does not choose one.

The value moment is the explanation of a lifecycle claim, including the evidence that supports it and the evidence gaps that limit it.

---

## 4. Glossary

- **SourceUnit** - The exact source input unit used by a rule execution under the R1 observation contract. A path may describe a SourceUnit but does not by itself establish identity across snapshots.
- **Rule Identity** - The stable name of a rule, separate from its Semantic Revision.
- **Semantic Revision** - The version of a rule's detection meaning. A changed threshold, predicate, required capability, or interpretation can make two observations semantically incomparable even when the Rule Identity is unchanged.
- **Atomic Observation** - The outcome for one Rule Identity, one Semantic Revision, and one parsed SourceUnit in one Observation Snapshot. Its outcome is one of: committed with zero or more Detections, unsupported, failed, or excluded with a recorded reason. A SourceUnit parse failure occurs before rule execution, is recorded once at source level, and marks every affected expected Atomic Observation as not executed; it is not a rule failure.
- **Detection** - A canonical current-source fact validated and committed by the engine. It records its rule semantics and canonical source location plus any rule evidence accepted by the engine. It is not a persistent lifecycle identity.
- **Observation Snapshot** - An immutable, versioned record of the selected analysis scope, every expected Atomic Observation outcome, committed Detections, and Snapshot Provenance for one analyzed source state.
- **Snapshot Provenance** - The source identity, repository and revision state when available, content identity, selected and excluded scope, rule semantics, effective configuration, required capability availability, engine identity, and ordering relationship needed to interpret an Observation Snapshot.
- **Finding** - The persistent record for one debt occurrence across zero or more later Observation Snapshots. It has a stable Finding ID, a Lifecycle State, an Evidence State, and an append-only sequence of Lifecycle Events. Existing schema-2 report rows named `findings` do not acquire this lifecycle meaning.
- **Finding ID** - An opaque stable reference assigned only after the product can open a Finding without unresolved predecessor ambiguity. It is never derived solely from a path, line, column, message, embedding, or similarity score.
- **Lifecycle State** - The last conclusively supported state, either `open` or `resolved`. `reopened` is a Lifecycle Event that moves a resolved Finding back to `open`; it is not a third durable state.
- **Evidence State** - The latest support for a Finding in a selected lineage: `observed`, `unverified`, `continuity-ambiguous`, or `verified-absent`. Only `verified-absent` can create a transition to `resolved`; later ambiguous evidence does not rewrite that event and must remain visible until a supported reopen or new-Finding conclusion exists.
- **Lifecycle Event** - An immutable statement that a Finding was opened, observed again, moved, resolved, reopened, or became unverifiable or continuity-ambiguous, with links to all supporting and limiting evidence.
- **First Observation** - The Observation Snapshot in which SwiftDebt first opened the Finding during ordered ingestion. It is an immutable operational fact and does not claim that the debt began in that source state. An older source revision analyzed later can refine the Introduction Conclusion but not rewrite First Observation.
- **Introduction Conclusion** - A Git-backed conclusion about when a Finding first became present. Its result is `exact`, `bounded`, or `unavailable`, and it records the evidence and limitations that produced that result.
- **Continuity** - The conclusion that Detections from different Observation Snapshots describe the same Finding.
- **Reconciliation** - The deterministic evaluation that produces a unique continuity result, a new Finding, an unresolved Detection, or a continuity ambiguity.
- **Continuity Candidate** - A prior Finding that has auditable evidence suggesting possible Continuity with a Detection. Candidate status alone never establishes Continuity.
- **Unresolved Detection** - A committed current Detection that cannot yet receive a new or existing Finding ID because one or more credible predecessor relationships remain ambiguous. It remains visible in current results and audit output.
- **Comparability** - A recorded decision that two Observation Snapshots support a particular cross-snapshot claim. Comparability is directional and claim-specific: continuity, verified absence, and Git introduction may have different requirements.
- **Resolution Coverage** - The comparable Atomic Observations and source scope that must commit before absence can be used to resolve a Finding, including the eligible search space for a move, rename, or deletion.
- **Verified Resolution** - The transition to `resolved` after complete Resolution Coverage establishes absence and Reconciliation finds no continuing or ambiguous Detection.
- **Lineage** - An explicitly ordered chain of source states used to evaluate lifecycle transitions. Divergent Git branches are separate lineages unless a later merge provides an ancestry relationship.

---

## 5. Product invariants

1. **Positive observations survive incomplete runs.** A committed Detection can open or update a Finding even when another Atomic Observation fails.
2. **Missing observation is not absence.** Parse failed, unsupported, failed, excluded, omitted, or out-of-scope analysis cannot resolve a Finding.
3. **Truth outranks continuity.** SwiftDebt reports ambiguity instead of forcing a stable-looking history.
4. **Location does not own identity.** Path, line, column, message, or display name can support Reconciliation but none is sufficient alone.
5. **Rule meaning is part of every claim.** A same-named rule under incomparable semantics cannot verify Continuity, absence, or introduction.
6. **Resolution is stronger than non-observation.** Only complete comparable Resolution Coverage can produce Verified Resolution.
7. **History does not rewrite facts.** Git inference can add or revise an Introduction Conclusion, but it cannot change the First Observation or erase prior Lifecycle Events.
8. **Every conclusion is explainable.** A lifecycle result without inspectable supporting and limiting evidence is invalid.
9. **Replay is deterministic.** The same ordered inputs and compatibility decisions produce the same Finding assignments, events, ambiguities, and report ordering.
10. **Unrelated lineages do not overwrite one another.** Wall-clock arrival order cannot make a divergent branch the successor of another branch.

---

## 6. Functional requirements

### 6.1 Observation Snapshots and provenance

#### FR-1: Persist an immutable Observation Snapshot

SwiftDebt must persist each accepted Observation Snapshot as an immutable fact before using it for lifecycle transitions. A failed persistence operation must not partially update Findings or their Lifecycle Events.

#### FR-2: Preserve claim-relevant Snapshot Provenance

Each Observation Snapshot must record enough provenance to determine source identity, expected analysis scope, actual coverage, rule semantics, effective configuration, capability availability, engine identity, and lineage ordering. An unavailable provenance field must be explicit and must name the claims it blocks.

#### FR-3: Preserve every Atomic Observation outcome

For every selected SourceUnit, the Observation Snapshot must record whether parsing succeeded and retain any parse diagnostics. For every expected Rule Identity by SourceUnit pair, it must then distinguish committed zero Detections, committed one or more Detections, unsupported, failed, excluded, and not executed because the SourceUnit failed to parse. A source parse failure must not be represented as a rule failure. An absent row or empty aggregate cannot be interpreted as a committed empty result.

#### FR-4: Retain positive facts from an incomplete snapshot

A committed Detection in an otherwise incomplete Observation Snapshot remains eligible to open or observe a Finding. The same snapshot cannot establish Verified Resolution for any Finding whose Resolution Coverage intersects an uncommitted or excluded Atomic Observation.

#### FR-5: Make ingestion idempotent and order-aware

Re-ingesting the same Observation Snapshot must not duplicate Findings or Lifecycle Events. A late or repeated snapshot may enrich historical evidence, but it must not become a successor merely because it arrived later.

#### FR-6: Keep released report contracts isolated

R3 lifecycle persistence and output must not silently add fields to `AnalysisReport` schema 2, `DebtReport` schema 2, or the compiler evidence sidecar. Consumers must be able to identify and reject unknown lifecycle artifact versions before interpreting them.

### 6.2 Finding creation and continuity

#### FR-7: Open a Finding from first supportable observation

When a committed Detection has no credible predecessor, SwiftDebt must open a Finding in Lifecycle State `open`, Evidence State `observed`, and record the snapshot as its First Observation. The First Observation must not be labeled as introduction.

#### FR-8: Assign durable identity independently of location

A Finding ID must remain stable across line shifts, formatting changes, and uniquely evidenced path or declaration moves. SwiftDebt must not create a Finding ID by hashing only location, diagnostic text, or a similarity representation.

#### FR-9: Link every observation to its canonical Detection

Every observed or reopened Lifecycle Event must link to the exact committed Detection and Atomic Observation that support it. Lifecycle storage cannot normalize away rule semantics, source identity, or decisive evidence.

#### FR-10: Reconcile deterministically

Given the same prior Findings, current Detections, Snapshot Provenance, Comparability decisions, and ordering, Reconciliation must return the same result and reason codes regardless of concurrency or traversal order.

#### FR-11: Continue only on unique sufficient evidence

SwiftDebt may assign a current Detection to an existing Finding only when the evidence is sufficient under that rule's continuity contract and the supported assignment is unique within the reconciliation set.

#### FR-12: Preserve ambiguity without selecting a winner

When more than one credible predecessor or successor assignment remains, SwiftDebt must record a continuity ambiguity. Prior Finding states remain unchanged, current Detections stay visible as Unresolved Detections, and no candidate is auto-merged, auto-resolved, reopened, or silently opened as definitely new.

#### FR-13: Open a new Finding only when predecessor ambiguity is absent

A committed Detection that has no credible prior Continuity Candidate may open a new Finding. A low score or failure to retrieve a candidate is insufficient if required candidate evidence was unavailable.

#### FR-14: Treat move, rename, copy, split, and merge as evidence-sensitive changes

A unique move or rename can preserve Continuity. A copy, one-to-many split, many-to-one merge, or many-to-many change must remain ambiguous unless rule-specific evidence establishes one unique lifecycle assignment. Git rename or copy heuristics are evidence, not identity proof.

#### FR-15: Keep current debt visible during unresolved identity

Inventory and reports must show Unresolved Detections separately from identified Findings so ambiguity cannot make current observed debt disappear or inflate the count of definitely new Findings.

### 6.3 Semantic Comparability

#### FR-16: Evaluate Comparability before cross-snapshot conclusions

SwiftDebt must evaluate Comparability before asserting Continuity, Verified Resolution, reopening, or an Introduction Conclusion. Matching Rule Identity and Semantic Revision is not sufficient when effective configuration, required capabilities, source identity, or scope differs.

#### FR-17: Make Comparability directional and claim-specific

The product must be able to express that a later rule/configuration can support one claim but not another. For example, absence under a later broader detector may prove absence under an earlier narrower detector, while the reverse comparison remains invalid. Every allowed and blocked claim must have a reason.

#### FR-18: Fail closed across semantic changes

Different Semantic Revisions are incomparable by default. Cross-revision claims require an explicit, tested compatibility declaration that covers the relevant effective configuration, required capabilities, evidence interpretation, and direction.

#### FR-19: Record the comparison basis

Every lifecycle conclusion must retain the exact snapshots, Semantic Revisions, configuration dimensions, capabilities, scope, and compatibility declaration used. A later explanation must not recompute the reason from mutable defaults.

### 6.4 Verified Resolution and reopening

#### FR-20: Require complete comparable Resolution Coverage

SwiftDebt may resolve an open Finding only when a later Observation Snapshot is an ordered successor in the selected Lineage, the rule semantics are comparable for absence, every Atomic Observation in Resolution Coverage committed, and no continuing or ambiguous Detection remains.

#### FR-21: Block resolution on non-proof outcomes

Parse failed, unsupported, failed, excluded, omitted, canceled, timed-out, unavailable capability, unknown source identity, or semantically incomparable analysis must not create a continuity, resolution, or reopen conclusion for the affected scope. SwiftDebt must preserve the prior Lifecycle State, mark the affected current evidence as unverified, and identify the exact blocker.

#### FR-22: Cover relocation and deletion before claiming absence

If a prior SourceUnit moved, was renamed, disappeared, or left the selected scope, Resolution Coverage must include the eligible successor search space. File deletion alone does not prove debt resolution when the debt could have moved or been copied elsewhere.

#### FR-23: Record resolution as a new fact

Verified Resolution must append a Lifecycle Event linked to the resolving Observation Snapshot and comparison evidence. It must retain all prior observations and must never rewrite the last observed Detection into an absence record.

#### FR-24: Reopen only with unique supported Continuity

A later committed Detection may reopen a resolved Finding only when it uniquely satisfies the continuity contract for that Finding. The reopen event must retain the intervening Verified Resolution and identify the new observation as recurrence after verified absence. Otherwise the Detection is new or unresolved according to FR-12 and FR-13.

### 6.5 Git introduction inference

#### FR-25: Always report First Observation independently

Every Finding must expose First Observation even when Git is unavailable. First Observation uses the analyzed source state and must not be relabeled when older history is analyzed later.

#### FR-26: Express Introduction Conclusions without fake precision

Git introduction inference must return one of:

- `exact`: one revision is supported as the introduction point;
- `bounded`: evidence establishes a range or ancestry boundary but not one revision; or
- `unavailable`: the available history cannot support an introduction claim.

The result must include the analyzed history boundary, rule semantics, scope, capability state, and limiting gaps.

#### FR-27: Require comparable positive and negative historical evidence

An exact Introduction Conclusion requires a comparable committed Detection in the candidate revision and either verified comparable absence in every relevant parent lineage or evidence that the candidate is the repository root with no parent. A bounded conclusion may use the earliest positive observation and the nearest verified-absent or unknown boundary. Missing history is not verified absence.

#### FR-28: Handle merge history explicitly

A merge revision may be called the exact introduction only when the Finding is detected at the merge and verified absent from every relevant comparable parent. If it exists in a parent, inference must follow that parent lineage. Incomplete or incomparable parents produce a bounded or unavailable result.

#### FR-29: Degrade honestly for dirty, shallow, rewritten, or unavailable history

A dirty working tree can support First Observation by content identity but cannot be assigned an exact committed Git introduction. Shallow clones, missing objects, unsupported historical toolchains, history rewrites, and unavailable source identity must narrow or invalidate the Introduction Conclusion with an explicit reason.

#### FR-30: Keep Git inference non-destructive

Re-running introduction inference with deeper history may refine an Introduction Conclusion from unavailable to bounded or from bounded to exact. It must not delete the previous conclusion or alter the Finding's observed lifecycle; the audit history must show the refinement and its new evidence boundary.

### 6.6 Read-only audit, explanation, and reporting

#### FR-31: Report a lifecycle inventory

Users must be able to list Findings by Lifecycle State and Evidence State, with First Observation, last observation, Verified Resolution when present, Introduction Conclusion, current location when observed, and explicit ambiguity or verification blockers. Unresolved Detections must be listed separately.

#### FR-32: Explain one Finding end to end

A read-only explanation must show the Finding's ordered Lifecycle Events, supporting Detections, Observation Snapshots, Comparability decisions, reconciliation reasons, provenance, uncertainty, and Introduction Conclusion. It must answer why a Finding did or did not transition at each relevant snapshot.

#### FR-33: Inspect an Observation Snapshot

Users must be able to inspect the selected scope, expected and actual Atomic Observations, committed Detections, exclusions, failures, capabilities, source identity, and downstream lifecycle effects of an Observation Snapshot.

#### FR-34: Produce stable machine-readable output

Lifecycle inventory, Finding explanation, snapshot inspection, and audit export must have versioned machine-readable forms with deterministic ordering. Human-readable output may summarize but cannot omit uncertainty that changes the meaning of a claim.

#### FR-35: Keep R3 lifecycle interaction read-only

R3 does not let a user manually force Continuity, resolution, reopening, introduction, suppression, waiver, ownership, or severity through the lifecycle reporting surface. Analyses and evidence refinement can append facts; report and explain operations cannot mutate lifecycle state.

#### FR-36: Fail closed on unreadable lifecycle data

Unknown schema versions, failed migrations, corrupt records, broken references, or incomplete writes must produce an explicit audit error and preserve the last verifiable state. SwiftDebt must not rebuild an apparently clean history by dropping unreadable evidence.

---

## 7. Lifecycle model

### 7.1 State and evidence transitions

| Input condition | Prior Lifecycle State | Resulting Lifecycle State | Evidence State | Required event or output |
| --- | --- | --- | --- | --- |
| Detection has no credible predecessor | None | `open` | `observed` | Open Finding and record First Observation. |
| Detection uniquely continues prior Finding | `open` | `open` | `observed` | Append observation; record move when material. |
| Relevant observation is missing, failed, excluded, or incomparable | `open` or `resolved` | unchanged | `unverified` | Append or expose blocker; do not infer a transition. |
| Reconciliation has multiple credible assignments | `open` or `resolved` | unchanged | `continuity-ambiguous` for affected records | Preserve Findings and show Unresolved Detections. |
| Complete comparable Resolution Coverage proves absence | `open` | `resolved` | `verified-absent` | Append Verified Resolution. |
| Detection uniquely continues a resolved Finding | `resolved` | `open` | `observed` | Append reopen event after the prior resolution. |
| Detection after resolution has no credible predecessor | `resolved` remains unchanged; new record has no prior state | old stays `resolved`; new Finding is `open` | old `verified-absent`; new `observed` | Open a new Finding rather than inventing a reopen. |

### 7.2 Ordering rules

- Git ancestry, a validated explicit predecessor relationship, or another source-ordering fact establishes lifecycle order. Wall-clock timestamps describe processing but do not establish ancestry.
- An out-of-order Observation Snapshot can add older observations or refine an Introduction Conclusion. It cannot reverse a later Verified Resolution merely because it was ingested last.
- Divergent branch snapshots remain parallel. A report selects a Lineage or shows branch-specific states rather than presenting one global state that hides the divergence.
- For archives or source states without Git identity, lifecycle transition requires an explicit validated predecessor relationship. Otherwise the snapshot remains useful as positive evidence but unordered for transition claims.

---

## 8. Failure and uncertainty behavior

| Condition | Required product response | Claims blocked |
| --- | --- | --- |
| Source parse fails | Persist the source-level parse failure and diagnostics, then mark every affected Atomic Observation as not executed. | Absence and resolution for every affected rule by SourceUnit pair. |
| Rule is unsupported or throws | Persist the exact outcome and reason without committing buffered proposals. | Absence and resolution for that pair. |
| Source or rule is excluded | Record who or what selected the exclusion and its scope. | Absence and resolution for that excluded scope. |
| Required semantic or historical capability is unavailable or ambiguous | Record capability state and reason. | Every claim that declares that capability required. |
| Semantic Revision or effective configuration is incomparable | Keep prior Finding state and show comparison dimensions. | Continuity, resolution, reopening, or introduction according to the blocked claim. |
| Several Continuity Candidates remain | Emit continuity ambiguity and retain all candidates and current Detections. | Automatic continuation, new identity, resolution, or reopening for the ambiguous set. |
| Selected scope shrinks | Show the scope delta and affected Findings as unverified. | Resolution for Findings no longer covered. |
| File is deleted or renamed | Evaluate the eligible relocation scope and Git evidence. | Resolution until relocation coverage is complete and unambiguous. |
| Git history is shallow, rewritten, missing, or has incomparable parents | Report bounded or unavailable Introduction Conclusion. | Exact introduction. |
| Working tree is dirty | Use content identity and record dirty state. | Exact committed Git introduction for that source state. |
| Snapshot arrives out of order or from a divergent branch | Place it in its actual Lineage or leave it unordered. | Any transition inferred only from arrival time. |
| Persistence is interrupted | Leave the previous verifiable lifecycle unchanged and surface recovery information. | All transitions from the incomplete write. |
| Lifecycle data has an unknown schema or broken reference | Refuse interpretation of the affected data and identify the unreadable boundary. | Clean, resolved, or complete-history claims based on that data. |

---

## 9. Cross-cutting quality requirements

### 9.1 Determinism and reproducibility

- Canonical export and reconciliation outcomes must be stable for identical ordered inputs, regardless of filesystem traversal, concurrency, locale, or wall-clock time.
- Every external fact that can change a conclusion, including Git history boundary and capability identity, must be captured in provenance rather than reread silently during explanation.
- The product must support replay from persisted Observation Snapshots and compatibility decisions without reinterpreting them under newer defaults.

### 9.2 Integrity and recoverability

- Persisting an Observation Snapshot and its resulting Lifecycle Events must be atomic from the user's perspective.
- Retry after interruption must be idempotent.
- Corrections and migrations must retain an audit trail. They cannot overwrite evidence in place without leaving the prior state inspectable.
- Unknown or partially migrated data fails closed for lifecycle claims.

### 9.3 Performance and scale

- Normal current-source analysis must not require full Git-history traversal.
- Git introduction inference must be demand-driven and bounded by an explicit user-visible history scope or work budget.
- Reconciliation must expose candidate counts, ambiguity counts, and stage timing so realistic repository benchmarks can set release budgets.
- R3 must benchmark cold ingestion, repeated ingestion, one-revision incremental reconciliation, read-only explanation, and bounded history inference on small, medium, and large repositories before numeric budgets are frozen.

### 9.4 Privacy and security

- Default operation is local and offline and requires no telemetry or external source transmission.
- Lifecycle artifacts must document whether they contain paths, source excerpts, repository identifiers, authorship data, or commit messages.
- The minimum evidence required to audit a conclusion should be retained. Raw source retention is not required by this PRD.
- Human and machine reports must escape source-derived text and warn that paths and history metadata may reveal private repository structure.

### 9.5 Compatibility

- Lifecycle artifacts use an explicit report kind and schema version independent of released syntax-only and compiler-sidecar artifacts.
- Consumers reject unsupported major schema versions before reading state.
- Migration preserves Finding IDs, event ordering, provenance, ambiguity, and prior conclusions or reports exactly which property cannot be preserved.

---

## 10. Scope

### 10.1 In scope for R3

- Immutable Observation Snapshots with claim-relevant provenance and Atomic Observation outcomes.
- Persistent Finding IDs, open and resolved states, and append-only Lifecycle Events.
- Deterministic Continuity and Reconciliation with an explicit ambiguity result.
- Purpose-specific Semantic Revision and configuration Comparability.
- Verified Resolution from complete comparable Resolution Coverage.
- Reopening after verified absence when unique Continuity is supported.
- First Observation and exact, bounded, or unavailable Git Introduction Conclusions.
- Read-only inventory, explain, snapshot inspection, and versioned audit export.
- Deterministic replay, idempotent ingestion, corruption detection, and compatibility behavior.
- Acceptance fixtures containing real Git histories, moves, copies, merges, rule revisions, and incomplete analyses.

### 10.2 Non-goals

- Lifecycle-based CI gates, debt budgets, age limits, service-level objectives, policy evaluation, waivers, or suppressions. Existing current-run `--fail-on-violation` behavior remains separate.
- Manual adjudication that forces a continuity or lifecycle outcome.
- Automatic source edits, refactoring, remediation generation, or issue closure.
- Ownership assignment, assignee workflow, comments, due dates, ticket synchronization, or team collaboration features.
- A GUI, IDE extension, hosted service, repository chat, or notification system.
- Using a path, line, message, embedding, nearest neighbor, or vector-store key as Finding identity.
- Proving one universal introduction commit when history or rule semantics do not support it.
- Requiring Git for First Observation or for positive current-source lifecycle facts.
- Retaining complete source archives as a prerequisite for audit.
- Modifying released report schemas or making the optional compiler sidecar part of syntax-only output.
- Defining the R2 vector-store implementation. If vector retrieval contributes Continuity Candidates, its output remains candidate evidence under the same R3 proof rules.

---

## 11. Acceptance tests

Acceptance fixtures must exercise the public library or CLI surface against persisted artifacts and, for history behavior, real temporary Git repositories. A test passes only when both lifecycle output and explanation/audit evidence match the expected claim.

| ID | Scenario | Expected result |
| --- | --- | --- |
| AT-1 | One rule commits a Detection while another rule fails in the same snapshot. | The Detection can open a Finding; the snapshot is incomplete; no affected prior Finding is resolved. |
| AT-2 | A rule by SourceUnit pair commits zero Detections under comparable semantics and complete selected scope. | Absence is available for that pair and may contribute to Resolution Coverage. |
| AT-3 | A previously observed Finding shifts lines after comments are inserted. | One unique supported continuation keeps the Finding ID; location history changes; no new Finding opens. |
| AT-4 | A declaration moves to a renamed file with unique continuity evidence. | The Finding ID continues and the explanation lists the move evidence; Git rename data alone is not presented as proof. |
| AT-5 | A declaration containing a Detection is copied into two files. | The original-to-successor assignment is continuity-ambiguous unless rule-specific evidence distinguishes it; current Detections remain visible; no candidate is resolved. |
| AT-6 | Two prior Findings collapse into one current Detection. | The many-to-one relationship stays ambiguous unless exactly one assignment is sufficiently supported; no prior Finding is auto-closed. |
| AT-7 | A later comparable repository-scope snapshot commits every required Atomic Observation and contains no continuing or ambiguous Detection. | The Finding transitions from open to resolved with Evidence State `verified-absent` and an auditable resolution event. |
| AT-8 | The Detection is missing, but its source parse fails in the later run. | The Finding stays open with Evidence State `unverified`; explanation names the parse failure. |
| AT-9 | The prior file falls outside a changed-files run or is explicitly excluded. | The Finding stays open and the scope gap is reported; no clean or resolved claim is emitted. |
| AT-10 | The prior file is deleted and the comparable repository scope fully covers eligible successors with no continuing or ambiguous Detection. | The Finding resolves; the explanation identifies the deletion, complete relocation coverage, and committed absence evidence. |
| AT-11 | The prior file is deleted but only its directory is analyzed. | The Finding remains unverified because relocation coverage is incomplete. |
| AT-12 | Rule Identity is equal but Semantic Revision changes with no compatibility declaration. | The later snapshot is incomparable for lifecycle claims; the Finding is not resolved or continued across the boundary. |
| AT-13 | An explicit tested compatibility declaration allows continuity but not absence in one direction. | A present Detection can continue the Finding in that direction; a missing Detection cannot resolve it; explanation records the directional decision. |
| AT-14 | A uniquely matching Detection appears after Verified Resolution. | The same Finding reopens, preserving the earlier resolution and recording recurrence. |
| AT-15 | A post-resolution Detection has no credible predecessor. | The old Finding stays resolved and a new Finding opens with a separate First Observation. |
| AT-16 | Linear Git history has verified absence at parent P and a comparable Detection first present at child C. | Introduction Conclusion is exact at C, with P and C linked as evidence. |
| AT-17 | The earliest analyzed positive revision is preceded by an unparseable or unavailable revision. | Introduction Conclusion is bounded or unavailable, never exact. |
| AT-18 | A merge contains the Detection, one parent contains it, and the other parent is clean. | Introduction inference follows the positive parent lineage and does not attribute introduction to the merge. |
| AT-19 | A merge contains the Detection and every comparable parent has verified absence. | Introduction Conclusion is exact at the merge when the remaining provenance and scope requirements are satisfied. |
| AT-20 | History is shallow or the working tree is dirty. | First Observation remains available; exact committed introduction is blocked with a specific reason. |
| AT-21 | An older snapshot arrives after a newer snapshot, and two snapshots belong to divergent branches. | Arrival order causes no lifecycle reversal; branch-specific Lineages remain explicit. |
| AT-22 | The same ordered snapshots are ingested twice and replayed with different concurrency. | Finding IDs, events, ambiguities, and canonical export are identical, with no duplicates. |
| AT-23 | A user requests an explanation for an unverified or ambiguous Finding. | Output includes every blocker and candidate needed to understand why no transition occurred; human and machine output agree. |
| AT-24 | A lifecycle artifact has an unknown schema or a broken Detection reference. | The affected history is rejected explicitly; no apparently complete or resolved replacement is synthesized. |
| AT-25 | R3 is enabled alongside existing schema-2 reports and current-run `--fail-on-violation`. | Existing report bytes and gate semantics remain unchanged; lifecycle output is independently identifiable. |
| AT-26 | A later run omits or cannot initialize an optional semantic or historical capability required by the rule that produced the Finding. | Missing Detection is unverified; the Finding does not resolve; explanation identifies the unavailable capability. |
| AT-27 | An unrelated Detection later occupies the same path, line, and column as a prior Finding but fails its continuity contract. | Location reuse does not continue or reopen the prior Finding; the Detection is new or unresolved according to candidate evidence. |

---

## 12. Success metrics and release gates

### 12.1 Primary correctness metrics

- **SM-1 - False Verified Resolution rate:** 0 across the curated acceptance and adversarial corpus. A false resolution is any transition produced without complete comparable Resolution Coverage. Validates FR-20 through FR-23.
- **SM-2 - False automatic Continuity rate:** 0 across curated move, rename, copy, split, merge, and ambiguity fixtures. Ambiguous cases must remain ambiguous. Validates FR-10 through FR-15.
- **SM-3 - Audit coverage:** 100% of Lifecycle Events and Introduction Conclusions link to their supporting Observation Snapshots, Detections, comparison basis, and any limiting reasons. Validates FR-9, FR-19, FR-23, and FR-25 through FR-34.
- **SM-4 - Incomplete-analysis safety:** 100% of fixtures containing a relevant parse failed, unsupported, failed, excluded, omitted, or incomparable Atomic Observation block Verified Resolution. Validates FR-3, FR-4, and FR-21.
- **SM-5 - Replay determinism:** repeated and concurrent replay produces identical canonical lifecycle output and zero duplicate Findings or events. Validates FR-5, FR-10, and FR-34.
- **SM-6 - Introduction precision:** 0 exact Introduction Conclusions without verified comparable absence in every relevant parent, except a verified repository-root revision that has no parent. Validates FR-26 through FR-30.

### 12.2 Operational metrics to baseline before release

- Snapshot ingestion time and peak memory by repository size.
- Incremental reconciliation time per changed Detection and affected candidate set.
- Read-only inventory and single-Finding explanation latency.
- Git revisions analyzed, cache reuse, and wall time for each bounded introduction query.
- Rates of unique Continuity, new Finding creation, Unresolved Detections, and continuity ambiguity on representative repositories.
- Lifecycle artifact size per 1,000 snapshots and per 10,000 Findings.

Numeric performance budgets must be set from these benchmarks before release rather than invented in this PRD.

### 12.3 Counter-metrics

- A higher automatic Continuity rate is not success if it increases false merges.
- A higher exact-introduction rate is not success if it converts bounded or unavailable history into unsupported precision.
- A lower open-Finding count is not success if it comes from exclusions, incomplete runs, semantic incompatibility, or data loss.
- A lower ambiguity rate is not success if the product silently opens duplicates or chooses candidates without sufficient evidence.

### 12.4 Release gates

R3 is releasable when:

1. AT-1 through AT-27 pass through the real lifecycle surface.
2. SM-1 through SM-6 meet their correctness targets on both curated and adversarial fixtures.
3. Existing schema-2 golden artifacts and current-run gate behavior remain unchanged.
4. Persistence interruption and retry demonstrate atomicity and idempotency.
5. Corrupt and unknown-version fixtures fail closed.
6. Small, medium, and large repository benchmarks establish explicit documented performance budgets.
7. Human and machine explanations expose the same uncertainty and transition reasons.

---

## 13. Risks and mitigations

| Risk | Product mitigation |
| --- | --- |
| False continuity makes unrelated debt look like one long-lived Finding. | Require unique sufficient evidence, default semantic changes to incomparable, and preserve ambiguity. |
| False resolution hides active debt. | Require complete comparable Resolution Coverage and fail closed on every non-proof outcome. |
| Copy, split, and merge cases inflate or erase inventory. | Keep current Detections visible as unresolved and avoid assigning or closing identities while cardinality is ambiguous. |
| Git history creates expensive or non-reproducible work. | Make inference demand-driven, bounded, provenance-recorded, and independent from normal current-source analysis. |
| Repository rewrites invalidate apparent ancestry. | Preserve content and history boundary provenance and recompute conclusions as refinements rather than rewriting facts. |
| Rule evolution silently changes historical meaning. | Make Comparability explicit, directional, claim-specific, and tested. |
| Persistent artifacts expose private repository metadata. | Default to local operation, document retained fields, minimize raw source, and warn before publishing exports. |
| A database or migration failure produces a clean-looking empty history. | Use atomic writes, integrity checks, idempotent retry, and explicit unreadable boundaries. |

---

## 14. Open questions

These questions do not relax the invariants above. They must be resolved before architecture or release planning freezes the corresponding surface.

1. What is the minimum rule-owned continuity evidence contract for each Detection class, and which common evidence may the engine provide without rules authoring identity?
2. What default Resolution Coverage is required for a moved or deleted SourceUnit in repository, package, target, directory, and changed-files analysis modes?
3. How should users select a Lineage when several branches or worktrees contain different current states for the same Finding?
4. Which cross-revision compatibility declarations are expressive enough for directional continuity and absence without becoming an unrestricted rule-specific program?
5. What bounded Git-history defaults provide useful Introduction Conclusions on large repositories while keeping normal analysis predictable?
6. How long must snapshots, events, and source-derived evidence be retained, and what audit-preserving compaction is allowed?
7. How should repository forks, remote changes, submodules, and history rewrites affect repository identity and Finding portability?
8. Which path and authorship fields should be redacted by default in exported audit artifacts?
9. What measured repository sizes and latency targets define the small, medium, and large performance gates?
10. Should a future release add manual adjudication for ambiguity, and if so, how will it remain a clearly labeled operator decision rather than observed fact?

---

## 15. Assumptions index

- R3 can be specified independently of whether every R2 analysis capability ships first; it consumes any canonical Detection that meets the R1 contract.
- Repository maintainers are the primary journey actor because no named persona or separate UX brief was supplied.
- Read-only lifecycle reporting excludes manual adjudication and policy enforcement in R3; both remain possible follow-up products with separate provenance rules.
- Numeric performance targets require representative benchmark evidence and remain open until those measurements exist.
