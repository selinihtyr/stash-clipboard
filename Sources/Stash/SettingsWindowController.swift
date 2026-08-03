import AppKit
import StashCore
import Store
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    // `settingsStore` AppDelegate'ten geliyor ve onunla paylaşılıyor (kopya
    // değil, aynı referans) — pencere kapatılmadan yaşadığı için
    // (`isReleasedWhenClosed = false`), AppDelegate'in sonradan yaptığı bir
    // değişiklik (ör. reddedilen bir kısayolu geri almak) bir sonraki
    // `present()`'ta otomatik görünür (fix round 2).
    convenience init(settingsStore: SettingsStore, store: ClipStore,
                     onChange: @escaping (StashCore.Settings) -> Void) {
        let view = SettingsView(settingsStore: settingsStore, store: store, onChange: onChange)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Stash Ayarları"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        // Ayarlar penceresi normal bir pencere: LSUIElement uygulaması olduğumuz
        // için öne gelmesi elle etkinleştirme istiyor.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
