// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PluginConsumer",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Demo", targets: ["Demo"])],
    dependencies: [.package(name: "SwiftDebt", path: "../..")],
    targets: [
        .target(name: "Demo", plugins: [.plugin(name: "SwiftDebtBuildPlugin", package: "SwiftDebt")])
    ]
)
