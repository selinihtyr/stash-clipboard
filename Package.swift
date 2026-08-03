// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v14)],
    products: [],
    targets: [
        .target(name: "Filters"),
        .testTarget(name: "FiltersTests", dependencies: ["Filters"]),
        .target(name: "Store", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
        .target(name: "PasteboardKit"),
        .testTarget(name: "PasteboardKitTests", dependencies: ["PasteboardKit"]),
    ]
)
