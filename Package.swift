// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinyTaskMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TinyTaskMac", targets: ["TinyTaskMac"]),
        .executable(name: "TinyTaskMacSelfTest", targets: ["TinyTaskMacSelfTest"])
    ],
    targets: [
        .target(
            name: "TinyTaskMacKit",
            path: "Sources/TinyTaskMac"
        ),
        .executableTarget(
            name: "TinyTaskMac",
            dependencies: ["TinyTaskMacKit"],
            path: "Sources/TinyTaskMacApp"
        ),
        .executableTarget(
            name: "TinyTaskMacSelfTest",
            dependencies: ["TinyTaskMacKit"],
            path: "Sources/TinyTaskMacSelfTest"
        )
    ]
)
