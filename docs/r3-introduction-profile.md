# R3 introduction profiling

Git introduction inference can write a separate operational profile without changing the lifecycle artifact or explanation output:

```sh
swift-debt lifecycle infer-introduction ARTIFACT FINDING_ID \
  --repository REPOSITORY --max-revisions 32 \
  --profile-output /tmp/swiftdebt-introduction-profile.json \
  --format json
```

The profile output must be outside the analyzed repository. SwiftDebt removes a prior file at that exact output path when output preparation begins, writes the replacement atomically only after a successful query, and rejects lifecycle-artifact, lock-file, directory, and Swift-source destinations. After preparation begins, a failed query cannot leave an older profile at that path. Callers must also require a successful current command and should use a fresh path for each benchmark sample because an interruption before preparation cannot authenticate a pre-existing file.

The lifecycle artifact and operational sidecar are separate atomic files rather than one cross-file transaction. If the sidecar write fails after a conclusion is recorded, the command fails while the validated artifact remains authoritative. A retry may therefore report `already-present`.

The schema-1 `swiftdebt-lifecycle-introduction-profile` sidecar records:

| Field | Meaning |
| --- | --- |
| `reportKind` | Stable `swiftdebt-lifecycle-introduction-profile` identity. |
| `schemaVersion` | Sidecar contract version, currently `1`. |
| `findingID` | Finding selected by the public command. |
| `maximumRevisions` | User-visible Git work budget. |
| `maximumFileBytes` | Historical source-size limit used by analysis. |
| `evidenceRevisionCount` | Historical revision records supporting the persisted conclusion. |
| `analyzedRevisionCount` | Revision records rebuilt during this invocation. |
| `reusedRevisionCount` | Persisted historical revision records consumed without reanalysis. |
| `frontierRevisionCount` | Parent revisions left outside the bounded query. |
| `recordingStatus` | Whether the conclusion was appended or was already present byte-for-byte. |
| `operationElapsedNanoseconds` | Monotonic in-process duration through conclusion recording; excludes sidecar serialization and subsequent explanation rendering. |

`evidenceRevisionCount` always equals `analyzedRevisionCount + reusedRevisionCount`. An analyzed count means the invocation rebuilt the historical revision record, including an explicit availability-gap record when source analysis could not complete. It does not claim every revision produced a complete Observation Snapshot. The sidecar is operational evidence and is not part of the lifecycle claim. Artifact decode continues to recompute each Introduction Conclusion from its persisted historical evidence.

---

## Current measurement boundary

The current provider rebuilds every historical revision record before the artifact store checks whether identical evidence is already present. It therefore reports zero reused revisions on both a cold query and an identical repeat. `recordingStatus: already-present` proves persistence idempotence only; it is not a cache hit.

The lifecycle benchmark measures cold introduction and same-artifact repeat as separate public CLI operations. Each sample validates the profile against the persisted conclusion, retains the raw analyzed and reused revision counts, and measures process wall time and peak resident memory. This establishes an honest zero-reuse baseline for a later cache change. It does not claim that an introduction cache exists, establish a numeric release budget, or satisfy the representative small, medium, and large repository gate by itself.

---

## Safety boundary for future reuse

A future cache may increase `reusedRevisionCount` only when it can prove that persisted history matches the current query identity. At minimum that identity includes the Finding and starting revision, repository HEAD, clean working-tree status digest, shallow-history boundary, revision and file-size budgets, engine version, selected Rule Identities and Semantic Revisions, source-selection policy, and every availability gap. Dirty, shallow, unavailable, rewritten, differently configured, or deeper-budget queries must remain misses or refinements. Reuse cannot change conclusion bytes, skip artifact validation, turn missing history into absence, or relabel `already-present` as a cache hit.
