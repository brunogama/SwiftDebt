# R2 release performance evidence

`calibration.v1.json` is the valid compact-retention calibration for the
current manifest. Its SHA-256 is
`a6c778c32b45501b4bb0b24142223811d89d94487ded47d1b45656492b7de09b`.
The independent artifact validator recomputes every aggregate, budget, output
identity, cache contract, load check, induced proof, and exhaustion verdict
from the checked-in raw samples.

The first calibration attempt remains invalid. Its raw artifact is retained
without modification as `moderate-load-invalid.v1.json` with SHA-256
`987449981a9852f2a480606291d277e24e49dee7e847fb46732ab6b824206cd1`.
No threshold was changed in response to that result.

The branch commit named `test(performance): preserve initial R2 calibration`
contains the exact old manifest before the harness was updated for the merged
repository syntax cache. Its SHA-256 is
`7622d7ae5ea95a7aa9af41f4b3d517b0eba1c8c624cc74d4b2b770541f30ef24`,
which matches the identity recorded by the invalid artifact.

---

## Valid compact-retention calibration

The run completed on 2026-09-26 from harness commit
`fa495f461289040d32a759ba28a220b2e8d0aa1f`. Its candidate package inputs
matched the manifest's pinned source commit
`4b9db979e7dc0f870d00f6cae9dcab37528bffb4`. Later changes to the benchmark
branch or `main` do not change that measured candidate identity.

| Role | Commit | Engine version | Binary SHA-256 |
|---|---|---:|---|
| R1 reference | `54516ae9385dabd09969d9f02a8f51b6cea2b0e1` | 0.8.0 | `d7295ae474ef280bcc243cac780cdf2cc097f848f06cb2ac8a5ae4a0ce7a05b4` |
| R2 candidate | `4b9db979e7dc0f870d00f6cae9dcab37528bffb4` | 0.10.0 | `558c1b87af916a39aed5ef59e0945de5c20cac2511d808e22fbc268e69834e00` |

The 30-second preflight passed with maximum one-minute load 13.61, minimum CPU
idle 58.53 percent, and maximum disk throughput 0 MB/s. Every scenario
completed five warmups, 30 measured runs, and five induced-regression runs.
The compact work directory ended at 23 MB with 787 `*.sample.json` records,
zero retained `analysis.json` files, and 22 GiB free on the Data volume. Those
work-directory records are diagnostic; the 5.3 MB atomic artifact contains the
raw measurements used by the validator.

| Scenario | Reference or calibration p95 ms | Candidate p95 ms | Candidate p95 RSS MiB | Max 1m load | Verdict |
|---|---:|---:|---:|---:|---|
| `similarity-disabled-scale-16` | 24.51 | 27.77 | 20.75 | 10.35 | Pass |
| `similarity-disabled-scale-128` | 111.51 | 115.39 | 50.70 | 10.62 | Pass |
| `similarity-disabled-scale-1024` | 1,854.63 | 1,881.54 | 252.27 | 9.61 | Pass |
| `repository-evidence-cache-disabled-scale-16` | 44.18 | 44.18 | 21.69 | 6.36 | Pass |
| `repository-evidence-cold-cache-scale-16` | 47.52 | 47.52 | 21.84 | 6.36 | Pass |
| `repository-evidence-warm-cache-scale-16` | 50.43 | 50.43 | 22.25 | 6.25 | Pass |
| `repository-evidence-one-file-edit-scale-16` | 50.37 | 50.37 | 21.91 | 6.31 | Pass |
| `repository-evidence-cache-disabled-scale-128` | 158.75 | 158.75 | 54.59 | 6.31 | Pass |
| `repository-evidence-cold-cache-scale-128` | 170.79 | 170.79 | 53.81 | 5.80 | Pass |
| `repository-evidence-warm-cache-scale-128` | 186.33 | 186.33 | 54.58 | 5.43 | Pass |
| `repository-evidence-one-file-edit-scale-128` | 187.65 | 187.65 | 54.75 | 5.22 | Pass |
| `repository-evidence-cache-disabled-scale-1024` | 1,885.21 | 1,885.21 | 268.45 | 5.72 | Pass |
| `repository-evidence-cold-cache-scale-1024` | 2,090.20 | 2,090.20 | 271.52 | 7.27 | Pass |
| `repository-evidence-warm-cache-scale-1024` | 2,419.53 | 2,419.53 | 293.16 | 6.25 | Pass |
| `repository-evidence-one-file-edit-scale-1024` | 2,290.12 | 2,290.12 | 293.86 | 7.02 | Pass |

The three paired rows are R1-to-R2 comparisons. The twelve repository rows use
the same R2 samples as calibration baseline and candidate because R1 has no
repository evidence sidecar. Their pass proves deterministic measurement,
cache activity, fixed load bounds, and gate sensitivity. It does not prove a
cache speedup or establish an R1 regression ceiling. Every numeric limit remains
`proposed-for-review`.

