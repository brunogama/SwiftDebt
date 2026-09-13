# SwiftSCMA baseline benchmark methodology

This record freezes the inputs and method for the pre-Debtmap runtime and peak-memory baseline. It does not claim any measured performance result.

## Frozen inputs

The executable benchmark fixture is listed in `Benchmarks/SwiftSCMABaseline/manifest.json`. The manifest records each input path, module name, UTF-8 byte count, and line count so the test suite can detect accidental fixture drift.

## Procedure

1. Use the checked-out repository without uncommitted changes.
2. Build the release executable with `swift build -c release --product scma`.
3. Run one warm-up analysis that writes `.scma/baseline-report.json`.
4. Run five measured analyses with the same command and report the median wall-clock seconds and median peak resident set size in bytes.
5. On macOS, capture wall time and maximum resident set size with `/usr/bin/time -l`.
6. On Linux, capture wall time and maximum resident set size with `/usr/bin/time -v`.

The analysis command is:

```sh
.build/release/scma analyze Benchmarks/SwiftSCMABaseline/Sources \
  --format json \
  --type-scope nominals \
  --jobs 1 \
  --output .scma/baseline-report.json
```

Use `--jobs 1` for the baseline so repeated runs do not depend on host core count or task scheduling.
