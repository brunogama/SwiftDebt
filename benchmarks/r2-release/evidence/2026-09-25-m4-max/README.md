# R2 release performance evidence

The first calibration attempt is invalid. Its raw artifact is retained as
`moderate-load-invalid.v1.json` with SHA-256
`987449981a9852f2a480606291d277e24e49dee7e847fb46732ab6b824206cd1`.
No threshold was changed after observing the result. A valid calibration is
pending a host window that passes the same preflight and per-command load
limits.

---

## Frozen inputs

| Role | Commit | Engine version | Binary SHA-256 |
|---|---|---:|---|
| R1 reference | `54516ae9385dabd09969d9f02a8f51b6cea2b0e1` | 0.8.0 | `d7295ae474ef280bcc243cac780cdf2cc097f848f06cb2ac8a5ae4a0ce7a05b4` |
| R2 candidate | `d489dd922f422890e58ea22a9b5035af69f05d5b` | 0.9.0 | `90f752136b98bd678aeb437580882c7e6efb5b68a332ed89cb3e892dabe5c844` |

Both binaries were built independently with the manifest's Xcode 26.6,
Swift 6.3.3, and macOS SDK 26.5 release-build protocol. The runner verified the
source roots, engine versions, binary paths, toolchain, hardware, corpus
snapshots, and output contracts before recording evidence.

---

## Invalid moderate-load attempt

The run started at 15:01 BRT on 2026-09-25 after a 30-second preflight. The
one-minute load decreased from 11.05 to 9.28, CPU idle was 72 to 73 percent,
and sampled disk throughput was 0 MB/s. Other SwiftDebt agents held their build
and CLI work. A separate SQVector gate continued with a two-job bound, so this
run is moderate-load evidence and is not described as a quiet-host run.

The frozen per-command ceiling was 21, equal to 1.5 times the 14 physical CPU
count. The 1,024-file similarity scenario observed 23.87 and failed closed.
Two similarity scenarios also failed the required induced-regression
sensitivity proof. Those results invalidate the complete run even though the
other scenarios passed.

| Scenario | Baseline p95 ms | Candidate p95 ms | Applied floor ms | Max 1m load | Induced proof | Result |
|---|---:|---:|---:|---:|---|---|
| Similarity disabled, 16 files | 87.49 | 104.58 | 102.44 | 10.36 | Fail | Invalid |
| Similarity disabled, 128 files | 320.37 | 321.52 | 76.75 | 12.16 | Pass | Pass |
| Similarity disabled, 1,024 files | 12,389.98 | 12,125.13 | 1,039.12 | 23.87 | Fail | Invalid |
| Repository evidence, 16 files | 72.81 | 72.81 | 25.74 | 9.43 | Pass | Pass |
| Repository evidence, 128 files | 162.18 | 162.18 | 16.05 | 9.43 | Pass | Pass |
| Repository evidence, 1,024 files | 5,094.61 | 5,094.61 | 2,394.27 | 11.67 | Pass | Pass |

The 16-file paired deltas ranged from -56.60 to 98.24 ms. Their median absolute
deviation was 34.15 ms, producing a 102.44 ms floor. The doubled workload rose
65.27 ms above the baseline p95, so it did not cross that noise floor.

The 1,024-file baseline median was 3,542.36 ms while its p95 reached 12,389.98
ms. Individual paired deltas included 4,857.22 ms and -7,573.77 ms. The induced
workload p95 was 6,256.27 ms, below the load-inflated baseline p95. This run
cannot calibrate an effective long-stage regression gate.

The independent exhaustion proof passed: the real CLI exited 2 and emitted
`comparison-budget-exceeded` at a maximum one-minute load of 8.26.

---

## Interrupted rerun

A second attempt started at 15:54 BRT after one-minute load decreased from 8.90
to 7.14, CPU idle stayed at or above the frozen 40 percent minimum, and sampled
disk throughput remained 0 MB/s. It completed all paired scenarios and the 16
and 128-file repository scenarios.

At 16:00 BRT the host one-minute load reached 56.83, above the unchanged limit
of 21. The exact runner process was interrupted with exit 130 during the
1,024-file repository scenario. At that point the largest observed competing
processes were the macOS `deleted` service, a Chrome GPU helper, and
WindowServer. No benchmark child remained after interruption.

The runner writes its artifact atomically after all scenarios complete, so this
interrupted attempt has no partial raw JSON artifact. This is a runner evidence
limitation, and no timing result from the attempt is used for calibration. The
complete first invalid run remains preserved above.

---

## Rerun criteria

The rerun shall use the same manifest, source commits, binaries, and thresholds.
SwiftDebt build and CLI work in the other local worktrees must be paused. A
30-second preflight must keep one-minute load at or below 14, current CPU idle
at or above 40 percent, and sampled disk throughput effectively idle.

During the run, every recorded one-minute load must stay at or below 21. The
runner must exit 0, every scenario must pass its deterministic output, wall,
RSS, host-load, and induced-regression checks, and the exhaustion proof must
pass. Any failed attempt remains raw invalid evidence and does not replace the
final `calibration.v1.json` artifact.

---

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 scripts/run_r2_release_benchmarks.py \
  --manifest benchmarks/r2-release/manifest.v1.json \
  --reference-root /Users/bruno/Developer/SwiftSCMA-r1-benchmark \
  --reference-binary /Users/bruno/Developer/SwiftSCMA-r1-benchmark/.build/release/swift-debt \
  --candidate-root /Users/bruno/Developer/SwiftSCMA-r2-benchmarks \
  --candidate-binary /Users/bruno/Developer/SwiftSCMA-r2-benchmarks/.build/release/swift-debt \
  --output benchmarks/r2-release/evidence/2026-09-25-m4-max/calibration.v1.json
```

The invalid output was renamed without modification so the expected final path
remains reserved for a valid run.

---

## Open qualification gates

Release qualification remains incomplete even after a valid rerun. Persistent
warm-cache, one-file incremental, global provider and index-operation telemetry,
published SQVector exact-index, and ANN scenarios are unavailable in this source
slice and remain explicitly blocked in the manifest.
