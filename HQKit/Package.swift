// swift-tools-version: 6.4
import PackageDescription

// The model, its rules and parsing, with no UI: its tests run in a second, without building the app.
let package = Package(
    name: "HQKit",
    platforms: [.macOS(.v27)],
    products: [.library(name: "HQKit", targets: ["HQKit"])],
    targets: [
        .target(name: "HQKit"),
        .testTarget(name: "HQKitTests", dependencies: ["HQKit"]),
    ]
)
