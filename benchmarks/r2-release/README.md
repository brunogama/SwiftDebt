# R2 release performance benchmark

This directory defines the reproducible performance slice for deterministic R2
repository analysis. It exercises the real `swift-debt` CLI with similarity
disabled and with explicit repository syntax-cache states. It does not qualify
the complete R2 release while embedding telemetry, SQVector, ANN, accuracy, and
independent reviewer gates remain open.

---

## Files

| Path | Purpose |
|---|---|
| `manifest.v1.json` | Frozen source commits, engine versions, cache compatibility, generated corpus snapshots, analysis-unit counts, environment, command shapes, scenarios, and budget policy. |
| `../../scripts/run_r2_release_benchmarks.py` | Release calibration entry point and fail-closed manifest validation. |
| `../../scripts/r2_benchmark_support.py` | Statistics, host preflight, deterministic corpus generation, and the standard edit. |
| `../../scripts/r2_benchmark_cli.py` | Real CLI process measurement and output validation. |
| `../../scripts/r2_benchmark_cache.py` | Explicit cache-state preparation and exact activity validation. |
| `../../scripts/r2_benchmark_scenarios.py` | Scenario sampling, fixed limits, and induced-regression proof. |
| `evidence/2026-09-25-m4-max/moderate-load-invalid.v1.json` | Preserved raw artifact from the first invalid calibration. |
| `evidence/2026-09-25-m4-max/README.md` | Historical result, interruption evidence, and current rerun requirements. |

`manifest.v1.json` is authored source configuration. Calibration JSON is
generated atomically by the runner and must not be edited by hand. The valid
`calibration.v1.json` path remains absent until a complete run passes.

The branch commit named `test(performance): preserve initial R2 calibration`
retains the exact historical manifest and invalid artifact before the cache
harness update. The invalid artifact also records that manifest's SHA-256.

---

## Measurement design

The runner generates Swift corpora at 16, 128, and 1,024 source files. Each
source contributes three Data Clumps analysis units and two Repeated Switches
units. The manifest freezes the generated file count, byte count, tree digest,
analysis-unit counts, expected Detection counts, and the edited tree digest.

Comparable R1 and R2 similarity-disabled commands run as paired samples with
alternating order. R2 repository-evidence scenarios run independently because
R1 has no repository sidecar. Every scenario uses five unmeasured warmups and
30 measured fresh-process runs.

Raw report hashes and engine versions prove byte stability within each build.
The cross-version comparison canonicalizes JSON and removes only
`engineVersion`; the artifact records both engine versions separately. Any
other report difference invalidates the paired scenario.

---

## Repository cache states

Each repository sample owns a fresh state directory and passes an explicit CLI
cache policy. The benchmark never uses the CLI's default cache location.

| State | Preparation outside timed command | Measured expectation |
|---|---|---|
| `disabled` | None | `--no-repository-cache`, every source recomputed, no retained cache file. |
| `cold` | Explicit absent cache path | Every source recomputed, `cache-missing`, one atomic cache write. |
| `warm` | Seed the explicit cache from the frozen corpus | Every source reused, zero recomputed, no invalidation, no cache rewrite. |
| `one-file-edit` | Seed from the frozen corpus, then append the manifest's fixed comment to `Scale0000.swift` | All unchanged sources reused, exactly one source recomputed, `source-content-changed`, one cache write. |

Every cache report must match the frozen cache, fact, projection, provider, rule,
and unit-budget compatibility identity. It must also report zero network
requests. Its source snapshot digest must equal the repository-evidence content
digest from the same command. For enabled cache states, its absolute storage
path, retained data classes, byte count, and content digest must match the
controlled cache file. Determinism compares the activity JSON after removing
only the machine-local cache path and compares the retained cache bytes directly.

The timed wall and RSS sample contains only the measured CLI process. Warm and
edit setup uses one validated scenario seed whose exact bytes are copied into a
fresh state directory before each sample. Seed creation and copying are outside
the timed command. The seed activity and cache identity are recorded separately
in each raw sample.

---

## Host validity

