// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ReleaseWatcher",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ReleaseWatcher", targets: ["ReleaseWatcher"]),
    ],
    targets: [
        .executableTarget(
            name: "ReleaseWatcher",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
