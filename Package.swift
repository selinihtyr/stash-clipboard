// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v14)],
    products: [],
    targets: [
        .target(name: "Filters"),
        .testTarget(name: "FiltersTests", dependencies: ["Filters"]),
    ]
)
