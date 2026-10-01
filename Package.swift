// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenDezor",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OpenDezor",
            targets: ["OpenDezor"]
        ),
    ],
    targets: [
        .target(
            name: "OpenDezor",
            path: "OpenDezor",
            exclude: [
                "Resources",
                "App/OpenDezorApp.swift"
            ]
        ),
        .testTarget(
            name: "OpenDezorTests",
            dependencies: ["OpenDezor"],
            path: "OpenDezorTests"
        ),
    ]
)
