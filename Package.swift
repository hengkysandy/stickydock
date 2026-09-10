// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickyDock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StickyDock", targets: ["StickyDock"]),
        .library(name: "StickyDockCore", targets: ["StickyDockCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "StickyDockCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Resources/notes_bridge.js")]
        ),
        .executableTarget(
            name: "StickyDock",
            dependencies: ["StickyDockCore"]
        ),
        .testTarget(
            name: "StickyDockCoreTests",
            dependencies: ["StickyDockCore"]
        ),
    ]
)
