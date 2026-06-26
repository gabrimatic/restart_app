// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

// This Package.swift is a build system shim. It should not be edited.
// See https://flutter.dev/to/spm for details.

import PackageDescription

let package = Package(
  name: "restart_app",
  platforms: [
    .iOS("11.0")
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
