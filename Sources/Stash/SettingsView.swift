import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Filters
import HotKey
import StashCore
import Store
import SwiftUI

/// Bir sonraki tuş vuruşunu yakalayıp bir `KeyCombo`ya çevirir. Global bir
/// olay musluğu (CGEventTap) Erişilebilirlik izni ister; pencere zaten öndeyken
/// tek bir tuşu yakalamak için yerel bir izleyici yeterli ve izin istemiyor —
/// izinsiz açılışın (bkz. HotKeyCenter'daki RegisterEventHotKey tercihi) aynı
/// gerekçesi burada da geçerli.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    /// Yalnızca test için: gerçek bir tuş vuruşu göndermeden izleyicinin
    /// hâlâ kurulu olup olmadığını doğrulamanın tek yolu bu — `isRecording`
    /// tek başına yeterli değil, çünkü asıl kaçak olan `monitor`, bayrak
    /// değil (bkz. I1: pencere kapanınca `isRecording` yanlışlıkla true
    /// kalmaz ama eski kodda `monitor` kalırdı).
    var isMonitoring: Bool { monitor != nil }

    func start(onCapture: @escaping (KeyCombo) -> Void) {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.stop(); return nil }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= KeyCombo.command }
            if event.modifierFlags.contains(.option) { modifiers |= KeyCombo.option }
            if event.modifierFlags.contains(.control) { modifiers |= KeyCombo.control }
            if event.modifierFlags.contains(.shift) { modifiers |= KeyCombo.shift }
            // Değiştiricisiz bir global kısayol her yerde normal yazmayı
            // yutar; boş basışları görmezden gelip izlemeye devam ediyoruz.
            guard modifiers != 0 else { return nil }
            self.stop()
            onCapture(KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            return nil // Tuşu yut: pencereye gitmesin, sistem beep çalmasın.
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

struct SettingsView: View {
    // `settingsStore` AppDelegate ile paylaşılan tek doğruluk kaynağı: bir
    // struct anlık görüntüsü (@State) olsaydı AppDelegate'in reddedilen bir
    // kısayolu geri alması hiç görüntüye yansımazdı (fix round 2). `settings`
    // aşağıdaki hesaplanan özellik, bu dosyanın geri kalanının
    // `settingsStore.settings` yerine hâlâ düz `settings` yazabilmesini
    // sağlıyor.
    @ObservedObject var settingsStore: SettingsStore
    let store: ClipStore
    let onChange: (StashCore.Settings) -> Void
    // Artık `@StateObject` DEĞİL: sahiplik `SettingsWindowController`'a taşındı
    // (bkz. I1) çünkü `.onDisappear` bu pencere kurulumunda (isReleasedWhenClosed
    // = false + AppDelegate'in kontrolcüyü tutması) pencere kapanınca hiç
    // tetiklenmiyor — SwiftUI view hiyerarşisi pencereyle birlikte hayatta
    // kalıyor. Kontrolcü artık pencerenin gerçekten yok olduğu anı (close VE
    // orderOut) yakalayıp `recorder.stop()` çağırıyor; view burada sadece
    // paylaşılan nesneyi gözlemliyor.
    @ObservedObject var recorder: ShortcutRecorder

    // `Settings` çıplak yazılınca SwiftUI.Settings (bir Scene tipi) ile
    // çakışıyor; StashCore.Settings modül önekiyle belirtiliyor.
    private var settings: StashCore.Settings {
        get { settingsStore.settings }
        nonmutating set { settingsStore.settings = newValue }
    }
    @State private var diskText = "calculating…"
    @State private var shelves: [Shelf] = []
    @State private var newShelfName = ""
    @State private var newBlockedBundleID = ""
    @State private var errorAlert: AlertMessage?
    // body içinde AXIsProcessTrusted() doğrudan okunsaydı SwiftUI'nin yeniden
    // çizilmesini tetikleyecek hiçbir şey olmazdı: kullanıcı "verilmedi"
    // görüp Sistem Ayarları'na gidip izni verip geri döndüğünde pencere hâlâ
    // "verilmedi" derdi — tam da uygulama çalışmaya başladığı anda bozukmuş
    // gibi görünürdü (fix round 1, bulgu 3). @State + uygulama etkinleşince
    // yeniden okumak bunu çözüyor.
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    // `LoginItem.isEnabled` `Settings`e değil `SMAppService`e sorulur (bkz.
    // Settings.swift'teki gerekçe); bu @State yalnızca SwiftUI'ye yeniden
    // çizim tetiklemesi için bir yer — doğruluk kaynağı hâlâ SMAppService,
    // her `refresh()`te oradan tazeleniyor.
    @State private var launchAtLoginEnabled = LoginItem.isEnabled

    struct AlertMessage: Identifiable { let id = UUID(); let title: String; let detail: String }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                        } catch {
                            // Kaynaktan kurulan, ad-hoc imzalı bir uygulamada
                            // SMAppService.register() sessizce başarısız
                            // olabilir (bkz. README "Açılışta başlatma").
                            // Anahtarı tıklanan değere göre bırakmak
                            // kullanıcıya yalan söyler; gerçek durumu aşağıda
                            // yeniden okuyoruz.
                            errorAlert = AlertMessage(title: "Couldn't set launch at login",
                                                      detail: "\(error)")
                        }
                        launchAtLoginEnabled = LoginItem.isEnabled
                    }))
                Text("Also appears in the Login Items list in System Settings, where it can be turned off too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sound") {
                Toggle("Play a sound on copy and paste", isOn: Binding(
                    get: { settings.soundsEnabled },
                    set: { newValue in
                        settings.soundsEnabled = newValue
                        onChange(settings)
                    }))
                Text("You'll hear two distinct short sounds: one when something new is saved from the clipboard, another when a card is pasted into the frontmost app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Screenshots") {
                // `onChange` (AppDelegate.openSettings kapanışı) senkron
                // çalışır: izin ilk kez BURADA istenir. Reddedilirse
                // `AppDelegate` `settingsStore.settings`i (ayrı bir `@State`
                // kopyası değil, bu view'ın da okuduğu AYNI paylaşılan nesne)
                // gerçek duruma geri döndürür — `get:` bir sonraki çizimde
                // bunu kendiliğinden görür, "Açılışta başlat"ın `@State`
                // anlık görüntüsünün aksine burada elle yeniden okumaya
                // gerek yok (görev kuralı: "@State anlık görüntüsü YOK").
                Toggle("Watch the screenshot folder", isOn: Binding(
                    get: { settings.screenshotWatchEnabled },
                    set: { newValue in
                        settings.screenshotWatchEnabled = newValue
                        onChange(settings)
                    }))
                Text("""
                    Shortcuts like ⌘⇧4 write the screenshot straight to disk, \
                    never touching the clipboard; with this on, Stash also \
                    watches that folder and adds new screenshots to your \
                    history as if they'd been copied. Only actual screenshots \
                    are picked up — other files in the folder are left alone. \
                    This reads a folder, not the clipboard, and needs folder \
                    access permission; if it's denied, the toggle turns \
                    itself back off.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcut") {
                HStack {
                    LabeledContent("Open the strip", value: settings.combo.displayString)
                    Spacer()
                    Button(recorder.isRecording ? "Listening…" : "Change") {
                        recorder.start { combo in
                            settings.combo = combo
                            onChange(settings)
                        }
                    }
                    .disabled(recorder.isRecording)
                }
                Text(recorder.isRecording
                     ? "Press the new combination. Esc to cancel."
                     : "Press “Change”, then press the new combination.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Paste filters") {
                ForEach(PasteFilter.allCases, id: \.self) { filter in
                    Toggle(title(for: filter), isOn: binding(for: filter))
                }
                Text("Filters apply in list order when pasting with ⌥↵.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Apps not to save from") {
                ForEach(Array(settings.blockedBundleIDs).sorted(), id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Remove") {
                            settings.blockedBundleIDs.remove(id); onChange(settings)
                        }
                    }
                }
                HStack {
                    TextField("Bundle ID, e.g. com.apple.Notes", text: $newBlockedBundleID)
                    Button("Add", action: addBlockedBundleID)
                }
                Text("Needs a reverse-DNS bundle ID (e.g. com.apple.Notes).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shelves") {
                ForEach(shelves) { shelf in
                    HStack {
                        Text(shelf.name)
                        Spacer()
                        Button("Rename") { renameShelf(shelf) }
                            .buttonStyle(.borderless)
                        Button("Delete", role: .destructive) { confirmDeleteShelf(shelf) }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("New shelf", text: $newShelfName)
                    Button("Add", action: createShelf)
                }
                Text("Deleting a shelf doesn't delete the cards on it — they just become shelfless.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("History") {
                // "Görseller VE önizlemeler": imagesByteSize() thumbs/'u da
                // sayıyor (bkz. ClipStore'daki gerekçe) — etiket yalnızca
                // "Görsellerin" derse gösterilen sayıyla uyuşmaz, kullanıcı
                // diskte gördüğünden daha büyük bir rakam görür.
                LabeledContent("Space used by images and previews", value: diskText)
                Button("Clear the last hour") {
                    try? store.deleteCreated(after: Date().addingTimeInterval(-3600))
                    refresh()
                }
                Button("Clear everything", role: .destructive) {
                    try? store.deleteAll(); refresh()
                }
                Text("Pinned cards survive clearing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permission") {
                LabeledContent("Accessibility",
                               value: accessibilityTrusted ? "granted" : "not granted")
                if !accessibilityTrusted {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Text("Without this permission, Stash won't paste — it'll only copy to the clipboard.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 680)
        .onAppear(perform: refresh)
        .onDisappear { recorder.stop() }
        // Kullanıcı Sistem Ayarları'ndan izin verip ya da Giriş Öğeleri'nden
        // açılışta başlatmayı kapatıp Stash'e geri döndüğünde uygulama
        // yeniden etkinleşir; bu bildirim ikisini de güncel tutmanın
        // zamanlayıcı kurmadan yeterli olan tek tetikleyicisi. Pencere açık
        // kalıp Stash'e odak geri gelmeden bu ikisi tazelenmezse, tazelenen
        // tek yol pencereyi kapatıp yeniden açmak olurdu — Ayarlar'ın var
        // olma amacının tam tersi (fix round 1, bulgu benzeri: bkz. yukarıki
        // accessibilityTrusted gerekçesi). launchAtLoginEnabled buraya aynı
        // gerekçeyle katıldı: `docs/manual-qa.md`, pencere kapatılıp
        // yeniden açılmadan Giriş Öğeleri'nden kapatmanın anahtara
        // yansımasını beklerken kod önceden sadece izin durumunu
        // güncelliyordu.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
            launchAtLoginEnabled = LoginItem.isEnabled
        }
        .alert(item: $errorAlert) { message in
            Alert(title: Text(message.title), message: Text(message.detail),
                 dismissButton: .default(Text("OK")))
        }
    }

    private func refresh() {
        refreshShelves()
        let bytes = (try? store.imagesByteSize()) ?? 0
        diskText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        accessibilityTrusted = AXIsProcessTrusted()
        launchAtLoginEnabled = LoginItem.isEnabled
    }

    private func refreshShelves() {
        shelves = (try? store.shelves()) ?? []
    }

    /// `onChange(settings)`i Kaldır düğmesiyle AYNI şekilde, tıklamayla eşzamanlı
    /// çağırıyoruz (pencere kapanana kadar biriktirmiyoruz): AppDelegate.openSettings
    /// bu kapanışta `capture?.updatePolicy(...)`i çalıştırıyor, o yüzden yeni
    /// engellenen uygulama çalışan yakalamaya yeniden başlatma gerekmeden hemen
    /// ulaşıyor — kaldırmanın bugün zaten yaptığı canlı güncelleme yoluyla.
    private func addBlockedBundleID() {
        switch validateBlockedBundleID(newBlockedBundleID, existing: settings.blockedBundleIDs) {
        case .valid(let id):
            settings.blockedBundleIDs.insert(id)
            onChange(settings)
            newBlockedBundleID = ""
        case .invalid(let reason):
            // Raf adı boş bırakıldığında createShelf()'in yaptığı gibi:
            // sessizce hiçbir şey olmamış gibi davranmak yerine görünür bir
            // hata, kullanıcıyı neyin ters gittiği konusunda karanlıkta
            // bırakmaz.
            errorAlert = AlertMessage(title: "Couldn't add app", detail: reason)
        }
    }

    private func createShelf() {
        do {
            _ = try store.createShelf(name: newShelfName)
            newShelfName = ""
            refreshShelves()
        } catch {
            // Boş ad StoreError ile düşer; sessizce hiçbir şey olmamış gibi
            // davranmak kullanıcıyı neyin ters gittiği konusunda karanlıkta
            // bırakır — bkz. AppDelegate.createShelfAndMoveSelected'daki
            // aynı gerekçe.
            errorAlert = AlertMessage(title: "Couldn't create shelf", detail: "\(error)")
        }
    }

    private func renameShelf(_ shelf: Shelf) {
        let alert = NSAlert()
        alert.messageText = "Rename shelf"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = shelf.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.renameShelf(shelf.id, to: field.stringValue)
            refreshShelves()
        } catch {
            errorAlert = AlertMessage(title: "Couldn't rename", detail: "\(error)")
        }
    }

    private func confirmDeleteShelf(_ shelf: Shelf) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(shelf.name)”?"
        alert.informativeText = "The cards on it aren't deleted — they just become shelfless."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.deleteShelf(shelf.id)
            refreshShelves()
        } catch {
            errorAlert = AlertMessage(title: "Couldn't delete", detail: "\(error)")
        }
    }

    private func title(for filter: PasteFilter) -> String {
        switch filter {
        case .plainText: return "Paste as plain text"
        case .collapseWhitespace: return "Collapse extra whitespace"
        case .straightenQuotes: return "Straighten smart quotes"
        }
    }

    private func binding(for filter: PasteFilter) -> Binding<Bool> {
        Binding(
            get: { settings.activeFilters.contains(filter) },
            set: { isOn in
                if isOn { settings.activeFilters.append(filter) }
                else { settings.activeFilters.removeAll { $0 == filter } }
                onChange(settings)
            })
    }
}
