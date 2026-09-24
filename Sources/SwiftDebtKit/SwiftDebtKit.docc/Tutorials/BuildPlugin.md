# Attach the SwiftDebt Build Plugin

Run target-local SwiftDebt diagnostics when SwiftPM builds a target.

## Attach the plugin

After adding the released SwiftDebt dependency, attach `SwiftDebtBuildPlugin` to every target you want checked:

```swift
.target(
    name: "AppCore",
    plugins: [
        .plugin(name: "SwiftDebtBuildPlugin", package: "SwiftDebt")
    ]
)
```

## Create the configuration input

Create `.swift-debt.json` in the consuming package root before the first build. The file is a declared build input, and an empty object is valid.

```json
{
  "typeScope": "nominals",
  "thresholds": { "CCF": 15 },
  "failOnViolation": true
}
```

Run a normal build:

```sh
swift build
```

The plugin emits source-located diagnostics and a comment-only completion file in its work directory. Source or configuration changes invalidate analysis; a warmed no-op build can reuse the prior result.

Build-plugin analysis is limited to one target at a time. Use <doc:CommandPlugin> when coupling or duplicate detection must span multiple targets.
