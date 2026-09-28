# Add a Programmatic Analysis Gate

Use the library when a Swift tool needs to analyze a directory and decide whether to accept its result.

## Add the package

Add the `SwiftDebtKit` product to your target as shown in <doc:LibraryAPI>. It exposes both `SwiftDebtKit` and `SwiftDebtCore` modules.

---

## Run the analysis service

```swift
import SwiftDebtCore
import SwiftDebtKit

let request = AnalysisRequest(
    path: "/path/to/project",
    format: .json,
    failOnViolation: true,
    thresholds: [.ccf: 15]
)

let result = try await AnalysisService().run(request)
print(result.standardOutput)

switch result.exitStatus {
case 0:
    print("Analysis complete; configured gates passed")
case 1:
    print("Analysis complete; a configured gate failed")
default:
    print("Input or analysis was incomplete")
}
```

The service applies the same source discovery, configuration, report rendering, and exit-status rules as the CLI. `result.report` holds the structured metric report. `result.rankedDebtAnalysis` is non-`nil` when ranked debt was requested or configured.

---

## Keep the result auditable

Set a stable input path, source revision, and configuration before comparing reports. Use `AnalysisRequest(debtReferenceTime:)` when Git-history recency participates in ranking. For a custom Git installation, set `gitExecutablePath` to an absolute executable path. See <doc:Determinism> for the inputs that must match across runs.
