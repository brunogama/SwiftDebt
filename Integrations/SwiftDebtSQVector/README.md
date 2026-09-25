# Optional SQVector exact candidate index

This separate Swift package links SQVector's `SQVectorStatic` product and exposes
an R2-owned exact candidate-index interface. The base SwiftDebt package does not
depend on SQVector and does not initialize this adapter during syntax-only work.

The SQVector-backed implementation is compiled for macOS 26 and iOS 26. The
same public interface reports an explicit unavailable state on the other
SwiftDebt platforms.

## Local setup

From the SwiftDebt repository root, link a complete local `sqvector-swift`
checkout. The link is ignored by Git.

```sh
mkdir -p .vendor
ln -s /absolute/path/to/sqvector-swift .vendor/sqvector-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path Integrations/SwiftDebtSQVector --jobs 2
```

The checkout must expose `SQVectorStatic` from its nested
`Packages/SQVector` package.

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

Schema version 1 persists the following identity in the database manifest and
requires exact equality whenever the index is reopened:

| Field | Meaning |
|---|---|
| `namespace` | Caller-owned repository and source-snapshot namespace |
| `provider` | Embedding provider name |
| `providerVersion` | Provider implementation version or explicit `unavailable` |
| `model` | Model or vocabulary identity |
| `modelRevision` | Model revision or explicit `unavailable` |
| `dimensions` | Vector dimension |
| `metric` | Cosine or L2 |
| `projectionRevision` | Semantic projection revision |
| `schemaVersion` | Adapter storage schema version |

An unavailable provider version or model revision is preserved as unavailable;
the adapter does not invent an identifier. That state cannot establish
cross-environment embedding compatibility. Callers must select a new namespace
or rebuild derived state whenever an unreported provider or model may have
changed.

---

## Qualification status

This exact-index slice was exercised against the clean local SQVector revision
`1766942c8d7cf093e1ee66323b2c855624451d70` on its local
`feature/static-product` branch. The revision is recorded here separately from
the database manifest.

This remains a local dependency because no published SQVector revision exposes
`SQVectorStatic`. It therefore does not satisfy the exact pinned dependency and
platform qualification required by R2 FR-23.

The current exact path also has these limits:

- vec0 insertion fails at the tested SQVector revision with an internal
  validity-blob error tracked in
  [SQVector issue 329](https://github.com/brunogama/sqvector-swift/issues/329);
- scalar vector SQL functions are not registered on every pooled reader, as
  tracked in
  [SQVector issue 346](https://github.com/brunogama/sqvector-swift/issues/346);
- the `SQVectorStatic` dependency graph still compiles unrelated SQVector
  modules and has not passed the minimal-slice or binary-size qualification;
- package version and SQVector source revision are documented but are not yet
  persisted as compatibility fields in this adapter manifest;
- source-snapshot compatibility depends on the caller supplying a precise
  namespace; and
- ANN recall, hybrid retrieval, scale, latency, memory, index-size, and frozen
  corpus gates remain Research.

The local contract covers the exact insert, replacement, deletion, persistence,
dimension, namespace, provider, model, metric, projection, bounded retrieval,
and filtering behaviors in FR-24. It is an exact reference adapter, not evidence
that the complete R2 similarity and index gate has passed.
