// swift-tools-version: 6.2
import PackageDescription

let warningsAsErrors: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "SwiftDebt",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .executable(name: "swift-debt", targets: ["swift-debt"]),
        .library(name: "SwiftDebtKit", targets: ["SwiftDebtKit", "SwiftDebtCore"]),
        .plugin(name: "SwiftDebtCommandPlugin", targets: ["SwiftDebtCommandPlugin"]),
        .plugin(name: "SwiftDebtBuildPlugin", targets: ["SwiftDebtBuildPlugin"]),
        .plugin(
            name: "RuleManifestValidationPlugin", targets: ["RuleManifestValidationPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
        .package(
            url: "https://github.com/hummingbird-project/swift-mustache.git",
            exact: "2.1.0"),
        // Build-time DocC tooling for public API references and the shared article catalog.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftDebtCore",
            exclude: ["RuleCatalog/Manifest/RuleCatalogManifest.yaml"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SwiftDebtSyntax",
            dependencies: [
                "SwiftDebtCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SwiftDebtReporting",
            dependencies: [
                "SwiftDebtCore",
                .product(name: "Mustache", package: "swift-mustache"),
            ],
            resources: [.process("Resources")],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SwiftDebtInteractive",
            dependencies: ["SwiftDebtCore"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SwiftDebtKit",
            dependencies: ["SwiftDebtCore", "SwiftDebtSyntax", "SwiftDebtReporting"],
            resources: [.copy("SwiftDebtKit.docc")],
            swiftSettings: warningsAsErrors
        ),
        .executableTarget(
            name: "swift-debt",
            dependencies: ["SwiftDebtCore", "SwiftDebtInteractive", "SwiftDebtKit"],
            swiftSettings: warningsAsErrors,
            plugins: ["RuleManifestValidationPlugin"]
        ),
        .executableTarget(
            name: "swift-debt-manifest-lint",
            dependencies: ["SwiftDebtCore"],
            swiftSettings: warningsAsErrors
        ),
        .plugin(
            name: "SwiftDebtCommandPlugin",
            capability: .command(
                intent: .custom(verb: "swift-debt", description: "Analyze Swift code metrics"),
                permissions: []
            ),
            dependencies: ["swift-debt"]
        ),
        .plugin(name: "SwiftDebtBuildPlugin", capability: .buildTool(), dependencies: ["swift-debt"]),
        .plugin(
            name: "RuleManifestValidationPlugin",
            capability: .buildTool(),
            dependencies: ["swift-debt-manifest-lint"]
        ),
        .testTarget(
            name: "SwiftDebtCoreTests",
            dependencies: ["SwiftDebtCore"],
            exclude: ["Fixtures/ProjectRules"],
            resources: [.process("Fixtures")],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "SwiftDebtSyntaxTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtSyntax"],
            resources: [.process("Fixtures")],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "SwiftDebtKitTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtKit", "SwiftDebtReporting"],
            resources: [.process("Fixtures")],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "SwiftDebtInteractiveTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtInteractive", "swift-debt"],
            swiftSettings: warningsAsErrors
        ),
    ],
    swiftLanguageModes: [.v6]
)
