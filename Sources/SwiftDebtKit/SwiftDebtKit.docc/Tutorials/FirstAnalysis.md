# Run Your First Analysis

Build SwiftDebt and produce a report from the example source in this package. The commands in this tutorial run from the SwiftDebt repository root with Swift 6.2 or later.

## Build the executable

```sh
swift build
```

The build creates `.build/debug/swift-debt`. Run it once against the included example:

```sh
.build/debug/swift-debt analyze Examples/Sources --format text
```

The report lists ten metric families and findings for `Example.swift`. This directory scan uses the virtual module name `Workspace`.

---

## Inspect structured output

Run the same analysis as JSON:

```sh
.build/debug/swift-debt analyze Examples/Sources --format json > /tmp/swift-debt-example.json
python3 -m json.tool /tmp/swift-debt-example.json > /dev/null
```

The JSON contains `complete: true`, `inputFileCount: 1`, and `analyzedFileCount: 1`. The report also contains source locations and the evidence behind debt items. If your command exits with status `2`, read stderr before using the JSON in automation.

---

## Analyze your own source

Replace `Examples/Sources` with a directory of Swift files:

```sh
.build/debug/swift-debt analyze /path/to/project --format json --output swift-debt.json
```

Use `--type-scope nominals` when structs, enums, and actors belong in the type metrics. The default type scope measures classes. Continue with <doc:RankedDebt> to turn observations into a ranked debt report.
