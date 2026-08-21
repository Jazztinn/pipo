// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Pipo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PipoApp", targets: ["PipoApp"]),
        .library(name: "PipoUI", targets: ["PipoUI"]),
        .library(name: "PipoAppCore", targets: ["PipoAppCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.2"),
    ],
    targets: [
        .target(
            name: "PipoAppCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "app/Sources/PipoAppCore"
        ),
        .target(
            name: "PipoUI",
            dependencies: ["PipoAppCore"],
            path: "app/Sources/PipoUI"
        ),
        .executableTarget(
            name: "PipoApp",
            dependencies: [
                "PipoAppCore",
                "PipoUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "app/Sources/PipoApp"
        ),
        .testTarget(
            name: "PipoAppCoreTests",
            dependencies: ["PipoAppCore"],
            path: "app/Tests/PipoAppCoreTests"
        ),
        .testTarget(
            name: "PipoUITests",
            dependencies: ["PipoUI"],
            path: "app/Tests/PipoUITests"
        ),
    ]
)

