// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftDebtSQVector",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SwiftDebtSQVector", targets: ["SwiftDebtSQVector"])
    ],
    dependencies: [
        .package(name: "SwiftDebt", path: "../.."),
        .package(path: "../../.vendor/sqvector-swift/Packages/SQVector"),
    ],
    targets: [
        .target(
            name: "SwiftDebtSQVector",
            dependencies: [
                .product(name: "SwiftDebtKit", package: "SwiftDebt"),
                .product(name: "SQVectorStatic", package: "SQVector"),
            ]
        ),
        .testTarget(name: "SwiftDebtSQVectorTests", dependencies: ["SwiftDebtSQVector"]),
    ],
    swiftLanguageModes: [.v6]
)
