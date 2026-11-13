// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCallIndicator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacCallIndicator", targets: ["MacCallIndicator"]),
        .executable(name: "DeskPresence", targets: ["DeskPresence"])
    ],
    targets: [
        .target(name: "ComputerPresence"),
        .executableTarget(name: "MacCallIndicator", dependencies: ["ComputerPresence"]),
        .executableTarget(name: "DeskPresence", dependencies: ["ComputerPresence"]),
        .testTarget(name: "MacCallIndicatorTests", dependencies: ["MacCallIndicator", "ComputerPresence"])
    ]
)
