// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CompilerEvidenceProbe",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ConditionalOverload"),
        .target(name: "ObservableMacro"),
        .target(name: "TypeError"),
    ],
    swiftLanguageModes: [.v6]
)
