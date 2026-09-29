// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pace",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pace",
            path: "Sources/Pace",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "PaceTests",
            dependencies: ["Pace"],
            path: "Tests/PaceTests"
        ),
    ]
)
