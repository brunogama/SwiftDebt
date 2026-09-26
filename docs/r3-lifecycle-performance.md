# R3 lifecycle performance gate

This gate measures the public `swift-debt` executable. By default it creates three temporary, local Git repositories, runs the real lifecycle commands, and records every wall-clock and peak resident-memory sample. The generated repositories and artifacts are removed after measurement. No network access is needed.

---

## Workloads

| Tier | Swift files | Source lines | Finding shape |
| --- | ---: | ---: | --- |
| Small | 10 | 500 | One built-in `try!` Detection per file |
| Medium | 100 | 5,000 | One built-in `try!` Detection per file |
| Large | 1,000 | 50,000 | One built-in `try!` Detection per file |

Each repository has a clean root commit without debt, a second commit introducing the Detections, and a third commit moving one Detection by a comment-only line shift. Commits have fixed authorship metadata and dates. The script records the resulting Git revisions and the binary SHA-256 in the evidence file.

Each timed command has a 600-second limit. A timeout kills its process group and fails the run; it is not recorded as a passing sample.

The six timed public operations are fresh cold ingestion, byte-identical replay, one-revision incremental ingestion, inventory, one-Finding explanation, and introduction inference with a four-revision work budget. Incremental ingestion includes source discovery, parsing, reconciliation, validation, serialization, and process startup. It also requests the public `--profile-output` sidecar and records the product's dedicated `reconciliationElapsedNanoseconds`, prior Finding candidate count, evaluated and credible pairs, and continuity outcomes for every measured run. The validator binds that sidecar to the new Snapshot and verifies its counts against the persisted Finding continuity. The CLI wall time remains an end-to-end upper bound for reconciliation. The artifact record includes actual bytes, Snapshot and Finding counts, Lifecycle Event kinds, unresolved Detection counts, and Introduction Conclusion count. The script requires every original Finding ID to remain unique and observed after the edit, verifies the shifted Detection's location, parses the inventory and explanation JSON, rejects mutation by read-only commands, and requires an exact introduction conclusion.

---

## Run and enforce

Use a clean checkout at the candidate release commit. Resolve dependencies before measurement, then build the release executable once:

```sh
swift build -c release --jobs 2
python3 scripts/run_r3_lifecycle_benchmark.py \
  --swift-debt .build/release/swift-debt \
  --output benchmarks/r3-lifecycle/evidence/MEASUREMENT.json \
  --runs 3 --warmups 1 \
  --budgets benchmarks/r3-lifecycle/budgets.json
```

`--budgets` requires all three tiers, one warmup, and at least three measured runs. It checks the fixture version, OS family, architecture, CPU model, and Swift version before comparing each tier's median wall time, maximum sampled peak RSS, and the largest cold, incremental, or introduction artifact with calibrated ceilings. The script writes raw evidence before returning a budget failure. The budget file and measurements must come from calibration on the integrated release candidate; they are not included in this draft. Omit `--budgets` only while calibrating a new release platform or workload. Record the candidate binary and source commit with each passing result; a result from another binary, machine class, or artifact schema is not evidence for this release.

For a bounded public-CLI proof of the reconciliation sidecar before calibration, run:

```sh
python3 scripts/run_r3_lifecycle_benchmark.py \
  --swift-debt .build/release/swift-debt \
  --output /tmp/swiftdebt-r3-reconciliation-smoke.json \
  --tiers small --runs 1 --warmups 0
```

Inspect `tiers.small.incrementalReconciliation` in that output. This one-sample smoke result is not a release budget or host calibration.

The evidence JSON records the Swift version, OS, architecture, CPU label, binary digest, source commit, fixture revisions, warmup and run counts, raw samples, medians, maximum RSS, examined Git revision count, and remaining history frontier. The first run of each operation is discarded by default. All subsequent samples are retained. Introduction cache reuse is not exposed by the current artifact or CLI, so this gate does not claim a cache-reuse measurement.

---

## Interpretation and limits

The three tiers are deterministic synthetic source shapes. Once calibrated, they establish repeatable CLI budgets for these shapes; they do not establish throughput for arbitrary Swift repositories or compare SwiftDebt with another analyzer. The one-file edit leaves the other source contents unchanged, so its incremental result measures a narrow continuity case. Report its observed and ambiguous event counts alongside time rather than optimizing for a higher automatic match rate.

Artifact sizes in the evidence are actual sizes at one and two Snapshots and 10, 100, or 1,000 Findings. Dividing these values by the observed counts may help plan capacity, but extrapolating them to 1,000 Snapshots or 10,000 Findings is not a measured scale result. The PRD's explicit large-history and large-Finding capacity requirement remains open until product-generated artifacts at those cardinalities are measured. The reconciliation sidecar measures the affected prior Finding candidates in this single-rule fixture; it does not establish candidate-set behavior on representative multi-rule repositories. Its numeric stage ceiling remains uncalibrated. Representative ambiguity rates and introduction cache-reuse measurement also remain open. Passing these CLI budgets alone does not satisfy all R3 release-performance requirements in PRD sections 9.3, 12.2, and 12.4.

Budgets are machine-class specific. A changed Swift toolchain, SwiftSyntax version, artifact schema, fixture shape, or hardware class requires a new calibration with raw evidence and documented ceilings. A release cannot claim this gate merely because the script exits successfully on a different environment.
