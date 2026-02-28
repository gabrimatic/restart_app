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
    dependencies: [],
    targets: [
        .target(
            name: "restart_app",
            dependencies: [],
            path: "../Classes"
        )
    ]
)
