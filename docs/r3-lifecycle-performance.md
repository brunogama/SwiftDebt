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

The seven timed public operations are fresh cold ingestion, byte-identical replay, one-revision incremental ingestion, inventory, one-Finding explanation, cold introduction inference with a four-revision work budget, and the identical introduction query against the resulting artifact. Incremental ingestion includes source discovery, parsing, reconciliation, validation, serialization, and process startup. It also requests the public `--profile-output` sidecar and records the product's dedicated `reconciliationElapsedNanoseconds`, prior Finding candidate count, evaluated and credible pairs, and continuity outcomes for every measured run. The validator binds that sidecar to the new Snapshot and verifies its counts against the persisted Finding continuity. Both introduction operations request the separate `swiftdebt-lifecycle-introduction-profile` sidecar. The cold sample must record `accepted`; the repeat must record `already-present` and leave the lifecycle artifact byte-identical. The validator binds the profile's Finding, work budgets, analyzed and reused revision counts, frontier count, and recording status to the persisted exact Introduction Conclusion. Raw samples retain those fields and the in-process duration through conclusion recording. CLI wall time remains the end-to-end measurement for every operation. The artifact record includes actual bytes, Snapshot and Finding counts, Lifecycle Event kinds, unresolved Detection counts, and Introduction Conclusion count. The script requires every original Finding ID to remain unique and observed after the edit, verifies the shifted Detection's location, parses the inventory and explanation JSON, rejects mutation by read-only commands, and requires an exact introduction conclusion.

---

## Run and enforce

Use a clean checkout at the candidate release commit. Resolve dependencies before measurement, then build the release executable once:

```sh
swift build -c release --jobs 2
python3 scripts/run_r3_lifecycle_benchmark.py \
  --swift-debt .build/release/swift-debt \
  --output /tmp/swiftdebt-r3-check.json \
  --runs 3 --warmups 1 \
  --budgets benchmarks/r3-lifecycle/budgets.json
```

`--budgets` requires all three tiers, one warmup, and at least three measured runs. It checks the fixture version, OS family, architecture, CPU model, and Swift version before comparing each tier's median wall time, maximum sampled peak RSS, reconciliation-stage median, and the largest cold, incremental, or introduction artifact with calibrated ceilings. The script writes raw evidence before returning a budget failure. The checked-in budget applies only to the recorded Apple M4 Max and Swift 6.4 environment; another machine or toolchain requires its own measured budget. Record the candidate binary and source commit with each passing result.

For a bounded public-CLI proof of the reconciliation sidecar before calibration, run:

```sh
python3 scripts/run_r3_lifecycle_benchmark.py \
  --swift-debt .build/release/swift-debt \
  --output /tmp/swiftdebt-r3-reconciliation-smoke.json \
  --tiers small --runs 1 --warmups 0
```

Inspect `tiers.small.incrementalReconciliation`, `tiers.small.operations.introduction.samples[].history`, and `tiers.small.operations.introductionRepeat.samples[].history` in that output. This one-sample smoke result is not a release budget or host calibration.

The evidence JSON records the Swift version, OS, architecture, CPU label, binary digest, source commit, fixture revisions, warmup and run counts, raw samples, medians, maximum RSS, examined Git revision count, remaining history frontier, and per-query analyzed and reused revision counts. The first run of each operation is discarded by default. All subsequent samples are retained. A matching clean repeat may reuse atomically complete zero-Detection historical Observation Snapshots after fresh Git and source-identity validation. Revisions with Detections remain cold until a persisted rule-implementation output identity exists. The cold operation remains the forced-cold oracle, and the validator requires both operations to produce the same persisted Introduction evidence. Raw counts must show which revision records were actually analyzed or reused; `already-present` alone is not treated as a cache hit.

---

## Apple M4 Max calibration

The checked-in evidence under `benchmarks/r3-lifecycle/evidence/` contains two independent raw runs and one passing budget-gate run. Each run used the same clean source commit and Release binary, with one warmup and three measured samples for every operation in each tier. The environment is macOS 27.2, arm64, Apple M4 Max, 36 GiB RAM, and Apple Swift 6.4. The JSON records the exact source commit and binary SHA-256; those fields, rather than the filename, establish provenance.

The table shows the larger median from the two raw runs and the budget ceiling, in seconds. The gate run is independent of those calibration runs.

| Operation | Small observed / limit | Medium observed / limit | Large observed / limit |
| --- | ---: | ---: | ---: |
| Cold ingestion | 0.139 / 0.30 | 0.193 / 0.40 | 1.361 / 2.75 |
| Identical replay | 0.151 / 0.35 | 0.195 / 0.40 | 1.809 / 3.65 |
| Incremental ingestion | 0.140 / 0.30 | 0.257 / 0.55 | 2.199 / 4.40 |
| Inventory | 0.012 / 0.10 | 0.030 / 0.10 | 0.338 / 0.70 |
| Explanation | 0.013 / 0.10 | 0.034 / 0.10 | 0.441 / 0.90 |
| Introduction inference | 0.218 / 0.45 | 0.399 / 0.80 | 2.856 / 5.75 |
| Identical introduction query | 0.211 / 0.45 | 0.428 / 0.90 | 3.894 / 7.80 |

Wall ceilings are twice the larger observed median, rounded up to 0.05 seconds with a 0.10-second floor. Peak RSS ceilings are 1.5 times the larger observed maximum, rounded up to 8 MiB with a 24 MiB floor. Artifact ceilings are 1.1 times the largest observed artifact, rounded up to 64 KiB. Reconciliation-stage ceilings are four times the larger observed median, rounded up to 5 ms with a 5 ms floor: 5 ms, 10 ms, and 80 ms for the three tiers. The complete numeric limits and all raw samples are in the JSON files.

---

## Interpretation and limits

The three tiers are deterministic synthetic source shapes. Once calibrated, they establish repeatable CLI budgets for these shapes; they do not establish throughput for arbitrary Swift repositories or compare SwiftDebt with another analyzer. The one-file edit leaves the other source contents unchanged, so its incremental result measures a narrow continuity case. Report its observed and ambiguous event counts alongside time rather than optimizing for a higher automatic match rate.

Artifact sizes in this benchmark are actual sizes at one and two Snapshots and 10, 100, or 1,000 Findings. Separate public CLI capacity probes have already measured product-generated artifacts at 1,000 Snapshots with zero Findings (10,123,749 bytes) and ten Snapshots with 10,000 Findings (112,073,433 bytes); see [R3 capacity evidence](r3-capacity-evidence.md). Those single runs do not measure the combined cardinalities or establish latency and memory distributions at either scale. The reconciliation sidecar here measures affected prior Finding candidates in a single-rule fixture; it does not establish candidate-set behavior on representative multi-rule repositories. Representative ambiguity rates, representative introduction reuse across mixed hits and invalidations, and a numeric introduction-cache budget also remain open. Passing these CLI budgets alone does not satisfy all R3 release-performance requirements in PRD sections 9.3, 12.2, and 12.4.

Budgets are machine-class specific. A changed Swift toolchain, SwiftSyntax version, artifact schema, fixture shape, or hardware class requires a new calibration with raw evidence and documented ceilings. A release cannot claim this gate merely because the script exits successfully on a different environment.
