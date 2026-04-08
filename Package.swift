// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flock",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/k3rnelpan11c/SwiftTerm", branch: "flock-scroll-lock")
    ],
    targets: [
        .executableTarget(
            name: "Flock",
            dependencies: ["SwiftTerm"],
            path: "Sources/Flock"
        )
    ]
)
