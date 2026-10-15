// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "restart_app",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "restart-app", targets: ["restart_app"])
    ],
    // No FlutterFramework dependency: that package exists only from Flutter 3.44,
    // and this plugin supports Swift Package Manager from Flutter 3.24.
    dependencies: [],
    targets: [
        .target(
            name: "restart_app",
            dependencies: [],
            path: "Sources/restart_app"
        )
    ]
)
