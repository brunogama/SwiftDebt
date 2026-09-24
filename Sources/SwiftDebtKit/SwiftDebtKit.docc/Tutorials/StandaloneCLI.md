# Analyze a Project with the Standalone CLI

Build a tagged SwiftDebt release, analyze a directory, and interpret the process result.

## Build the released executable

Clone the tagged source so the executable and its documentation describe the same release:

```sh
# swiftdebt-release-version:start
git clone --branch v0.2.1 --depth 1 https://github.com/brunogama/SwiftDebt.git
# swiftdebt-release-version:end
cd SwiftDebt
swift build -c release
.build/release/swift-debt --version
```

The first build resolves the pinned SwiftSyntax dependency. The executable does not require a server or the analyzed project's dependencies after it is built.

## Analyze source

Run the analyzer with a bounded parser job count and write a deterministic JSON report:

```sh
.build/release/swift-debt analyze /path/to/project \
  --type-scope nominals \
  --jobs 4 \
  --format json \
  --output swift-debt.json
```

Use `text`, `json`, `csv`, `html`, or `diagnostics` for metric reports. Add a `.swift-debt.json` file at the analysis root, or pass `--config`, when you need repeatable exclusions, thresholds, or scoring settings.

## Interpret completion

The executable exits with status `0` after a complete analysis, status `1` when an opted-in policy gate finds a violation, and status `2` for invalid input, invalid configuration, or incomplete analysis. A parse error is a warning by default; pass `--strict` to make it an incomplete-analysis error.
