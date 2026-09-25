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

The store serializes one schema-versioned `swiftdebt-lifecycle` artifact. Schema 2 persists a snapshot parent graph and per-branch Finding event bases. Ingestion holds an advisory exclusive lock, writes by atomic replacement, orders pending snapshots by their explicit predecessor relationship, and leaves bytes unchanged when the same snapshot is retried. A validated schema 1 artifact migrates in memory without changing its bytes; the next accepted atomic ingestion writes schema 2 while preserving every existing Snapshot, Finding, Detection, and Lifecycle Event ID.

The supported CLI write path accepts only an artifact location:

```text
swift-debt analyze PATH --lifecycle-artifact ARTIFACT
```

`AnalysisService` derives the Observation Snapshot from the same in-memory `SourceUnit` values passed to `RuleEngine` and `Analyzer`. It computes the source digest, rule-analysis configuration fingerprint, capability state, engine version, Git source state, and lineage. None of those values are accepted as CLI input.

## Authority boundary

---

The public snapshot conversion accepts only an R1 `AnalysisSnapshot`; raw arrays of sources, atomics, and Detections are package scoped. A lifecycle caller can therefore attach provenance to engine-owned observations, but it cannot use the public initializer to fabricate a canonical Detection.

Structural evidence and direct-parent source rename evidence also have package-scoped construction. `RuleEngine` derives the former from validated syntax, and the CLI analysis service derives the latter from Git. Neither is accepted as a caller-provided continuity key.

Provenance remains a trusted integration input for direct library callers. A syntactically valid digest alone does not prove that an external caller computed it from the analyzed checkout. The CLI path closes that gap for command-line ingestion by constructing provenance inside `AnalysisService` and exposing only the artifact destination.

The lifecycle audit query commands remain read-only:

```text
swift-debt lifecycle inventory ARTIFACT [--head SNAPSHOT_ID] [--format text|json]
swift-debt lifecycle explain ARTIFACT FINDING_ID [--head SNAPSHOT_ID] [--format text|json]
swift-debt lifecycle snapshot ARTIFACT SNAPSHOT_ID [--format text|json]
```

These commands decode and validate the entire artifact before reporting. They never repair, replace, or partially interpret unreadable history.

When the artifact has several graph heads, inventory reports one projection per Finding and head. `--head` selects one current branch projection explicitly. An unscoped explanation retains the complete append-only Finding event graph and renders the lifecycle and evidence state for every head. A head-scoped explanation returns only that head's event path, supporting snapshots, and unresolved evidence. It includes an Introduction Conclusion only when its recorded Git head matches a persisted snapshot on the selected head's ancestor path; conclusions without that graph evidence remain available in the unscoped explanation. Snapshot inspection reports its parent, children, and head status.

Introduction inference is a separate, explicit artifact mutation:

```text
swift-debt lifecycle infer-introduction ARTIFACT FINDING_ID \
  --repository PATH --max-revisions INTEGER [--max-file-bytes INTEGER] \
  [--format text|json]
```

Normal `analyze` runs never traverse history. The inference command has a required positive revision budget and analyzes committed trees through `git archive` without checking out or modifying them. It appends an immutable Introduction Conclusion attempt and then renders the same validated explanation used by the read-only command. An identical retry leaves artifact bytes unchanged.

## Git introduction evidence

---

Each Introduction Conclusion persists the Git `HEAD`, working-tree state and status digest, shallow-repository state, requested starting revision, maximum revision count, unvisited frontier, and every examined revision. An examined revision records its parents and either a complete engine-produced Observation Snapshot or a specific availability gap. Historical snapshots contain source identity, configuration fingerprint, capability state, engine version, repository scope, Atomic Observations, and structural Detection evidence.

Artifact decode recomputes `exact`, `bounded`, or `unavailable` from that raw evidence. An exact conclusion requires a uniquely matching structural Detection on the original SourceUnit path and committed target-rule evidence for every selected SourceUnit. Every direct parent must prove comparable absence, or exactly one positive parent is followed farther through history. A merge is exact only when every parent proves absence. A tampered exact revision, missing parent record, failed parse, partial scope, configuration mismatch, capability mismatch, or unavailable object fails closed.

Dirty and shallow repositories retain First Observation but block exact committed attribution with machine-readable reasons. Exhausting the revision budget produces a bounded conclusion with the unexamined frontier. A later deeper query appends a refinement without changing the Finding, its First Observation, or earlier conclusions.

Historical cross-file continuity remains bounded because this slice does not persist per-edge Git rename evidence for archived revisions. The inference command currently reproduces the default directory selection with the requested maximum file size. If that fingerprint differs from the opening Observation, comparability fails rather than accepting caller-supplied configuration claims.

## CLI provenance derivation

