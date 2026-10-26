# SwiftPM plugins

## Sub-features

- Build-time analysis through `SwiftDebtBuildPlugin`.
- On-demand package analysis through `SwiftDebtCommandPlugin`.
- Target selection and incremental invalidation.
- Required `.swift-debt.json` configuration and source-located diagnostics.

## How to get to it (user POV)

From the repository root, the checked-in consumer demonstrates the build plugin:

```sh
cd Examples/PluginConsumer
swift build
swift package swift-debt --target Demo --type-scope nominals --format json
```

The command plugin can also be invoked from another package that depends on
SwiftDebt. The build plugin requires `.swift-debt.json` in the consumer root;
`{}` is valid.

## Driving it with the SwiftDebt CLI helper

Run:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --feature plugins
```

The helper delegates to `scripts/smoke-test.py --plugins`. That real harness
creates an isolated consumer, proves the missing-configuration failure, adds a
configuration, builds, checks the generated `SwiftDebt.analysis.swift` stamp,
warms a no-op build, verifies source invalidation, exercises a failing and
recovering gate, and runs command-plugin target selection.

## Gotchas

- SwiftPM owns plugin process exit wrapping, so plugin status text can differ from the standalone CLI.
- Build checks are per target; use the command plugin for package-wide analysis.
- Do not attach the build plugin to a target whose selected source set is empty.
- Never reuse a consumer build directory across verification runs.
