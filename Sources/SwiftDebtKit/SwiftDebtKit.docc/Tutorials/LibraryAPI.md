# Analyze In-Memory Source with the Library API

Add the library product, provide source units, and inspect an analysis report without file discovery.

## Add SwiftDebtKit

Declare the released package in `Package.swift` and add `SwiftDebtKit` to the target that owns your analysis tool:

```swift
dependencies: [
    // swiftdebt-release-version:start
    .package(url: "https://github.com/brunogama/SwiftDebt.git", from: "0.7.3")
    // swiftdebt-release-version:end
],
targets: [
    .executableTarget(
        name: "DebtTool",
        dependencies: [.product(name: "SwiftDebtKit", package: "SwiftDebt")]
    )
]
```

## Run an in-memory analysis

Each `SourceUnit` has a stable path, module name, and source string. ``Analyzer`` validates the options, parses concurrently up to the requested job count, and returns an `AnalysisReport`.

```swift
import SwiftDebtCore
import SwiftDebtKit

let source = SourceUnit(
    path: "Sources/Feature/Example.swift",
    module: "Feature",
    content: """
    final class Example {
        func answer(_ value: Int) -> Int {
            if value > 0 { return value }
            return 0
        }
    }
    """
)

let report = try await Analyzer().analyze(
    [source],
    options: AnalysisOptions(typeScope: .nominals),
    jobs: 2
)

print(report.metrics)
```

Use ``AnalysisService`` with an ``AnalysisRequest`` when your tool needs the same filesystem discovery, configuration loading, report rendering, and exit-status policy as the CLI and plugins.
