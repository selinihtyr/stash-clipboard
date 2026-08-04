import AppKit
import StashCore
import Store
import SwiftUI

/// `NSWindow.willCloseNotification` yalnızca `close()`'u (kırmızı düğme, ⌘W)
/// yakalar; kullanıcı pencereyi kapatmadan yalnızca "ordered out" ederse
/// (ör. ileride eklenecek bir "gizle" yolu) bu bildirim hiç gelmez. Bu alt
/// sınıf iki yok-olma yolunu da (`close` VE `orderOut`) tek bir kancaya
/// indirger — StripPanel'in kendi kapanma yollarını `dismiss()`te
/// birleştirmesiyle aynı gerekçe (bkz. StripPanel).
final class SettingsWindow: NSWindow {
    var onGoAway: (() -> Void)?

    override func close() {
        super.close()
        onGoAway?()
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onGoAway?()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    // Sahiplik burada, `SettingsView`de değil (bkz. I1): view'ın hayatta
    // kalması SwiftUI'nin `.onDisappear`i çağırmasına bağlı değil, ama
    // `isReleasedWhenClosed = false` + AppDelegate'in kontrolcüyü tutması
    // yüzünden pencere kapanınca view hiç sökülmüyor — `.onDisappear` bu
    // yapılandırmada asla tetiklenmiyor. Kontrolcü kendi ömrü boyunca var
    // olduğu için kaydı gerçek pencere yaşam döngüsü olaylarına
    // (SettingsWindow.onGoAway) bağlayabiliyor.
    let recorder = ShortcutRecorder()

    // `settingsStore` AppDelegate'ten geliyor ve onunla paylaşılıyor (kopya
    // değil, aynı referans) — pencere kapatılmadan yaşadığı için
    // (`isReleasedWhenClosed = false`), AppDelegate'in sonradan yaptığı bir
    // değişiklik (ör. reddedilen bir kısayolu geri almak) bir sonraki
    // `present()`'ta otomatik görünür (fix round 2).
    convenience init(settingsStore: SettingsStore, store: ClipStore,
                     onChange: @escaping (StashCore.Settings) -> Void) {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Stash Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)

        // `self` artık var; `recorder` (varsayılan değerle otomatik kurulmuş)
        // ve view'ı burada bağlıyoruz.
        let recorder = self.recorder
        window.onGoAway = { [recorder] in recorder.stop() }
        let view = SettingsView(settingsStore: settingsStore, store: store,
                                onChange: onChange, recorder: recorder)
        window.contentView = NSHostingView(rootView: view)
    }

    func present() {
        // Her açılış temiz bir durumla başlamalı: `onGoAway` her yok-olma
        // yolunu yakalasa da, burada da durdurmak ikinci bir güvenlik ağı —
        // kullanıcı "Değiştir"e basıp pencereyi hiç kapatmadan bir sonraki
        // sekmeye geçseydi bile artık kayıt sızmıyor (I1).
        recorder.stop()
        // Ayarlar penceresi normal bir pencere: LSUIElement uygulaması olduğumuz
        // için öne gelmesi elle etkinleştirme istiyor.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
