// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FDBKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "FDBDomain", targets: ["FDBDomain"]),
        .library(name: "FDBPersistence", targets: ["FDBPersistence"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(name: "FDBDomain"),
        .target(
            name: "FDBPersistence",
            dependencies: [
                "FDBDomain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "FDBDomainTests",
            dependencies: ["FDBDomain"]
        ),
        .testTarget(
            name: "FDBPersistenceTests",
            dependencies: [
                "FDBDomain",
                "FDBPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
