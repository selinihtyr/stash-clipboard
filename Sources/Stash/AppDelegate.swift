import AppKit
import HotKey
import PasteboardKit
import PasteEngine
import StashCore
import Store
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: StripPanel?
    private var hotKey = HotKeyCenter()
    private var coordinator: CaptureCoordinator?
    private var model: StripModel?
    private var settings = Settings.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.on.square.dashed",
                                     accessibilityDescription: "Stash")
        item.menu = buildMenu()
        statusItem = item

        do {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
                .appendingPathComponent("Stash")
            let store = try ClipStore(directory: dir)
            let engine = PasteEngine(pasteboard: SystemPasteboardWriter(),
                                     keystrokes: SystemKeystrokeSender())
            let model = StripModel(store: store, engine: engine, settings: settings)
            self.model = model

            // blockedBundleIDs burada ClipCapture'a ulaşmazsa uygulamanın
            // merkezi mahremiyet sözü (şifre yöneticilerinden asla kopya
            // kaydetme) hiçbir yerde uygulanmamış olur — bkz. Task 8 incelemesi.
            let capture = ClipCapture(pasteboard: SystemPasteboard(),
                                      policy: CapturePolicy(blockedBundleIDs: settings.blockedBundleIDs))
            let coordinator = CaptureCoordinator(store: store, capture: capture)
            coordinator.onCapture = { [weak self] in try? self?.model?.reload() }
            coordinator.onError = { [weak self] _ in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle",
                    accessibilityDescription: "Stash: disk hatası")
            }
            coordinator.start()
            self.coordinator = coordinator
        } catch {
            presentFatal(error)
            return
        }

        registerHotKey()
    }

    private func registerHotKey() {
        do {
            try hotKey.register(settings.combo) { [weak self] in self?.toggleStrip() }
        } catch HotKeyError.alreadyTaken {
            // Gerçek çakışma: kullanıcı başka bir kısayol seçebilir.
            let alert = NSAlert()
            alert.messageText = "Kısayol kaydedilemedi"
            alert.informativeText = """
                \(settings.combo.displayString) başka bir uygulama tarafından kullanılıyor. \
                Ayarlar'dan farklı bir kombinasyon seç.
                """
            alert.runModal()
        } catch HotKeyError.handlerInstallFailed(let status) {
            // Çakışma değil, dahili bir kurulum hatası: kullanıcıyı başka bir
            // kombinasyon denemeye yönlendirmek yanlış teşhis olur — sebep
            // sistemde, kısayolda değil.
            let alert = NSAlert()
            alert.messageText = "Kısayol kaydedilemedi"
            alert.informativeText = """
                Sistem olay işleyicisi kurulamadı (durum kodu \(status)). \
                Bu bir kısayol çakışması değil, dahili bir hata. Uygulamayı yeniden \
                başlatmayı deneyebilirsin.
                """
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Kısayol kaydedilemedi"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Stash'i aç", action: #selector(toggleStrip), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc func toggleStrip() {
        if let panel, panel.isVisible { panel.dismiss(); return }
        guard let model else { return }
        try? model.reload()
        let host = NSHostingView(rootView: Text("Şerit buraya gelecek")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.9)))
        let panel = self.panel ?? StripPanel(contentView: host)
        panel.contentView = host
        self.panel = panel
        panel.show(on: Self.screenWithMouse())
    }

    /// Şerit farenin bulunduğu ekranda açılır; iki ekranlı kurulumda "yanlış
    /// ekranda açıldı" en sık şikayet edilen davranış.
    static func screenWithMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main!
    }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Stash başlatılamadı"
        alert.informativeText = "\(error)"
        alert.runModal()
        NSApp.terminate(nil)
    }
}
