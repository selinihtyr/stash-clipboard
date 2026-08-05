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
        // Uygulamanın ağa çıkan TEK parçası kendi hedefinde duruyor: "Stash ne
        // zaman ağa bağlanır?" sorusunun cevabı böylece tek bir klasör.
        .target(name: "Updater"),
        .testTarget(name: "UpdaterTests", dependencies: ["Updater"]),
        .target(name: "StashCore",
                dependencies: ["Store", "PasteboardKit", "PasteEngine", "Filters", "HotKey"]),
        .testTarget(name: "StashCoreTests",
                    dependencies: ["StashCore", "Store", "PasteEngine", "Filters"]),
        // "Resources/Sounds": aynı AppIcon.icns mantığı — SwiftPM'in otomatik
        // kaynak paketleme/`Bundle.module` yolunu değil, `scripts/bundle.sh`nin
        // elle `Contents/Resources/Sounds`e kopyaladığı, `Bundle.main`den
        // okunan düz dosyaları izliyoruz (bkz. `SoundFeedback.swift`).
        .executableTarget(name: "Stash",
                          dependencies: ["StashCore", "HotKey", "PasteboardKit", "Updater"],
                          exclude: ["Info.plist", "AppIcon.icns", "Resources/Sounds"]),
        .testTarget(name: "StashTests", dependencies: ["Stash"]),
    ]
)
