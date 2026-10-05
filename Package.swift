// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glance",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Glance", targets: ["Glance"]),
        .library(name: "GlanceMediaBridge", type: .dynamic, targets: ["GlanceMediaBridge"]),
        .executable(name: "GlanceMagSafeHelper", targets: ["GlanceMagSafeHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .target(name: "GlanceMediaBridge", linkerSettings: [.linkedFramework("Foundation")]),
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
            name: "GlanceCore",
            dependencies: [
                "HotspotBridge",
                "DisplayFeaturesBridge",
                "MagSafeSMC",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/GlanceCore",
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
            name: "Glance",
            dependencies: ["GlanceCore"],
            path: "Sources/Glance"
        ),
        .executableTarget(
            name: "GlanceMagSafeHelper",
            dependencies: ["MagSafeSMC"],
            path: "Sources/GlanceMagSafeHelper",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "GlanceCoreTests",
            dependencies: ["GlanceCore", "MagSafeSMC", "GlanceMediaBridge"],
            path: "Tests/GlanceCoreTests"
        )
    ]
)
