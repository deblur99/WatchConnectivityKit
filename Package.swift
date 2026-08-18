// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchConnectivityKit",
    platforms: [
        .iOS(.v15),
        .watchOS(.v9),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "WatchConnectivityKit",
            targets: ["WatchConnectivityKit"]
        ),
    ],
    targets: [
        .target(
            name: "WatchConnectivityKit",
            dependencies: [],
            path: "Sources/WatchConnectivityKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            linkerSettings: [
                .linkedFramework("WatchConnectivity", .when(platforms: [.iOS, .watchOS])),
            ]
        ),
        .testTarget(
            name: "WatchConnectivityKitTests",
            dependencies: ["WatchConnectivityKit"],
            path: "Tests/WatchConnectivityKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
