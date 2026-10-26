# SwiftDebt verification feature map

The primary user surface is the short-lived `swift-debt` executable. Each
feature below names the user entry point, the stable drive, and the observable
end state that proves it worked.

| Feature | User entry point | Proof artifact |
| --- | --- | --- |
| [Metric analysis](metric-analysis.md) | `swift-debt analyze` | Complete JSON report and deterministic repeat |
| [Ranked debt](ranked-debt.md) | `swift-debt debt analyze` | Native debt JSON with frozen reference time |
| [SwiftPM plugins](swiftpm-plugins.md) | `swift build` and `swift package swift-debt` | Consumer build and analysis stamp |

Run one feature through the helper:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --feature metrics
```
