# SwiftDebt rename performance evidence

Observed through `2026-09-22T15:00:53Z` on an Apple M4 Max with 36 GiB memory,
macOS 27.2 arm64, and Apple Swift 6.3.3. The candidate was the SwiftDebt
rename working tree based on `89119cfba01d85a06e084d879165271a26f33ba3`.

The equivalent historical reference is
`89119cfba01d85a06e084d879165271a26f33ba3`. It contains the same always-on
dependency graph, structural evidence, functional evidence, debt-item, and
report-schema capabilities as the candidate. The frozen inputs retain their
provenance from `b0ae66be2065084b29b8b5da0a86d5cd049feced`.
The `performance-reference-v1` tag keeps the rewritten reference available to CI.

## Method

Both analyzers were built in release mode. Each result uses one discarded
warmup and fifteen measured runs with fixed `--jobs 1`. The commands and exact
arguments match `.github/workflows/debtmap-performance.yml`; only absolute
temporary build and output paths differed.

The equivalent reference reused a clean 167.03-second dependency build and took
22.97 seconds to incrementally compile the final reference revision. The
candidate's initial clean isolated release build took 329.95 seconds; rebuilding
the final current candidate after the termination-signaling change took 7.76
seconds. Current benchmark harness wall times were 0.38 seconds for the baseline
reference, 0.70 seconds for the baseline candidate, 19.82 seconds for the
full-evidence reference, and 0.84 seconds for the full-evidence candidate.

## Results

| Workload | Reference wall median | Candidate wall median | Wall regression | Reference memory median | Candidate memory median | Memory regression | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Baseline | 0.011977542 s | 0.010483625 s | -12.472651% | 13,991,936 B | 13,975,552 B | -0.117096% | Pass |
| Full evidence | 1.238966583 s | 0.043957166 s | -96.452110% | 17,498,112 B | 17,399,808 B | -0.561798% | Pass |

The baseline budget is at most 10 percent wall-clock regression and 15 percent
peak-memory regression. The full-evidence budget is at most 20 percent
wall-clock regression and 15 percent peak-memory regression. No exception was
needed.

## Diagnostic history

`diagnostics/` preserves three failed baseline comparisons against the original
input-provenance commit. That executable predates the candidate's always-on
graph and debt-evidence capabilities, so the matching command text did not make
the measured work equivalent. The first five-sample set failed memory at
15.102041 percent, the independent five-sample set failed wall clock at
13.927593 percent, and the fifteen-sample set failed wall clock at 20.109489
percent. These results motivated both the equivalent-reference correction and
the increase from five to fifteen measured samples. The initial passing
full-evidence comparison against `61adcc22a6d63ee7d6ec5d2e3b81e843d34a2a71`
and the intermediate comparisons against `04231b1b78e9e6b3fc18df35473c183f5ca38f47`
are also retained there. The final full-evidence reports prove that each analyzer
produced nine measured coverage facts and thirty-six available Git-history
facts, with none of those facts unavailable.
