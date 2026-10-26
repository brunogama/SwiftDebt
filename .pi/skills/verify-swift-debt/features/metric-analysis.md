# Metric analysis

## Sub-features

- Analyze Swift source with the ten SCMA metric summaries.
- Emit JSON, text, CSV, HTML, or diagnostics output.
- Enforce thresholds with an explicit exit status.
- Reject malformed arguments and protect source files from report overwrite.

## How to get to it (user POV)

Build the package, then run `swift-debt analyze` against a Swift source
directory. A user normally selects a format and optionally an output path:

```sh
.build/debug/swift-debt analyze Examples/Sources \
  --format json --jobs 1 --output /tmp/swift-debt-report.json
```

## Driving it with the SwiftDebt CLI helper

Run:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --feature metrics
```

The helper creates a temporary source fixture, performs the command twice with
different bounded job counts, and validates that both reports are complete,
contain ten metrics, and are byte-identical. Review the resulting
`metrics.json`, `metrics-repeat.json`, command records, and validation log in
the printed evidence directory.

## Gotchas

- `--strict` turns a parse warning into an incomplete analysis and exit status 2.
- Output paths are protected; never use a Swift input file as `--output`.
- A report's `overallScore` can be `null` when scoring is disabled or undefined.
- The analyzer does not build or resolve the analyzed project's dependencies.
