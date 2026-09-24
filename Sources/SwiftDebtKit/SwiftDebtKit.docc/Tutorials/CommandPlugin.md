# Run SwiftDebt as a Command Plugin

Analyze the exact Swift sources and module names known to a consuming Swift package.

## Add the package dependency

Add the released SwiftDebt package as shown in <doc:LibraryAPI>. A command plugin does not need a `.plugin(...)` entry on a target.

## Analyze selected targets

Run the command from the consuming package root:

```sh
swift package swift-debt \
  --target AppCore \
  --target Domain \
  --type-scope nominals \
  --format diagnostics \
  --fail-on-violation
```

Without `--target`, SwiftDebt analyzes regular Swift targets in the root package and excludes test targets. Pass `--include-tests` to include tests. Dependencies of the root package are not selected automatically.

## Write a report

The plugin requests no package-write or network permissions. Grant only the intended output directory when writing a file:

```sh
mkdir -p reports
swift package --allow-writing-to-directory ./reports swift-debt \
  --target AppCore \
  --format html \
  --output ./reports/swift-debt.html
```

SwiftPM may wrap a nonzero executable result in its own plugin failure. Treat the command as failed when SwiftDebt reports invalid input or an enabled policy violation.
