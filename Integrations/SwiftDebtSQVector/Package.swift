// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftDebtSQVector",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftDebtSQVector", targets: ["SwiftDebtSQVector"])
    ],
    dependencies: [
        .package(name: "SwiftDebt", path: "../.."),
        .package(
            url: "https://github.com/brunogama/sqvector-swift.git",
            revision: "aafd9ae601826112978127c7cb611c94ab8a2e06"
        ),
    ],
    targets: [
        .target(
            name: "SwiftDebtSQVector",
            dependencies: [
                .product(name: "SwiftDebtKit", package: "SwiftDebt"),
                .product(
                    name: "SQVectorStatic",
                    package: "sqvector-swift",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
            ]
        ),
        .testTarget(
            name: "SwiftDebtSQVectorTests",
            dependencies: [
                "SwiftDebtSQVector",
                .product(
                    name: "SQVectorStatic",
                    package: "sqvector-swift",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
