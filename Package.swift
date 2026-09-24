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
        .library(name: "SwiftDebtKit", targets: ["SwiftDebtKit", "SwiftDebtCore"]),
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
        .target(
            name: "SwiftDebtKit",
            dependencies: ["SwiftDebtCore", "SwiftDebtSyntax", "SwiftDebtReporting"],
            // DocC receives the excluded catalog explicitly in the documentation workflow.
            exclude: ["SwiftDebtKit.docc"]
        ),
        .executableTarget(name: "swift-debt", dependencies: ["SwiftDebtCore", "SwiftDebtInteractive", "SwiftDebtKit"]),
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
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "SwiftDebtInteractiveTests",
            dependencies: ["SwiftDebtCore", "SwiftDebtInteractive", "swift-debt"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
