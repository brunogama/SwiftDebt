// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WithUnsafeFlags",
    targets: [
        .target(
            name: "WithUnsafeFlags",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-actor-data-race-checks"])
            ]
        )
    ]
)
