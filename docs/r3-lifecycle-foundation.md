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

## Authority boundary

---

The public snapshot conversion accepts only an R1 `AnalysisSnapshot`; raw arrays of sources, atomics, and Detections are package scoped. A lifecycle caller can therefore attach provenance to engine-owned observations, but it cannot use the public initializer to fabricate a canonical Detection.

Provenance remains a trusted integration input. A syntactically valid digest does not prove that it was computed from the analyzed checkout. The current `swift-debt analyze` service does not expose one authoritative value for source identity, complete scope, effective configuration, capability availability, and lineage. For that reason this slice does not add an analyze-to-store CLI path. A later integration must compute and validate those values before it calls `ingest`.

The CLI is read-only:

```text
swift-debt lifecycle inventory ARTIFACT [--format text|json]
swift-debt lifecycle explain ARTIFACT FINDING_ID [--format text|json]
swift-debt lifecycle snapshot ARTIFACT SNAPSHOT_ID [--format text|json]
```

These commands decode and validate the entire artifact before reporting. They never repair, replace, or partially interpret unreadable history.

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
| AT-7 | Direct | Complete comparable committed absence creates an audited resolution. |
| AT-8 | Direct | A real parse failure records not-executed atomics and blocks resolution. |
| AT-9 | Open | No prior-Finding changed-files exclusion fixture. |
| AT-10 | Open | Eligible relocation coverage for deletion is not modeled. |
| AT-11 | Open | Directory-only deletion coverage is not modeled. |
| AT-12 | Direct | An undeclared Semantic Revision change blocks continuity and resolution. |
| AT-13 | Open | Directional compatibility declarations are not modeled. |
| AT-14 | Open | Unique supported reopen is not available without continuity evidence. |
| AT-15 | Open | Post-resolution new occurrence classification is not implemented. |
| AT-16 to AT-20 | Open | Git introduction inference is not implemented. |
| AT-21 | Direct | Reverse arrival and divergent lineage fixtures preserve source order. |
| AT-22 | Partial | Retry and reverse-arrival replay preserve canonical bytes; concurrent replay and interruption injection remain open. |
| AT-23 | Partial | Persisted human and JSON queries expose blockers; full candidate parity and audit export remain open. |
| AT-24 | Direct | Unknown schema, broken references, reference-valid false resolution proof, and invalid candidate references fail closed. |
| AT-25 | Regression gate | Lifecycle uses a separate report kind and full existing tests guard schema-2 output; no dedicated byte snapshot was added here. |
| AT-26 | Partial | Capability provenance is validated and unavailable capability cannot support decoded resolution; a real optional-provider run remains open. |
| AT-27 | Direct | Exact path, line, and column reuse remains unresolved and does not continue the Finding. |

## Remaining product gaps

---

The current slice does not complete UJ-1. The missing pieces are:

- authoritative analyze-to-store provenance from `AnalysisService`;
- engine-owned structural continuity evidence and unique assignment;
- observed-again, moved, reopened, and new-after-resolution transitions;
- explicit selection and exclusion coverage for moves and deletions;
- directional semantic and configuration compatibility declarations;
- Git introduction conclusions and merge handling;
- complete human and machine audit parity;
- concurrent replay and interrupted-write fault injection; and
- measured artifact and query performance budgets.
