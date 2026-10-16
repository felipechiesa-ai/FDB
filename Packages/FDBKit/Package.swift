// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FDBKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "FDBPersistence", targets: ["FDBPersistence"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(
            name: "FDBPersistence",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "FDBPersistenceTests",
            dependencies: [
                "FDBPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
