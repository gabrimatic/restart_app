// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "restart_app",
    platforms: [
        .iOS("12.0")
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
