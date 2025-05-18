// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataRaft",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "DataRaft",
            targets: ["DataRaft"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/angd-dev/data-lite-core.git",
            revision: "5c6942bd0b9636b5ac3e550453c07aac843e8416"
        ),
        .package(
            url: "https://github.com/angd-dev/data-lite-coder.git",
            revision: "5aec6ea5784dd5bd098bfa98036fbdc362a8931c"
        ),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "DataRaft",
            dependencies: [
                .product(name: "DataLiteCore", package: "data-lite-core"),
                .product(name: "DataLiteCoder", package: "data-lite-coder")
            ]
        ),
        .testTarget(
            name: "DataRaftTests",
            dependencies: ["DataRaft"],
            resources: [
                .copy("Resources/migration_1.sql"),
                .copy("Resources/migration_2.sql"),
                .copy("Resources/migration_3.sql"),
                .copy("Resources/migration_4.sql")
            ]
        )
    ]
)