---

The analyze-to-artifact path records:

| Provenance field | Engine-owned derivation |
| --- | --- |
| Source content identity | SHA-256 over a length-framed, sorted encoding of the exact `SourceUnit` path, module, and content values used by both engines. |
| Git source identity | Full validated `HEAD` commit ID, clean or modified state, and the source content digest. Git state is captured immediately before and after the one source read. |
| Observation scope | Repository only for a directory analysis rooted at the Git repository root with no configured exclusions and no skipped symbolic links; otherwise partial with reasons. |
| Configuration fingerprint | Versioned SHA-256 over source selection kind, effective exclusions, maximum file size, and the exact selected Rule Identities. Semantic rule contracts are bound separately into the snapshot identity. |
| Capability availability | `syntax-analysis` available. Parse and rule failures remain explicit source and Atomic Observation outcomes rather than unavailable capability claims. |
| Engine identity | The schema-2 report engine version produced by the same analysis run. |
| Snapshot graph | Existing edge for an exact retry, or one clean single-parent Git edge to the unique persisted snapshot of that parent revision. The parent does not need to remain a graph head. |
| Source rename evidence | Canonical Git rename edges between the direct parent and current revision, captured from the same clean repository state. |

The Git cleanliness check excludes only untracked or ignored lifecycle artifacts, lock files, and exact `--output`, `--profile-output`, and `--stamp` paths requested for that run when they are inside the repository. A Git-tracked output remains visible to provenance. Directory discovery also omits the requested generated stamp SourceUnit. These rules prevent ordinary SwiftDebt outputs from changing the source state it records without hiding tracked or unrelated changes, which continue to block successor claims.

The first snapshot may use a content-only identity when the input is outside Git. A later content-only snapshot cannot be ordered automatically. Dirty working trees, merge commits, skipped commits, duplicate but different evidence for one revision, and disconnected histories also fail closed. A clean single-parent child can extend a persisted parent even after another child has already been observed, so sibling Git branches remain parallel graph heads. The CLI does not infer a successor from invocation time.

Each Finding keeps one stable identity and an append-only event graph. A non-opening event names the exact predecessor event from its parent snapshot projection. A branch can therefore resolve a Finding while its sibling keeps the same Finding open without either event becoming evidence on the other branch. Artifact validation rejects missing parents, cycles, event bases that cross sibling paths, and non-opening events whose basis is not the parent projection's terminal event. Merge snapshots remain unsupported and fail before mutation.

The local SHA-256 implementation exists because the current R2 digest helper validates but does not compute digests. Consolidation with R2's `RepositorySHA256` is an integration task after that separate branch lands; this slice does not couple to unmerged code.

## Conservative continuity

---

`RuleEngine` now attaches versioned `DetectionStructuralEvidence` at the R1 emission boundary. A rule supplies the validated SwiftSyntax construct that represents the detected subject. The engine computes:

- a SHA-256 digest over the subject's source-accurate token sequence, excluding trivia and absolute location; and
- a SHA-256 digest over the ordered enclosing declaration kinds and header tokens.

The package-scoped evidence initializer prevents lifecycle clients from supplying a continuity key. The persisted `ObservedDetection` field is optional so artifacts written by the preceding lifecycle slice still decode. Missing or differently versioned evidence remains ambiguous.

Continuity reconciliation builds a bipartite candidate graph per Rule Identity. It makes an automatic assignment only when one prior Finding and one current Detection are each other's only supported edge. Every other connected component remains unresolved with its complete candidate set.

| Current evidence | Result |
| --- | --- |
| Exact subject and declaration digest on the same SourceUnit path | Supported continuity; a changed line or column is recorded as move evidence. |
| Exact digests across SourceUnit paths plus the matching direct-parent Git rename edge | Supported continuity with both structural and Git evidence. |
| Exact digests across paths without that Git edge | Unresolved with `cross-file-move-uncorroborated`. |
| Same declaration but changed subject, or same subject in a changed declaration | Unresolved as a partial structural candidate. |
| One candidate has multiple successors, or multiple candidates share a successor | Unresolved with `structural-assignment-not-unique`. |
| Both digests differ in the same SourceUnit, and neither side has a stronger edge | Unresolved with `same-source-structural-divergence`; an edited occurrence cannot be ruled out. |
| Both digests differ across SourceUnit paths without a Git rename edge | No structural predecessor; a current Detection can open a new Finding. |
| Semantic, configuration, capability, or source identity is incomparable | Unverified; no continuity or absence conclusion is made. |

Path, line, column, message, Git rename data, and source similarity never establish identity by themselves. A SourceUnit path is used only to retain an unresolved candidate after both structural digests change and no stronger edge exists. In particular, same-location reuse cannot continue a Finding, and an identical declaration deleted from one file then added to another stays unresolved unless Git corroborates the direct-parent rename. A uniquely supported match after Verified Resolution records `reopened` and preserves the earlier resolution event.

