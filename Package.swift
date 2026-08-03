// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Stash", targets: ["Stash"])
    ],
    targets: [
        .target(name: "Filters"),
        .testTarget(name: "FiltersTests", dependencies: ["Filters"]),
        .target(name: "Store", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
        .target(name: "PasteboardKit"),
        .testTarget(name: "PasteboardKitTests", dependencies: ["PasteboardKit"]),
        .target(name: "HotKey"),
        .testTarget(name: "HotKeyTests", dependencies: ["HotKey"]),
        .target(name: "PasteEngine", dependencies: ["Filters"]),
        .testTarget(name: "PasteEngineTests", dependencies: ["PasteEngine", "Filters"]),
        .target(name: "StashCore",
                dependencies: ["Store", "PasteboardKit", "PasteEngine", "Filters", "HotKey"]),
        .testTarget(name: "StashCoreTests",
                    dependencies: ["StashCore", "Store", "PasteEngine", "Filters"]),
        .executableTarget(name: "Stash", dependencies: ["StashCore", "HotKey"],
                          exclude: ["Info.plist"]),
    ]
)
