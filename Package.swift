// swift-tools-version: 6.0
// Builds the pieces of DarkCharge. `make app` assembles them into DarkCharge.app.

import PackageDescription

let package = Package(
    name: "DarkCharge",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared by the app and the helper: SMC access, lid state, the heartbeat format,
        // and the decision whether the LED should be off.
        .target(name: "DarkChargeCore"),
        // Root LaunchDaemon that writes the LED, registered by the app via SMAppService.
        .executableTarget(name: "DarkChargeHelper", dependencies: ["DarkChargeCore"]),
        // Menu bar app.
        .executableTarget(name: "DarkCharge", dependencies: ["DarkChargeCore"]),
        .testTarget(name: "DarkChargeCoreTests", dependencies: ["DarkChargeCore"]),
    ]
)
