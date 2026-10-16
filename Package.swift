// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chillbar",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Chillbar", targets: ["ChillbarApp"]),
        .library(name: "ACCore", targets: ["ACCore"]),
        .library(name: "ACTuya", targets: ["ACTuya"]),
    ],
    targets: [
        .target(name: "ACCore"),
        .target(name: "ACTuya", dependencies: ["ACCore"], resources: [.process("Profiles")]),
        .target(name: "ACSimulator", dependencies: ["ACCore"]),
        .target(name: "ACApplication", dependencies: ["ACCore"]),
        .target(name: "ACInterface", dependencies: ["ACApplication"], resources: [.process("Resources")]),
        .executableTarget(
            name: "ChillbarApp",
            dependencies: ["ACInterface", "ACApplication", "ACSimulator", "ACTuya"]
        ),
        .executableTarget(name: "ChillbarAssets"),
        .executableTarget(name: "ChillbarProbe", dependencies: ["ACTuya"]),
        .executableTarget(
            name: "ACSnapshots",
            dependencies: ["ACInterface", "ACApplication", "ACSimulator", "ACTuya"]
        ),
        .testTarget(name: "ACCoreTests", dependencies: ["ACCore"]),
        .testTarget(name: "ACTuyaTests", dependencies: ["ACTuya"]),
        .testTarget(name: "ACApplicationTests", dependencies: ["ACApplication", "ACSimulator"]),
        .testTarget(name: "ACInterfaceTests", dependencies: ["ACInterface"]),
    ]
)