Before any benchmark command, the runner observes the host for at least 30
seconds at five-second intervals. Every sample must satisfy all frozen limits:

| Signal | Preflight limit |
|---|---:|
| One-minute load | At most 14, equal to the physical core count |
| CPU idle | At least 40 percent |
| Disk throughput | At most 1 MB/s |

The disk allowance is a fixed measurement-resolution floor. It was selected
before the next calibration and is not adjusted from benchmark outcomes.

Each measured and induced command additionally records load immediately before
and after execution. Any observed one-minute load above 21, or 1.5 times the
physical core count, aborts the run. The output artifact includes the complete
preflight and per-command load evidence.

---

## Budgets and regression proof

The wall-time gate keeps the 10 percent relative limit. For a stage whose R1
p95 is under one second, the scenario also gets an absolute floor equal to the
greater of 10 milliseconds and three median absolute deviations. A short stage
fails only when both its relative limit and absolute floor are exceeded.

The peak-RSS gate keeps the 15 percent relative limit and the merged fixed 2 MiB
process-memory allowance. Memory fails only when both limits are exceeded. The
artifact records both comparisons and the effective maximum tolerated absolute
delta.

For each scenario the runner measures a deliberate workload increase made of
two complete sequential measured CLI processes. Calibration is invalid unless
that workload fails the wall-time gate. No budget depends on changed line,
source, or analysis-unit count.

---

## Reproduce

Build exact reference and candidate source trees with the manifest's toolchain.
Both binaries use the same bounded release-build command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --jobs 2
```

Run calibration from the candidate checkout only after the shared SwiftPM and
CLI lane is free and the host is quiet:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 scripts/run_r2_release_benchmarks.py \
  --manifest benchmarks/r2-release/manifest.v1.json \
  --reference-root /Users/bruno/Developer/SwiftSCMA-r1-benchmark \
  --reference-binary /Users/bruno/Developer/SwiftSCMA-r1-benchmark/.build/release/swift-debt \
  --candidate-root "$PWD" \
  --candidate-binary .build/release/swift-debt \
  --output benchmarks/r2-release/evidence/2026-09-25-m4-max/calibration.v1.json
```

The runner refuses a toolchain, OS, hardware, source commit, generated corpus,
edited corpus, analysis-unit, command-template, cache-state, or compatibility
mismatch. It exits 2 when a measured scenario fails, the induced workload
passes unexpectedly, or the exhaustion proof is absent.

---

## Qualification state

| Requirement | State | Evidence or blocker |
|---|---|---|
| Similarity-disabled cold wall and RSS | Harness ready, calibration pending | Paired R1/R2 samples at all three scale points. |
| Raw samples, median, p95, and per-scenario floor | Harness ready, calibration pending | Generated only after a complete valid run. |
| Deterministic report and repository evidence | Harness ready, calibration pending | Raw report and sidecar SHA-256 equality across measured runs. |
| Explicit cache disabled and cold states | Harness ready, calibration pending | Exact activity, retained-state, and zero-network assertions. |
| Unchanged warm syntax facts | Harness ready, calibration pending | All sources reused and cache bytes unchanged. |
| Standard one-file syntax-fact edit | Harness ready, calibration pending | One changed source and exact invalidation activity. |
| Reprojection and re-embedding counts | Blocked | The cache stores syntax facts; embedding and projection operation telemetry is unavailable. |
| Comparison-budget exhaustion | Harness ready, calibration pending | Real CLI exit 2 and `comparison-budget-exceeded` sidecar issue. |
| SQVector exact-index latency, RSS, size, candidates | Blocked | `SQVectorStatic` is pin-consumable at `aafd9ae601826112978127c7cb611c94ab8a2e06`, but the SwiftDebt adapter is unmerged and no frozen index scenario or raw release evidence exists. |
| ANN recall and latency | Blocked | No qualified ANN implementation is available. |
| Accuracy and independent labels | Outside this artifact | PR #62 remains provisional pending two named qualified reviewers. |

Index size and candidate count are not applicable to similarity-disabled
scenarios. They remain unavailable, rather than zero-filled, for blocked index
scenarios.
