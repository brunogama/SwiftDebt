// swift-tools-version: 6.2
import PackageDescription

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
        .library(name: "SwiftDebtKit", targets: ["SwiftDebtKit", "SwiftDebtCore", "SwiftDebtLifecycle"]),
        .library(name: "SwiftDebtLifecycle", targets: ["SwiftDebtLifecycle"]),
        .plugin(name: "SwiftDebtCommandPlugin", targets: ["SwiftDebtCommandPlugin"]),
        .plugin(name: "SwiftDebtBuildPlugin", targets: ["SwiftDebtBuildPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
        // Build-time tooling for the checked-in SwiftDebtKit DocC catalog and Pages site.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", exact: "1.5.0"),
    ],
    targets: [
        .target(name: "SwiftDebtCore"),
        .target(
            name: "SwiftDebtSyntax",
            dependencies: [
                "SwiftDebtCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(name: "SwiftDebtReporting", dependencies: ["SwiftDebtCore"]),
        .target(name: "SwiftDebtInteractive", dependencies: ["SwiftDebtCore"]),
        .target(name: "SwiftDebtLifecycle", dependencies: ["SwiftDebtCore"]),
        .target(
            name: "SwiftDebtKit",
            // The composition root converts engine-owned rule results into persisted lifecycle observations.
            dependencies: [
                "SwiftDebtCore",
                "SwiftDebtSyntax",
                "SwiftDebtReporting",
                "SwiftDebtLifecycle",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ],
            // Keep the catalog in the target for ordinary DocC and Swift Package Index builds.
            resources: [.copy("SwiftDebtKit.docc")]
        ),
        .executableTarget(
            name: "swift-debt",
            dependencies: ["SwiftDebtCore", "SwiftDebtInteractive", "SwiftDebtKit", "SwiftDebtLifecycle"]
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
        .testTarget(
            name: "SwiftDebtCoreTests",
            dependencies: ["SwiftDebtCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "SwiftDebtSyntaxTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtSyntax"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "SwiftDebtKitTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtKit", "SwiftDebtReporting"],
            exclude: ["Fixtures/RepositoryAnalysis", "Fixtures/RepositoryQualification"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "SwiftDebtInteractiveTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtInteractive", "swift-debt"]
        ),
        .testTarget(
            name: "SwiftDebtLifecycleTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtLifecycle", "SwiftDebtSyntax", "swift-debt"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