The existing schema-2 report models and renderers are unchanged. Structural evidence flows only through R1's in-memory `Detection` and the independently identified lifecycle artifact.

## Semantic comparability

---

`RuleContract` owns directional, claim-specific compatibility declarations. A destination Semantic Revision may declare that one earlier revision supports `continuity`, `absence`, or both. `RuleEngine` rejects duplicate sources and declarations that do not point from an earlier revision into the destination revision. Lifecycle callers cannot add declarations through the public `SnapshotRule` initializer; the authoritative snapshot conversion copies them from the engine-produced `AnalysisSnapshot`.

Different Semantic Revisions remain incomparable by default. A declaration relaxes only the revision check for its listed claims. Configuration fingerprints and engine versions must still match, both source identities must support comparison, and capability sets must match with every capability available. Resolution and exact introduction also keep their independent repository-scope and committed-observation requirements.

Every continuation, resolution, reopening, and Introduction Conclusion persists an immutable `SemanticComparisonBasis` containing:

- the claim and compatible or blocked decision;
- both snapshot IDs and full selected rule contracts;
- both configuration fingerprints, capability sets, source identities, scopes, and engine versions; and
- the exact destination-owned declaration when one applies.

Artifact validation recomputes each decision and the lifecycle outcome from those persisted dimensions. Removing or altering a basis causes decode to fail closed. Explanations render the direction, claim, decision, snapshot pair, configuration pair, engine pair, and declaration rationale.

The lifecycle configuration digest is versioned independently from Semantic Revision. This permits an exact effective-configuration match across rule revisions while the snapshot ID continues to bind the complete selected Semantic Revisions and compatibility declarations. Existing schema-2 analysis and report bytes remain unchanged.

## Verified absence

---

A committed empty Atomic Observation proves absence only for its exact rule by SourceUnit pair. Repository resolution is a stronger claim.

The reducer and artifact decoder both recompute a resolution proof. A resolution is valid only when all of these conditions hold:

- the resolving snapshot is a later processed descendant on the selected snapshot-graph path;
- repository scope is complete;
- both source identities are available;
- effective configuration, engine version, and capability sets are comparable;
- every declared capability is available;
- the selected Rule Identity and Semantic Revision is persisted even when the eligible SourceUnit set is empty;
- that exact rule has an Atomic Observation for every selected SourceUnit;
- every covered Atomic Observation committed zero Detections;
- the covered Atomic Observation IDs are exhaustive and exact; and
- no same-rule Detection or Unresolved Detection remains for the Finding in that snapshot.

Git-backed snapshots also persist the engine's repository-relative source selection and direct-parent
Swift SourceUnit rename and deletion evidence. A partial selection records the affected prior source as
out of scope and cannot verify resolution. A deletion can support resolution only when the current
snapshot has complete comparable repository coverage of the eligible successor search space.
Resolution follows the persisted snapshot parent path, so an observed sequence of Git rename or deletion
edges remains part of the later proof. A real CLI fixture covers two consecutive renames, partial
observations at both edges, and final complete repository coverage.
Lifecycle-enabled analysis can persist that proof after the sole Swift SourceUnit is deleted: the
schema-2 report contains zero input files, while the Observation Snapshot retains the selected rules
and an empty rule by SourceUnit product. Analysis without lifecycle ingestion keeps the existing
no-sources failure.

A tampered resolution that points at an existing failed or unrelated Atomic Observation is rejected. Unknown schemas, invalid digests, broken Detection or candidate Finding references, invalid snapshot graph edges, sibling event leakage, inconsistent ordering metadata, and malformed parse outcomes also fail closed.

## Acceptance status

---

All implemented acceptance tests use the real R1 `RuleEngine`, the public lifecycle conversion or query API, and a persisted artifact. CLI tests execute the built `swift-debt` process.

