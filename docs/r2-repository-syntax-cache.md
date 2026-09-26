# R2 repository syntax-fact cache

SwiftDebt stores repository syntax facts in a local, content-addressed cache
when repository evidence is enabled. The cache changes how SwiftDebt obtains
facts. It does not change repository rule semantics or the schema 1 repository
evidence report.

---

## Storage model

The cache is one versioned JSON file. Its entries are ordered by normalized
source path. The file uses report kind
`swiftdebt-repository-syntax-cache-store` and schema version 1. Each entry
records:

- the source path, module, and SHA-256 content digest;
- the remaining Data Clumps and Repeated Switches fact budgets at that source;
- the extracted syntax facts and parse diagnostics; and
- the shared compatibility identity for the cache file.

The compatibility identity records the cache and fact schema versions, the
projection revision, the exact SwiftSyntax package version and revision, the
semantic revision of each consuming rule, and the configuration that affects
fact extraction.

The incoming budgets are dependencies. If an earlier source changes the number
of extracted facts, SwiftDebt recomputes later entries whose incoming budgets
changed. This keeps the existing repository-wide limits intact.

This cache covers the deterministic Data Clumps and Repeated Switches syntax
facts used by the repository sidecar. It does not cache the schema 2 per-file
analysis, lifecycle artifacts, or semantic projection and vector state. The
cache retains normalized identifiers, types, switch shapes, locations, and
parse diagnostics. It stays local and makes no network request.

| Design | One-file reuse | Preserves repository budgets | Decision |
| --- | --- | --- | --- |
| Cache the complete repository snapshot | No | Yes | Rejected because every edit rebuilds all facts. |
| Cache unbounded facts for each source | Yes | No | Rejected because cold analysis can exceed the declared fact budget. |
| Cache each source with its incoming budgets | Yes | Yes | Selected. |

---

## Atomic updates and recovery

SwiftDebt encodes the complete next cache before it writes. The final write uses
an atomic replacement in the cache directory. A reader observes either the old
complete file or the new complete file.

SwiftDebt validates the report kind, schema version, canonical encoding,
payload integrity digest, compatibility identity, entry order, entry
uniqueness, source digests, budget state, and fact locations before reuse.
Invalid JSON, partial bytes, altered canonical values, and invalid entries cause
a complete rebuild. An unreadable or unwritable cache fails the run instead of
using stale facts.

---

## CLI use

Repository analysis uses a persistent file under the user cache directory by
default. The repository path identifies the default file. The cache stays
outside the checkout, so analysis does not create an untracked repository file.
Explicit cache and activity-report paths are treated as generated outputs when
SwiftDebt records Git provenance. A second identical run therefore does not
mark its own evidence as coming from a modified working tree.

Use an explicit cache and write the versioned activity report:

```sh
swift-debt analyze Sources \
  --repository-evidence .swift-debt/repository-evidence.json \
  --repository-cache /tmp/swiftdebt-repository-facts.json \
  --repository-cache-report /tmp/swiftdebt-repository-cache-report.json
```

Ignore all retained entries and replace the cache atomically:

```sh
swift-debt analyze Sources \
  --repository-evidence .swift-debt/repository-evidence.json \
  --repository-cache /tmp/swiftdebt-repository-facts.json \
  --rebuild-repository-cache
```

Disable reads and writes for one run with `--no-repository-cache`.

To clear retained state, remove the file at `storage.location` in the activity
report. To rebuild it in one deterministic step, run the same analysis with
`--rebuild-repository-cache`; SwiftDebt ignores every retained entry and
atomically replaces the file.

The activity report records the storage location, byte count, compatibility
identity, repository source snapshot digest, disposition, selected, reused,
recomputed, and removed source counts, invalidation reasons, and the network
request count. The report kind is
`swiftdebt-repository-syntax-cache` and its schema version is 1.
Compatibility invalidations distinguish cache and fact schema, projection,
provider, rule semantics, and extraction configuration changes.
Each invalidation count is the number of sources affected by that reason;
counts can overlap when more than one compatibility dimension changes.

---

## Acceptance gate

The release gate runs the real `swift-debt` executable through these states:

1. A cold run recomputes every selected source.
2. An unchanged warm run reuses every source and does not rewrite the cache.
3. A one-file edit recomputes that source and any entry whose incoming budget
   changed.
4. Corrupt JSON, partial bytes, and an unknown schema rebuild all selected
   sources without using retained facts.
5. A forced rebuild replaces compatible state.
6. A network-denied run produces the same repository evidence as the matching
   unsandboxed run.
7. Every state preserves the existing schema 2 reports and the schema 1
   repository evidence bytes.
