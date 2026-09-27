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

## Current reuse boundary

The provider can reuse a successful historical Observation Snapshot from an already validated Introduction Conclusion for the same Finding. Reuse still performs fresh local Git parent lookup, archive extraction, source discovery, source reads, and source hashing. It skips Swift parsing and built-in rule execution only after the fresh source state matches the persisted record.

The current match is deliberately narrow. The prior query must use the same Finding, First Observation revision, repository HEAD, clean status digest, non-shallow history, revision limit, and ancestry limitations. Each reused revision must then match its freshly observed parents, source identity and content digest, scope, source selection, requested file-size limit and configuration fingerprint, engine version, current built-in rule contracts, capability state, source paths, lineage, and recomputed Snapshot ID. Only atomically complete Observation Snapshots with no Detections are reusable. A Detection severity, message, or structural payload can change without an existing persisted implementation fingerprint, so revisions containing Detections remain cold. Unavailable records and snapshots containing parse failures, unsupported analysis, or rule failures are also always rebuilt. If more than one compatible persisted value disagrees, SwiftDebt rebuilds instead of choosing one.

Dirty or shallow repositories, changed work budgets or configuration, missing Git objects, archive/read failures, rewritten history, and mismatched provenance remain cold. Corrupt or unknown artifacts continue to fail during authoritative artifact loading rather than falling back to a clean-looking result. Reuse changes neither Introduction evidence nor explanation bytes, and the existing locked atomic artifact write remains the only persistence authority.

The lifecycle benchmark measures cold introduction and same-artifact repeat as separate public CLI operations. Each sample validates the profile against the persisted conclusion, retains the raw analyzed and reused revision counts, and measures process wall time and peak resident memory. The deterministic two-revision CLI fixture records `2 analyzed / 0 reused` when cold and `1 analyzed / 1 reused` on an identical clean repeat: the revision without a Detection is reused while the detected revision remains cold. This proves the narrow partial-reuse path and its counters. It does not establish a numeric release budget or satisfy the representative repository gate by itself.

`recordingStatus` and reuse counts answer different questions. `already-present` says the recomputed Introduction evidence was already persisted byte-for-byte. `reusedRevisionCount` says this invocation safely skipped syntax and rule analysis for validated historical records. Neither field alone is a performance budget.
