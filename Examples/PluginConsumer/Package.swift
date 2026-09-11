// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PluginConsumer",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Demo", targets: ["Demo"])],
    dependencies: [.package(name: "SwiftSCMA", path: "../..")],
    targets: [
        .target(name: "Demo", plugins: [.plugin(name: "SCMABuildPlugin", package: "SwiftSCMA")])
    ]
)
