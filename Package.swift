// swift-tools-version:5.9
// Pointbit — menu bar app. `swift build` / `swift test`; build.sh makes the .app bundle.
import PackageDescription

let package = Package(
    name: "Pointbit",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PointbitKit"),
        .executableTarget(name: "Pointbit", dependencies: ["PointbitKit"]),
        .executableTarget(name: "MakeIcon", dependencies: ["PointbitKit"]),
        .testTarget(name: "PointbitKitTests", dependencies: ["PointbitKit"]),
    ]
)
