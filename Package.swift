// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PowerMate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PowerMate", targets: ["PowerMate"])
    ],
    targets: [
        .executableTarget(
            name: "PowerMate",
            path: "Sources",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]
        )
    ]
)
