// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftSCMA",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "scma", targets: ["scma"]),
        .library(name: "SCMAKit", targets: ["SCMAKit", "SCMACore"]),
        .plugin(name: "SCMACommandPlugin", targets: ["SCMACommandPlugin"]),
        .plugin(name: "SCMABuildPlugin", targets: ["SCMABuildPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .target(name: "SCMACore"),
        .target(
            name: "SCMASyntax",
            dependencies: [
                "SCMACore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(name: "SCMAReporting", dependencies: ["SCMACore"]),
        .target(name: "SCMAKit", dependencies: ["SCMACore", "SCMASyntax", "SCMAReporting"]),
        .executableTarget(name: "scma", dependencies: ["SCMACore", "SCMAKit"]),
        .plugin(
            name: "SCMACommandPlugin",
            capability: .command(
                intent: .custom(verb: "scma", description: "Analyze Swift code metrics"),
                permissions: []
            ),
            dependencies: ["scma"]
        ),
        .plugin(name: "SCMABuildPlugin", capability: .buildTool(), dependencies: ["scma"]),
        .testTarget(name: "SCMACoreTests", dependencies: ["SCMACore"]),
        .testTarget(
            name: "SCMASyntaxTests",
            dependencies: ["SCMACore", "SCMASyntax"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "SCMAKitTests",
            dependencies: ["SCMACore", "SCMAKit", "SCMAReporting"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
