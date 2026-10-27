// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCallIndicator",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacCallIndicator", targets: ["MacCallIndicator"])],
    targets: [
        .executableTarget(name: "MacCallIndicator"),
        .testTarget(name: "MacCallIndicatorTests", dependencies: ["MacCallIndicator"])
    ]
)
