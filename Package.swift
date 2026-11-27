// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RubberStamp",
    platforms: [.macOS(.v13)],
    targets: [
        // GitHub access and approval rules, free of UI so the tests can use them.
        .target(name: "RubberStampKit", path: "Sources/RubberStampKit"),
        .executableTarget(name: "RubberStamp", dependencies: ["RubberStampKit"], path: "Sources/RubberStamp"),
        .testTarget(name: "RubberStampKitTests", dependencies: ["RubberStampKit"], path: "Tests/RubberStampKitTests"),
    ]
)
