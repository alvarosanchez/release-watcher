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
            resources: [
                .process("Resources/AppIcon.png"),
                .process("Resources/MenuBarIcon.png"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
