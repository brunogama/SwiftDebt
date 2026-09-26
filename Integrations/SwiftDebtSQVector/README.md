# Optional SQVector exact candidate index

This separate Swift package links SQVector's `SQVectorStatic` product and exposes
an R2-owned exact candidate-index interface. The base SwiftDebt package does not
depend on SQVector and does not initialize this adapter during syntax-only work.

The SQVector-backed implementation is selected for macOS 26 and iOS 26. The
same public interface reports an explicit unavailable state on the other
SwiftDebt platforms.

## Pinned dependency

The integration resolves the root package from
`https://github.com/brunogama/sqvector-swift.git` at the exact immutable
revision `aafd9ae601826112978127c7cb611c94ab8a2e06`. That revision exposes the
`SQVectorStatic` product from the repository root; the linked target imports its
public `SQVector` module. The root also preserves SQVector's existing automatic
`SwiftSQLiteVec` product.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path Integrations/SwiftDebtSQVector --jobs 2
```

The pin is not descended from the repository's `v1.0.0` tag. The runtime
identity therefore records the package version as explicitly unavailable and
records the exact revision above. `LocalCandidateIndexIdentity` binds this
identity automatically, so callers cannot substitute a different package
identity during normal construction.

SQVector also keeps the nested `Packages/SQVector` static product for
repository-local builds. A clean source-control consumer cannot select that
nested manifest: SwiftPM resolves the repository root and rejects local package
dependencies from a revision-based dependency. The pinned root manifest
declares the required targets directly so the same static product resolves from
the Git URL.

---

## Exact index contract

`SQVectorExactCandidateIndex` stores vectors and metadata in ordinary SQLite
tables through SQVector. It applies metadata filters in SQL, decodes the
filtered vectors, and uses SQVector's Swift distance implementation for an
exact scan. This path does not use vec0 or an approximate index.

The adapter provides:

- atomic insert or replacement by candidate ID;
- atomic metadata and candidate deletion without relying on foreign-key
  cascade configuration;
- file-backed persistence and reopen checks;
- cosine and L2 distance;
- deterministic ordering by distance, then candidate ID UTF-8 bytes;
- conjunctive exact-match metadata filters;
- a configurable filtered-scan budget, with a default of 10,000 candidates;
- result limits from 1 through 256; and
- explicit incomplete results for an exceeded budget, corrupt stored vectors,
  or failed distance computation.

The adapter rejects dimension mismatches and non-finite values before writes
and queries. Cosine indexes also reject zero-norm query and stored vectors. It
does not return a truncated top-k when the filtered candidate set exceeds the
work budget.

---

## Compatibility identity

Schema version 2 persists the following identity in the database manifest and
requires exact equality whenever the index is reopened:

| Field | Meaning |
|---|---|
| `namespace` | Caller-owned index namespace |
| `provider` | Embedding provider name |
| `providerVersion` | Provider implementation version or explicit `unavailable` |
| `model` | Model or vocabulary identity |
| `modelRevision` | Model revision or explicit `unavailable` |
| `dimensions` | Vector dimension |
| `metric` | Cosine or L2 |
| `projectionRevision` | Semantic projection revision |
| `sourceSnapshotDigest` | Typed SHA-256 digest of the exact source snapshot |
| `sqVectorPackage.version` | Published version or explicit `unavailable` |
| `sqVectorPackage.revision` | Exact immutable SQVector source revision |
| `schemaVersion` | Adapter storage schema version |

An unavailable provider version or model revision is preserved as unavailable;
the adapter does not invent an identifier. That state cannot establish
cross-environment embedding compatibility. Callers must select a new namespace
or rebuild derived state whenever an unreported provider or model may have
changed.

Schema v1 storage and the earlier draft schema v2 package-version layout are
rejected because they cannot establish the current source-snapshot and package
compatibility contract. The caller must rebuild them with the current v2
identity. The adapter does not infer a package version from branch or tag
names.

---

## Qualification status

This exact-index slice pins SQVector revision
`aafd9ae601826112978127c7cb611c94ab8a2e06` on the published
`feature/static-product` branch. The manifest and runtime compatibility
identity use the same revision. The absence of a compatible release tag is
represented explicitly instead of assigning a fabricated package version.

The current exact path also has these limits:

- vec0 insertion fails at the tested SQVector revision with an internal
  validity-blob error tracked in
  [SQVector issue 329](https://github.com/brunogama/sqvector-swift/issues/329);
- scalar vector SQL functions are not registered on every pooled reader, as
  tracked in
  [SQVector issue 346](https://github.com/brunogama/sqvector-swift/issues/346);
- the root `SQVectorStatic` dependency graph still compiles unrelated SQVector
  modules, produces a large archive, and dynamically links GRDB;
- macOS is the only platform with a completed runtime contract gate so far;
  iOS and the explicit unavailable paths still require clean platform builds;
- ANN recall, hybrid retrieval, scale, latency, memory, index-size, and frozen
  corpus gates remain Research.

The contract covers the exact insert, replacement, deletion, persistence,
dimension, namespace, provider, model, metric, projection, bounded retrieval,
source-snapshot, package-compatibility, and filtering behaviors in FR-24 and
FR-25. It is an exact reference adapter, not evidence that the complete R2
similarity and index gate has passed. FR-23 remains open until the supported
platform, dependency-size, and release qualification gates are complete.
