// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SurfsharkGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SurfsharkGuard",
            path: "Sources/SurfsharkGuard"
        ),
        .testTarget(
            name: "SurfsharkGuardTests",
            dependencies: ["SurfsharkGuard"],
            path: "Tests/SurfsharkGuardTests"
        )
    ]
)
