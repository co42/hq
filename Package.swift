// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "HQ",
    platforms: [.macOS(.v27)],
    // Model, rules and parsing with no UI, so tests run without the app: swift test --package-path HQKit.
    dependencies: [.package(path: "HQKit")],
    targets: [
        .executableTarget(
            name: "HQ",
            dependencies: [.product(name: "HQKit", package: "HQKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
