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
| `../../scripts/validate_r2_release_calibration.py` | Recompute and validate a checked-in artifact without claiming live host reproduction. |
| `evidence/2026-09-25-m4-max/calibration.v1.json` | Valid compact-retention calibration with raw samples, aggregates, load observations, limits, and induced-regression proofs. |
| `evidence/2026-09-25-m4-max/moderate-load-invalid.v1.json` | Preserved raw artifact from the first invalid calibration. |
| `evidence/2026-09-25-m4-max/README.md` | Valid result, historical invalid attempts, interpretation, and rerun requirements. |

`manifest.v1.json` is authored source configuration. Calibration JSON is
generated atomically by the runner and must not be edited by hand. The current
artifact has SHA-256
`a6c778c32b45501b4bb0b24142223811d89d94487ded47d1b45656492b7de09b`.

The branch commit named `test(performance): preserve initial R2 calibration`
retains the exact historical manifest and invalid artifact before the cache
harness update. The invalid artifact also records that manifest's SHA-256.

---

## Measured artifact

The compact-retention calibration ran from harness commit
`fa495f461289040d32a759ba28a220b2e8d0aa1f`. The candidate package inputs
`Package.swift`, `Package.resolved`, and `Sources` matched the manifest's pinned
candidate commit `4b9db979e7dc0f870d00f6cae9dcab37528bffb4`; the runner rejected any
tracked or untracked source difference. The frozen R1 reference remains
`54516ae9385dabd09969d9f02a8f51b6cea2b0e1`.

The artifact is a `measured-pass`: all 15 scenarios completed five warmups, 30
measurements, and five induced-regression runs; output, cache activity, wall,
RSS, and host-load checks passed; and the real exhaustion command exited 2 with
`comparison-budget-exceeded`. Release qualification remains `incomplete`.
Repository-only ceilings remain `proposed-for-review`, and the blocked index,
embedding, ANN, and independent accuracy gates are not inferred from these
samples.

CI validates the checked-in raw samples, aggregates, limits, and verdicts by
recomputation. It does not rerun host timings because the hosted runner does not
reproduce the frozen M4 Max environment. Live calibration on the frozen host
remains a local release requirement.

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
Each scenario records completed warmup, measured, and induced-run counts in the
generated artifact so CI can validate the checked-in 5+30 protocol without
claiming to reproduce the host-specific timings.

After each command passes output and cache validation, the runner atomically
records its complete measurement metadata as a compact `*.sample.json` file and
removes the bulky derived analysis files. A command that fails before validation
keeps its derived directory for diagnosis. The final artifact contains the same
measured raw samples; compact work-directory records are diagnostic checkpoints,
not a substitute for the atomic artifact.

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
greater of 10 milliseconds and three median absolute deviations from R1-only
wall samples. Candidate variance cannot widen its own paired allowance. A short
stage fails only when both its relative limit and absolute floor are exceeded.

The peak-RSS gate keeps the 15 percent relative limit and the merged fixed 2 MiB
process-memory allowance. Memory fails only when both limits are exceeded. The
artifact records both comparisons and the effective maximum tolerated absolute
delta.

For each scenario the runner measures a deliberate workload increase made of
two complete sequential measured CLI processes. Calibration is invalid unless
that workload fails the wall-time gate. No budget depends on changed line,
source, or analysis-unit count.

Repository cache states have no R1 command with equivalent evidence. Their
current candidate samples calibrate proposed per-scale ceilings and prove
determinism and sensitivity; they do not constitute an R1-to-R2 regression
comparison. Those ceilings remain pending review even after a measured run.

---

## Reproduce

Build exact reference and candidate source trees with the manifest's toolchain.
After this benchmark-only branch is rebased, use a detached candidate checkout
at the manifest pin rather than treating the newer integration tree as the
measured candidate:

```sh
git worktree add --detach /tmp/swiftdebt-r2-candidate \
  4b9db979e7dc0f870d00f6cae9dcab37528bffb4
```

Both binaries use the same bounded release-build command. Run it in the
reference checkout and for the detached candidate with `--package-path`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --package-path /tmp/swiftdebt-r2-candidate -c release --jobs 2
```

Run the harness from the benchmark checkout only after the shared SwiftPM and
CLI lane is free and the host is quiet:

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

The runner refuses a toolchain, OS, hardware, source commit, generated corpus,
edited corpus, analysis-unit, command-template, cache-state, or compatibility
mismatch. It exits 2 when a measured scenario fails, the induced workload
passes unexpectedly, or the exhaustion proof is absent.

---

## Qualification state

| Requirement | State | Evidence or blocker |
|---|---|---|
| Similarity-disabled cold wall and RSS | Measured pass; limit approval pending | Paired R1/R2 samples pass at all three scale points under proposed limits. |
| Raw samples, median, p95, and per-scenario floor | Measured pass | The generated artifact records all raw samples and recomputable aggregates. |
| Deterministic report and repository evidence | Measured pass | Raw report and sidecar SHA-256 equality across all measured runs. |
| Explicit cache disabled and cold states | Measured pass; ceilings proposed | Exact activity, retained state, and zero-network assertions at three scales. |
| Unchanged warm syntax facts | Measured pass; ceilings proposed | All sources reused and cache bytes unchanged at three scales. |
| Standard one-file syntax-fact edit | Measured pass; ceilings proposed | One changed source and exact invalidation activity at three scales. |
| Reprojection and re-embedding counts | Blocked | The cache stores syntax facts; embedding and projection operation telemetry is unavailable. |
| Comparison-budget exhaustion | Measured pass | Real CLI exit 2 and `comparison-budget-exceeded` sidecar issue. |
| SQVector exact-index latency, RSS, size, candidates | Blocked | `SQVectorStatic` is pin-consumable at `aafd9ae601826112978127c7cb611c94ab8a2e06`, but the SwiftDebt adapter is unmerged and no frozen index scenario or raw release evidence exists. |
| ANN recall and latency | Blocked | No qualified ANN implementation is available. |
| Accuracy and independent labels | Outside this artifact | PR #62 remains provisional pending two named qualified reviewers. |

Index size and candidate count are not applicable to similarity-disabled
scenarios. They remain unavailable, rather than zero-filled, for blocked index
scenarios.
