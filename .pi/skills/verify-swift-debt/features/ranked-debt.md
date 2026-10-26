# Ranked debt analysis

## Sub-features

- Compose structural, coverage, Git-history, functional, and Swift-specific evidence.
- Aggregate and filter callable, type, file, or module debt.
- Render native debt JSON, Markdown, text, compact, DOT, and dashboard reports.
- Validate score thresholds for CI with deterministic exit statuses.

## How to get to it (user POV)

Use the `debt` namespace and provide an explicit reference time for Git history:

```sh
.build/debug/swift-debt debt analyze Examples/Sources \
  --format debt-json \
  --debt-reference-time 2026-09-12T00:00:00Z \
  --top 5 --output /tmp/swift-debt-ranked.json
```

For a gate, run `debt validate` with `--max-score` and inspect exit status 1
when the policy is exceeded.

## Driving it with the SwiftDebt CLI helper

Run:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --feature debt
```

The helper drives the real ranked workflow against an isolated fixture, freezes
the reference time, and verifies the native schema, ranked-item count, and
unavailable Git evidence. The generated debt report and command transcript
remain under the printed evidence directory.

## Gotchas

- Missing Git history is unavailable evidence, not a fabricated zero.
- `debt analyze` and plain `analyze` are different workflows and report formats.
- `--top`, `--min-score`, `--category`, and `--level` are deterministic filters.
- The native schema is not a byte-for-byte Rust Debtmap report schema.