| PRD acceptance | Status in this slice | Evidence or gap |
| --- | --- | --- |
| AT-1 | Direct | A committed Detection opens while another Atomic Observation fails. |
| AT-2 | Direct | Committed zero proves pair-level absence without implying repository Resolution Coverage. |
| AT-3 | Direct | A real CLI/Git fixture inserts comments, preserves one Finding ID, records the new location, and explains the structural match and location move. |
| AT-4 | Direct | A real `git mv` fixture preserves one Finding only when exact structural evidence and the direct-parent Git rename edge agree; explanation lists both. |
| AT-5 | Direct | A real CLI fixture copies an anchored declaration into two files; both current Detections stay visible and unresolved, and the prior Finding remains open. |
| AT-6 | Direct | A real CLI fixture collapses two structurally identical prior Findings into one current Detection; both Findings remain open and the complete candidate set is persisted. |
| AT-7 | Direct | Complete comparable committed absence creates an audited resolution, including a real clean direct-child Git CLI run. |
| AT-8 | Direct | A real parse failure records not-executed atomics and blocks resolution. |
| AT-9 | Direct | Real CLI/Git fixtures explicitly exclude the prior SourceUnit and select only another changed file through a manifest. Both keep the Finding open and record the exact selection gap and incomplete relocation coverage. |
| AT-10 | Direct | Complete comparable repository coverage resolves direct-child Git deletion with other sources or with no remaining Swift SourceUnit. The persisted proof retains the selected rules, deletion edge, complete relocation coverage, and committed absence. Deletion evidence also survives an intermediate partial observation. |
| AT-11 | Direct | The same direct-child deletion analyzed only through its containing directory stays open and unverified because relocation coverage is incomplete. |
| AT-12 | Direct | An undeclared Semantic Revision change blocks continuity and resolution. |
| AT-13 | Direct | A rule-owned revision-2 declaration permits revision-1-to-2 continuity while absence, the reverse direction, and undeclared revision changes remain blocked. Real CLI explanations and persisted Introduction Conclusions expose the exact decision basis. |
| AT-14 | Direct | A real three-revision CLI fixture opens, resolves, and uniquely reopens the same Finding while retaining all three events. |
| AT-15 | Direct | A post-resolution Detection in another file, with different subject and declaration structure and no Git rename edge, opens a separate Finding and leaves the original resolved. |
| AT-16 | Direct | A real linear Git fixture persists the detected child and verified-absent parent, then reports the child as exact. |
| AT-17 | Direct | A real unparseable parent produces a bounded conclusion with an incomplete historical-observation reason. |
| AT-18 | Direct | A real merge with one positive and one absent parent follows the positive lineage and attributes introduction to its earlier commit. |
| AT-19 | Direct | A real merge that introduces the Detection after both parents prove absence is exact at the merge. |
| AT-20 | Direct | Real dirty-worktree and shallow-clone fixtures retain First Observation and block exact attribution with specific reasons. |
| AT-21 | Direct | A real Git fixture analyzes one root and two sibling children in both arrival orders. One branch resolves the shared Finding while the other keeps it open; both retain one Finding ID, independent event projections, explicit graph heads, head-scoped CLI output, byte-identical replay, and no sibling evidence leakage. Dirty, merge, disconnected, and broken-parent inputs fail closed. |
| AT-22 | Partial | Retry and reverse-arrival replay preserve canonical bytes, and real CLI replay is byte-identical; concurrent replay and interruption injection remain open. |
| AT-23 | Partial | Persisted human and JSON queries expose blockers; real CLI tests prove text and JSON parity for every ambiguity candidate and blocker and for unverified reasons. CLI snapshot inspection shows derived Git, configuration, capability, engine, scope, selected-rule, and rename provenance. Full human/machine audit parity remains open. |
| AT-24 | Direct | Unknown schema, broken references, reference-valid false resolution proof, and invalid candidate references fail closed. |
| AT-25 | Direct | A real CLI fixture compares schema-2 stdout byte for byte with lifecycle disabled and verifies `--fail-on-violation` keeps status 1 while retrying the same lifecycle snapshot without mutation. |
| AT-26 | Partial | Capability provenance is validated and unavailable capability cannot support decoded resolution; a real optional-provider run remains open. |
| AT-27 | Direct | A real CLI fixture reuses the exact path, line, and column after resolution with different subject and declaration structure; the old Finding retains its Verified Resolution and the current Detection remains separately unresolved. An edited subject in the same declaration also stays unresolved. |

## Remaining product gaps

---

The current slice completes the first-observation, line-move, corroborated file-rename, recurrence, changed-files boundary, multi-edge relocation coverage, clean deletion resolution, replay, and persisted inspection portions of UJ-1. It does not complete the full journey. The missing pieces are:

- rule-specific evidence that can safely distinguish copied or semantically edited occurrences beyond the conservative structural anchor;
- cross-file continuity without a direct-parent Git rename, which remains unresolved rather than inferred from identical code;
- directional effective-configuration compatibility beyond exact fingerprint equality;
- historical configuration reproduction beyond the default directory selection and maximum-file-size input;
- archived cross-file introduction continuity with persisted Git rename corroboration;
- complete human and machine audit parity;
- concurrent replay and interrupted-write fault injection; and
- measured artifact and query performance budgets.

The structural evidence code currently contains a local SHA-256 implementation. R2's `RepositorySHA256` exists on a separate unmerged branch, so consolidation remains an integration task rather than a dependency on unpublished code.
