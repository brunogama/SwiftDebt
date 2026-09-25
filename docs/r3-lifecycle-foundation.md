# R3 lifecycle foundation

This document describes the first persistent lifecycle slice. It is a foundation for R3, not an R3 release. The release gate in `docs/prd-r3.md` still requires AT-1 through AT-27 and the stated correctness, interruption, compatibility, and performance evidence.

## Public surface

---

`SwiftDebtLifecycle` converts an engine-produced `AnalysisSnapshot` into an immutable `ObservationSnapshot`. The conversion preserves each R1 rule by SourceUnit result as one `AtomicObservationOutcome` and records only committed canonical Detections.

Callers supply `SnapshotProvenance`, including:

- a validated SHA-256 source content identity;
- a validated SHA-256 effective configuration fingerprint;
- selected scope and capability states;
- engine version; and
- an explicit lineage sequence and predecessor.

The library persists the snapshot with:

```swift
let observation = try ObservationSnapshot(
    id: snapshotID,
    provenance: provenance,
    analysis: analysisSnapshot
)
let result = try LifecycleArtifactStore(artifactURL: artifactURL).ingest(observation)
```

The store serializes one schema-versioned `swiftdebt-lifecycle` artifact. Ingestion holds an advisory exclusive lock, writes by atomic replacement, orders pending lineage snapshots by their explicit predecessor relationship, and leaves bytes unchanged when the same snapshot is retried.

The supported CLI write path accepts only an artifact location:

```text
swift-debt analyze PATH --lifecycle-artifact ARTIFACT
```

`AnalysisService` derives the Observation Snapshot from the same in-memory `SourceUnit` values passed to `RuleEngine` and `Analyzer`. It computes the source digest, rule-analysis configuration fingerprint, capability state, engine version, Git source state, and lineage. None of those values are accepted as CLI input.

## Authority boundary

---

The public snapshot conversion accepts only an R1 `AnalysisSnapshot`; raw arrays of sources, atomics, and Detections are package scoped. A lifecycle caller can therefore attach provenance to engine-owned observations, but it cannot use the public initializer to fabricate a canonical Detection.

Provenance remains a trusted integration input for direct library callers. A syntactically valid digest alone does not prove that an external caller computed it from the analyzed checkout. The CLI path closes that gap for command-line ingestion by constructing provenance inside `AnalysisService` and exposing only the artifact destination.

The lifecycle query commands remain read-only:

```text
swift-debt lifecycle inventory ARTIFACT [--format text|json]
swift-debt lifecycle explain ARTIFACT FINDING_ID [--format text|json]
swift-debt lifecycle snapshot ARTIFACT SNAPSHOT_ID [--format text|json]
```

These commands decode and validate the entire artifact before reporting. They never repair, replace, or partially interpret unreadable history.

## CLI provenance derivation

---

The analyze-to-artifact path records:

| Provenance field | Engine-owned derivation |
| --- | --- |
| Source content identity | SHA-256 over a length-framed, sorted encoding of the exact `SourceUnit` path, module, and content values used by both engines. |
| Git source identity | Full validated `HEAD` commit ID, clean or modified state, and the source content digest. Git state is captured immediately before and after the one source read. |
| Observation scope | Repository only for a directory analysis rooted at the Git repository root with no configured exclusions and no skipped symbolic links; otherwise partial with reasons. |
| Configuration fingerprint | Versioned SHA-256 over source selection kind, effective exclusions, maximum file size, and the exact Rule Identities and Semantic Revisions emitted by R1. |
| Capability availability | `syntax-analysis` available. Parse and rule failures remain explicit source and Atomic Observation outcomes rather than unavailable capability claims. |
| Engine identity | The schema-2 report engine version produced by the same analysis run. |
| Lineage | Existing position for an exact retry, or the unique clean single-parent Git successor of one clean artifact head. |

The Git cleanliness check excludes only untracked or ignored lifecycle artifacts, lock files, and exact `--output`, `--profile-output`, and `--stamp` paths requested for that run when they are inside the repository. A Git-tracked output remains visible to provenance. Directory discovery also omits the requested generated stamp SourceUnit. These rules prevent ordinary SwiftDebt outputs from changing the source state it records without hiding tracked or unrelated changes, which continue to block successor claims.

The first snapshot may use a content-only identity when the input is outside Git. A later content-only snapshot cannot be ordered automatically. Dirty working trees, merge commits, skipped commits, duplicate but different evidence for one revision, and disconnected histories also fail closed. The CLI does not infer a successor from invocation time.

The local SHA-256 implementation exists because the current R2 digest helper validates but does not compute digests. Consolidation with R2's `RepositorySHA256` is an integration task after that separate branch lands; this slice does not couple to unmerged code.

## Conservative continuity

---

R1 `Detection` currently records Rule Identity, Semantic Revision, severity, location, and message. It does not carry an engine-owned normalized subject identity, enclosing declaration identity, or a rule-specific continuity contract.

Path, line, column, message, and an unvalidated caller key cannot establish historical identity. This slice therefore applies these rules:

