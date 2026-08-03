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
        let host = NSHostingView(rootView: StripView(model: model))
        let panel = self.panel ?? StripPanel(contentView: host)
        panel.contentView = host
        // dismiss() panelin kapandığı HER yoldan geçer (Escape, tekrar
        // kısayola basma, dışarı tıklama) — süzgeci tek bir yerde temizlemek
        // için doğru kanca burası; her çağıran yerin bunu hatırlaması gerekmez.
        panel.onDismiss = { [weak self] in self?.model?.query = "" }
        panel.onKey = { [weak self] event in
            guard let self, let model = self.model else { return false }
            guard let command = stripCommand(keyCode: event.keyCode,
                                             characters: event.charactersIgnoringModifiers,
                                             modifiers: event.modifierFlags) else { return false }
            switch command {
            case .moveLeft: model.moveSelection(by: -1)
            case .moveRight: model.moveSelection(by: 1)
            case .paste(let filtered):
                self.finishPaste(model.pasteSelected(applyingFilters: filtered))
            case .pasteIndex(let index):
                // Görünürden az kart varken ⌘N basılırsa hiçbir şey olmamalı;
                // aksi halde eski seçim sessizce yapıştırılır — yanlış kartı
                // panoya göndermek boş yapmaktan daha kötü.
                guard model.visible.indices.contains(index) else { break }
                model.select(index: index)
                self.finishPaste(model.pasteSelected(applyingFilters: false))
            case .togglePin: try? model.togglePinSelected()
            case .delete: try? model.deleteSelected()
            case .nextTab: self.advanceTab()
            case .moveToShelf: self.showShelfMenu()
            case .dismiss:
                self.panel?.dismiss()
            case .type(let char):
                model.query.append(char)
                try? model.reload()
            case .backspace:
                if !model.query.isEmpty { model.query.removeLast(); try? model.reload() }
            }
            return true
        }
        self.panel = panel
        panel.show(on: Self.screenWithMouse())
    }

    /// Yapıştırma isteği üç farklı sonuçla dönebilir; sessizce yutmak
    /// kullanıcıyı kör bırakır — özellikle klavyeden gidiliyorsa görsel bir
    /// ipucu yok, tek geri bildirim bu.
    private func finishPaste(_ outcome: PasteOutcome?) {
        guard let outcome else {
            // nil = seçili bir şey yok ya da seçili kartın yapıştırılacak
            // içeriği yok (boş şerit, ya da Return'e basılan an). Hiçbir şey
            // seçilmediyse hiçbir şey kapanmamalı — panel açık kalır, zaten
            // boş durumda başlıktaki "Henüz bir şey kopyalamadın." zaten
            // sebebini söylüyor; ayrı bir uyarıya gerek yok.
            return
        }
        panel?.dismiss()
        switch outcome {
        case .pastedIntoFrontmostApp:
            return
        case .copiedOnlyNoAccessibilityPermission:
            // Sessizce kopyalayıp bırakmıyoruz: kullanıcı ⌘V beklerken hiçbir şey
            // olmadığını görürse uygulamayı bozuk sanır.
            let alert = NSAlert()
            alert.messageText = "Panoya kopyalandı"
            alert.informativeText = """
                Doğrudan yapıştırma için Stash'in Erişilebilirlik izni gerekiyor. \
                Şimdilik ⌘V ile yapıştırabilirsin.
                """
            alert.addButton(withTitle: "İzin ver")
            alert.addButton(withTitle: "Şimdi değil")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        case .copiedOnlyKeystrokeFailed:
            // İzin zaten verilmiş; sorun izinde değil, tek seferlik tuş
            // gönderiminde. Kullanıcıyı izin ayarına yönlendirmek yanlış
            // teşhis olur — burada gösterilecek tek doğru şey içeriğin
            // panoda olduğu ve ⌘V ile yapıştırılabileceği.
            let alert = NSAlert()
            alert.messageText = "Panoya kopyalandı"
            alert.informativeText = "Otomatik yapıştırma bu sefer olmadı. İçerik panoda, ⌘V ile yapıştır."
            alert.addButton(withTitle: "Tamam")
            alert.runModal()
        }
    }

    /// Kullanıcı şeritteyken sekmeler arasında dolaşır: önce sabit üçlü
    /// (Tümü/Sabitlenen/Görseller), ardından kullanıcının rafları — sırası
    /// StripView'daki sekme çubuğuyla aynı olmalı, yoksa ⇥ görünenden
    /// başka bir sekmeye zıplar.
    private func advanceTab() {
        guard let model else { return }
        let all: [StripTab] = [.all, .pinned, .images] + model.shelves.map { .shelf($0.id) }
        let index = all.firstIndex(of: model.tab) ?? 0
        model.tab = all[(index + 1) % all.count]
        try? model.reload()
    }

    /// ⌃S: seçili kartı bir rafa taşımak için raf listesini menü olarak
    /// gösterir. "Yeni raf oluştur…" her zaman menüde; henüz hiç raf yoksa
    /// menü boş açılıp kapanmaz — kullanıcı rafların nereden geldiğini
    /// buradan öğrenir.
    private func showShelfMenu() {
        guard let model, model.visible.indices.contains(model.selectedIndex) else { return }
        let menu = NSMenu()
        for shelf in model.shelves {
            let item = menu.addItem(withTitle: shelf.name,
                                    action: #selector(moveSelectedToShelf(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shelf.id
        }
        if !model.shelves.isEmpty { menu.addItem(.separator()) }
        let newItem = menu.addItem(withTitle: "Yeni raf oluştur…",
                                   action: #selector(createShelfAndMoveSelected), keyEquivalent: "")
        newItem.target = self
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func moveSelectedToShelf(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        try? model?.moveSelectedToShelf(id)
    }

    @objc private func createShelfAndMoveSelected() {
        guard let model else { return }
        let alert = NSAlert()
        alert.messageText = "Yeni raf"
        alert.informativeText = "Rafa bir ad ver."
        alert.addButton(withTitle: "Oluştur")
        alert.addButton(withTitle: "Vazgeç")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let shelf = try model.createShelf(name: field.stringValue)
            try model.moveSelectedToShelf(shelf.id)
        } catch {
            // Boş ad createShelf'i StoreError ile düşürür; sessizce hiçbir
            // şey olmamış gibi davranmak kullanıcıyı neyin ters gittiği
            // konusunda karanlıkta bırakır.
            let errorAlert = NSAlert()
            errorAlert.messageText = "Raf oluşturulamadı"
            errorAlert.informativeText = "\(error)"
            errorAlert.runModal()
        }
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
