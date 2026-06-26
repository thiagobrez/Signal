// swift-tools-version: 6.0
// Locally vendored copy of MrKai77/DynamicNotchKit @ 1.1.0.
// Vendored so we can patch the floating-style margins (see Sources/.../Views/NotchlessView.swift).
// The upstream docc-plugin dependency and test target are dropped to keep this self-contained.

import PackageDescription

let package = Package(
    name: "DynamicNotchKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DynamicNotchKit",
            targets: ["DynamicNotchKit"]
        )
    ],
    targets: [
        .target(
            name: "DynamicNotchKit",
            path: "Sources"
        )
    ]
)