| Current evidence | Result |
| --- | --- |
| Detection with no prior same-lineage Finding for its Rule Identity | Open a Finding. |
| Detection with one or more prior same-lineage candidates | Keep it as an Unresolved Detection and record ambiguity or semantic incomparability. |
| Same path, line, and column as a prior Detection | Treat location as insufficient and leave continuity unresolved. |
| No Detection under incomplete or incomparable coverage | Keep the prior lifecycle state and append an unverified event. |
| No Detection under verified complete comparable coverage | Resolve an open Finding. |

This prevents false moves, renames, copies, splits, merges, and reopens. It also means AT-3, AT-4, and AT-14 cannot pass until R1 emits sufficient engine-owned structural evidence and R3 defines unique assignment rules for that evidence.

## Verified absence

---

A committed empty Atomic Observation proves absence only for its exact rule by SourceUnit pair. Repository resolution is a stronger claim.

The reducer and artifact decoder both recompute a resolution proof. A resolution is valid only when all of these conditions hold:

- the resolving snapshot is a later processed snapshot in the Finding's lineage;
- repository scope is complete;
- both source identities are available;
- effective configuration, engine version, and capability sets are comparable;
- every declared capability is available;
- the exact Rule Identity and Semantic Revision has an Atomic Observation for every selected SourceUnit;
- every covered Atomic Observation committed zero Detections;
- the covered Atomic Observation IDs are exhaustive and exact; and
- no same-rule Detection or Unresolved Detection remains for the Finding in that snapshot.

A tampered resolution that points at an existing failed or unrelated Atomic Observation is rejected. Unknown schemas, invalid digests, broken Detection or candidate Finding references, inconsistent lineage order, and malformed parse outcomes also fail closed.

## Acceptance status

---

All implemented acceptance tests use the real R1 `RuleEngine`, the public lifecycle conversion or query API, and a persisted artifact. CLI tests execute the built `swift-debt` process.

| PRD acceptance | Status in this slice | Evidence or gap |
| --- | --- | --- |
| AT-1 | Direct | A committed Detection opens while another Atomic Observation fails. |
| AT-2 | Direct | Committed zero proves pair-level absence without implying repository Resolution Coverage. |
| AT-3 | Open | No engine-owned structural identity for a moved Detection. |
| AT-4 | Open | No declaration identity or rename reconciliation contract. |
| AT-5 | Partial | One-to-many cardinality stays ambiguous, but the fixture does not copy a declaration into two files. |
| AT-6 | Direct | Two prior Findings and one current Detection remain ambiguous. |
| AT-7 | Direct | Complete comparable committed absence creates an audited resolution, including a real clean direct-child Git CLI run. |
| AT-8 | Direct | A real parse failure records not-executed atomics and blocks resolution. |
| AT-9 | Open | No prior-Finding changed-files exclusion fixture. |
| AT-10 | Open | Eligible relocation coverage for deletion is not modeled. |
| AT-11 | Open | Directory-only deletion coverage is not modeled. |
| AT-12 | Direct | An undeclared Semantic Revision change blocks continuity and resolution. |
| AT-13 | Open | Directional compatibility declarations are not modeled. |
| AT-14 | Open | Unique supported reopen is not available without continuity evidence. |
| AT-15 | Open | Post-resolution new occurrence classification is not implemented. |
| AT-16 to AT-20 | Open | Git introduction inference is not implemented. |
| AT-21 | Partial | Reverse arrival and divergent library fixtures preserve source order; the CLI accepts only a verified direct Git parent and rejects dirty, merge, or disconnected successors. Real divergent Git lineages in one artifact remain open. |
| AT-22 | Partial | Retry and reverse-arrival replay preserve canonical bytes, and real CLI replay is byte-identical; concurrent replay and interruption injection remain open. |
| AT-23 | Partial | Persisted human and JSON queries expose blockers and CLI snapshot inspection shows derived Git, configuration, capability, engine, and scope provenance; full candidate parity and audit export remain open. |
| AT-24 | Direct | Unknown schema, broken references, reference-valid false resolution proof, and invalid candidate references fail closed. |
| AT-25 | Direct | A real CLI fixture compares schema-2 stdout byte for byte with lifecycle disabled and verifies `--fail-on-violation` keeps status 1 while retrying the same lifecycle snapshot without mutation. |
| AT-26 | Partial | Capability provenance is validated and unavailable capability cannot support decoded resolution; a real optional-provider run remains open. |
| AT-27 | Direct | Exact path, line, and column reuse remains unresolved and does not continue the Finding. |

## Remaining product gaps

---

The current slice completes the first-observation, clean direct-child resolution, replay, and persisted inspection portions of UJ-1. It does not complete the full journey. The missing pieces are:

- engine-owned structural continuity evidence and unique assignment;
- observed-again, moved, reopened, and new-after-resolution transitions;
- a real incomplete changed-files CLI observation between first observation and resolution;
- explicit selection and exclusion coverage for moves and deletions;
- directional semantic and configuration compatibility declarations;
- Git introduction conclusions and merge handling;
- complete human and machine audit parity;
- concurrent replay and interrupted-write fault injection; and
- measured artifact and query performance budgets.