The independent exhaustion proof also passed. The real CLI exited 2, emitted
`comparison-budget-exceeded`, and remained within the fixed load ceiling.
Overall artifact state is `measured-pass`; release qualification is still
`incomplete` because the index, embedding, ANN, and independently reviewed
accuracy gates remain open.

CI executes the artifact validator below. This is an integrity and harness
logic gate, not a live timing run on a hosted machine:

```sh
python3 scripts/validate_r2_release_calibration.py \
  --manifest benchmarks/r2-release/manifest.v1.json \
  --artifact benchmarks/r2-release/evidence/2026-09-25-m4-max/calibration.v1.json
```

---

## Historical frozen inputs

These inputs belong only to `moderate-load-invalid.v1.json`.

| Role | Commit | Engine version | Binary SHA-256 |
|---|---|---:|---|
| R1 reference | `54516ae9385dabd09969d9f02a8f51b6cea2b0e1` | 0.8.0 | `d7295ae474ef280bcc243cac780cdf2cc097f848f06cb2ac8a5ae4a0ce7a05b4` |
| Historical R2 candidate | `d489dd922f422890e58ea22a9b5035af69f05d5b` | 0.9.0 | `90f752136b98bd678aeb437580882c7e6efb5b68a332ed89cb3e892dabe5c844` |

Both historical binaries were built independently with Xcode 26.6, Swift
6.3.3, macOS SDK 26.5, and `swift build -c release --jobs 2`.

---

## Invalid moderate-load attempt

The run started at 15:01 BRT on 2026-09-25 after a 30-second manual preflight.
The one-minute load decreased from 11.05 to 9.28, CPU idle was 72 to 73 percent,
and sampled disk throughput was 0 MB/s. A separate SQVector gate continued with
a two-job bound, so this is moderate-load evidence and is not described as a
quiet-host run.

The frozen per-command ceiling was 21, equal to 1.5 times the 14 physical CPU
count. The 1,024-file similarity scenario observed 23.87 and failed closed. Two
similarity scenarios also failed the required induced-regression sensitivity
proof. Those results invalidate the complete run even though other scenarios
passed.

The historical harness also derived paired short-stage variability from
candidate-minus-reference deltas. That let candidate variance widen its own
floor. The current harness uses reference-only samples, and no result from this
artifact supplies a current release budget.

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
to 7.14, CPU idle stayed at or above 40 percent, and disk throughput remained 0
MB/s. It completed all paired scenarios and the 16 and 128-file repository
scenarios.

At 16:00 BRT the host one-minute load reached 56.83, above the unchanged limit
of 21. The exact runner process was interrupted with exit 130 during the
1,024-file repository scenario. No benchmark child remained after interruption.

The runner writes its artifact atomically only after every scenario and the
exhaustion proof complete, so this interrupted attempt has no partial raw JSON
artifact. No timing result from that attempt is used for calibration.

---

## Frozen current inputs and rerun contract

Any rerun uses the current `manifest.v1.json`, whose candidate source is commit
`4b9db979e7dc0f870d00f6cae9dcab37528bffb4` and whose scenarios
explicitly separate cache disabled, cold, warm, and one-file-edit states. The
historical 0.9.0 candidate binary and old manifest cannot be reused for that
run. The frozen R1 reference remains the same.

The runner now performs and records its own 30-second preflight. Every five-
second sample must keep one-minute load at or below 14, CPU idle at or above 40
percent, and disk throughput at or below 1 MB/s. Every measured command must
remain at or below a one-minute load of 21.

A replacement run must exit 0. Every scenario must pass deterministic output,
exact cache activity, wall, RSS, host-load, and induced-regression checks. The
exhaustion proof must also pass. Any failed run remains invalid evidence and
does not replace the current `calibration.v1.json`.

---

## Command

Create and build the candidate from the manifest pin before invoking the
benchmark harness from this checkout:

```sh
git worktree add --detach /tmp/swiftdebt-r2-candidate \
  4b9db979e7dc0f870d00f6cae9dcab37528bffb4
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --package-path /tmp/swiftdebt-r2-candidate -c release --jobs 2
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 scripts/run_r2_release_benchmarks.py \
  --manifest benchmarks/r2-release/manifest.v1.json \
  --reference-root /Users/bruno/Developer/SwiftSCMA-r1-benchmark \
  --reference-binary /Users/bruno/Developer/SwiftSCMA-r1-benchmark/.build/release/swift-debt \
  --candidate-root /tmp/swiftdebt-r2-candidate \
  --candidate-binary /tmp/swiftdebt-r2-candidate/.build/release/swift-debt \
  --work-directory /tmp/swiftdebt-r2-calibration-$(git rev-parse --short HEAD) \
  --output benchmarks/r2-release/evidence/2026-09-25-m4-max/calibration.v1.json
```

---

## Open qualification gates

Release qualification remains incomplete after a valid deterministic-cache
calibration. Embedding and candidate-index operation telemetry, SQVector
exact-index evidence, ANN evidence, and the independently reviewed accuracy
gate remain open. PR #62 labels are provisional until two named qualified Swift
reviewers adjudicate them.
