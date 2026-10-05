// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusTrio",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "StatusTrio", targets: ["StatusTrio"]),
        .library(name: "StatusTrioMediaBridge", type: .dynamic, targets: ["StatusTrioMediaBridge"]),
        .executable(name: "StatusTrioMagSafeHelper", targets: ["StatusTrioMagSafeHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .target(name: "StatusTrioMediaBridge", linkerSettings: [.linkedFramework("Foundation")]),
        .target(name: "DisplayFeaturesBridge", linkerSettings: [.linkedFramework("Foundation")]),
        .target(name: "HotspotBridge", linkerSettings: [.linkedFramework("CoreWLAN")]),
        .target(
            name: "SMCDefinitions",
            path: "Sources/SMCDefinitions",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MagSafeSMC",
            dependencies: ["SMCDefinitions"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "StatusTrioCore",
            dependencies: [
                "HotspotBridge",
                "DisplayFeaturesBridge",
                "MagSafeSMC",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/StatusTrioCore",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "StatusTrio",
            dependencies: ["StatusTrioCore"],
            path: "Sources/StatusTrio"
        ),
        .executableTarget(
            name: "StatusTrioMagSafeHelper",
            dependencies: ["MagSafeSMC"],
            path: "Sources/StatusTrioMagSafeHelper",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "StatusTrioCoreTests",
            dependencies: ["StatusTrioCore", "MagSafeSMC"],
            path: "Tests/StatusTrioCoreTests"
        )
    ]
)
