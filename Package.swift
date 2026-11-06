// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "HQ",
    platforms: [.macOS(.v27)],
    targets: [
        // Model, rules and parsing with no UI, so tests run without the app.
        .target(name: "HQKit"),
        .executableTarget(
            name: "HQ",
            dependencies: ["HQKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "HQKitTests", dependencies: ["HQKit"]),
    ]
)
