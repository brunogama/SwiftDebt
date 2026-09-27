# R3 real-source lifecycle evidence

This probe measures lifecycle outcomes on three fixed revisions of SwiftDebt's own Swift source. A separate two-commit subset of unmodified SwiftDebt files proves bounded Introduction cache behavior. It complements the generated 10/100/1,000-file latency workload in [R3 lifecycle performance](r3-lifecycle-performance.md). The source is a real project history, including production and test Swift files, but one project's history cannot establish rates for other repositories. All current public built-in lifecycle rules have SemanticRevision 1, so this probe does not establish cross-revision Comparability rates.

---

## Fixed corpus

| Order | SwiftDebt source revision | Swift files | Role |
| --- | --- | ---: | --- |
| 1 | `c509396a5492106f94e74df718c84edfe2dbd894` | 188 | Initial source state |
| 2 | `9c7d1c2d38c1c975786fd70b3a3d83c1428cf5af` | 322 | Broad feature and rule evolution |
| 3 | `a4a3c6d680feb2a221f417048b4e34de65175234` | 331 | Later source state |

The runner reads `Sources/**/*.swift` and `Tests/**/*.swift` from these exact Git objects. It copies those bytes into three commits of a disposable Git repository, preserving relative paths. It records a SHA-256 over paths and contents for each source state, each disposable Git revision, the runner, fixture, and evidence support scripts, and the `swift-debt` executable. The source revisions must be present in the local Git object database; a shallow checkout missing them fails rather than selecting nearby revisions.

The second state adds many files, so its rates reflect this particular history and source selection. Test fixtures embedded in Swift string literals remain string literals when the CLI parses the real test files. The runner reports the actual rule identities and semantic revisions that emitted canonical Detections, not the rule names predicted from source text.

---

## Run

Use a clean checkout at the candidate implementation commit. Build the release executable from that commit, then run:

```sh
swift build -c release --jobs 2
python3 -m unittest scripts.tests.test_r3_representative_evidence
python3 scripts/run_r3_representative_evidence.py \
  --swift-debt .build/release/swift-debt \
  --output /tmp/swiftdebt-r3-real-source-evidence.json
```

The runner removes a previous output file before starting. A command failure, timeout, unsupported artifact schema, missing field, unaccounted Detection, absent Introduction profile, stale reuse, or cold-parity mismatch leaves no passing output. It uses the public `analyze`, `lifecycle export`, and `lifecycle infer-introduction` commands. Artifacts and query profiles live outside the disposable source repository. Every lifecycle artifact is decoded by the public canonical export path and compared to its persisted JSON.

Per Snapshot, the runner counts canonical Detections by Rule Identity and SemanticRevision. It classifies each Detection as a unique continuation, new Finding, or Unresolved Detection and fails unless those counts sum to the Detection total. It also records the number of `continuity-ambiguous` Lifecycle Events. Rates divide by current Snapshot Detections; the first Snapshot has no predecessor, so incremental interpretation uses Snapshots 2 and 3.

---

## Observed results

The checked-in [raw evidence](../benchmarks/r3-lifecycle/evidence/real-source-swiftdebt.json) was produced at clean runner commit `9f8381f52eb7e724bb08b9f17dcd115d97de11b3` with Release binary SHA-256 `94b1ca70e873075d051022e030d109fcff664ca3f47bb42650cb61b92fd1eaa2`. Public canonical export matched the persisted artifact after each of the three analyses. Ten rules were selected per Snapshot; six distinct Rule Identities emitted Detections, all at SemanticRevision 1.

| Snapshot | Detections | Unique continuations | New Findings | Unresolved Detections | Ambiguity Events |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1: `c509396` | 94 | 0 | 94 | 0 | 0 |
| 2: `9c7d1c2` | 195 | 45 (23.08%) | 84 (43.08%) | 66 (33.85%) | 49 (25.13%) |
| 3: `a4a3c6d` | 198 | 105 (53.03%) | 3 (1.52%) | 90 (45.45%) | 73 (36.87%) |

Each row's continuations, new Findings, and unresolved Detections sum to its Detection count. Ambiguity Events are a separate Finding-transition count and can overlap unresolved Detection groups; dividing Events by Detections does not make them another mutually exclusive Detection outcome. The raw evidence records all six rule-specific counts, source digests, fixture revisions, artifact hashes and sizes, and single-run wall times. These observations describe this fixed SwiftDebt history, not a cross-project population or calibrated latency distribution.

---

## Bounded Introduction cache proof

The whole-source corpus contains Detections in historical revisions. SwiftDebt's current cache only reuses atomically complete historical Observation Snapshots with **zero** Detections, so a warm query against that corpus should not claim a hit. The cache probe uses a separate disposable repository with two commits made from unmodified real SwiftDebt files at revision `a4a3c6d680feb2a221f417048b4e34de65175234`:

1. `Sources/SwiftDebtSyntax/BuiltInRuleCatalog.swift` alone, a source state the CLI must certify with zero Detections.
2. The same file plus `Sources/SwiftDebtKit/AnalysisProfiler.swift`, whose actual `@unchecked Sendable` declaration opens one Finding under the built-in rule.

The runner selects that canonical Finding and runs the same public bounded query four times:

| Query | Artifact input | Per-file limit | Required result |
| --- | --- | ---: | --- |
| Cold | Pre-query lifecycle artifact | 1 MiB | Accepted, two analyzed and zero reused revisions |
| Mixed warm | Cold result | 1 MiB | Already present, one analyzed and one reused revision, byte-identical artifact |
| Invalidated | Warm result | 2 MiB | Accepted, two analyzed and zero reused revisions |
| Forced cold oracle | Pre-query artifact copy | 2 MiB | Accepted, two analyzed and zero reused revisions, same conclusion and evidence as invalidated |

Each query has an explicit maximum of **three Git revisions** for this two-commit history. The profile must account for all evidence revisions as analyzed plus reused, stay within the limit, match the persisted Introduction Conclusion, and report a positive operation duration. The source file limit changes the effective historical analysis contract and must invalidate the previous cache entry. Forced cold means starting from the saved pre-query artifact; there is no hidden CLI flag.

These are numeric **work and reuse** budgets. They are not calibrated wall-time ceilings. The script records raw wall time and in-process duration for all four queries; a latency ceiling needs repeated uncontended samples on an identified machine class before it can be called a release budget.

The Release run recorded two analyzed and zero reused revisions for the cold query, one analyzed and one reused for the identical warm query, and two analyzed and zero reused after changing the file limit. The forced-cold oracle also analyzed two and reused zero. The warm query left the artifact byte-identical; the invalidated and forced-cold conclusions matched. All four operations stayed within the three-revision work budget.

---

## Release interpretation

This probe must report its measured rates and rule coverage before its result is cited. A zero ambiguity rate is a measured observation for this corpus, not proof that ambiguity is rare in user repositories. The generated capacity and latency workloads have a similarly narrow shape. R3 PRD section 12.2 still needs additional fixed repositories with different languages of Swift code, architectural patterns, team histories, source sizes, moves/copies, and actual ambiguity cases before cross-project rates are representative. Current public lifecycle selection cannot exercise two semantic revisions of the same built-in rule in one artifact. That gate needs a supported versioned rule-author/loading path or a migration-tested historical-binary protocol; fabricating a revision change in JSON would bypass the public observation boundary.
