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
    @State private var diskText = "hesaplanıyor…"
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
            Section("Genel") {
                Toggle("Açılışta başlat", isOn: Binding(
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
                            errorAlert = AlertMessage(title: "Açılışta başlatma ayarlanamadı",
                                                      detail: "\(error)")
                        }
                        launchAtLoginEnabled = LoginItem.isEnabled
                    }))
                Text("Sistem Ayarları'ndaki Giriş Öğeleri listesinde de görünür ve oradan kapatılabilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ses") {
                Toggle("Kopyalama ve yapıştırmada ses çal", isOn: Binding(
                    get: { settings.soundsEnabled },
                    set: { newValue in
                        settings.soundsEnabled = newValue
                        onChange(settings)
                    }))
                Text("Panodan yeni bir şey kaydedilince ve bir kart öndeki uygulamaya yapıştırılınca, birbirinden farklı iki kısa ses duyulur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ekran görüntüleri") {
                // `onChange` (AppDelegate.openSettings kapanışı) senkron
                // çalışır: izin ilk kez BURADA istenir. Reddedilirse
                // `AppDelegate` `settingsStore.settings`i (ayrı bir `@State`
                // kopyası değil, bu view'ın da okuduğu AYNI paylaşılan nesne)
                // gerçek duruma geri döndürür — `get:` bir sonraki çizimde
                // bunu kendiliğinden görür, "Açılışta başlat"ın `@State`
                // anlık görüntüsünün aksine burada elle yeniden okumaya
                // gerek yok (görev kuralı: "@State anlık görüntüsü YOK").
                Toggle("Ekran görüntüsü klasörünü izle", isOn: Binding(
                    get: { settings.screenshotWatchEnabled },
                    set: { newValue in
                        settings.screenshotWatchEnabled = newValue
                        onChange(settings)
                    }))
                Text("""
                    ⌘⇧4 gibi kısayollar ekran görüntüsünü panoya hiç \
                    uğratmadan doğrudan diske yazar; bu anahtar açıkken Stash \
                    o klasörü de izleyip yeni ekran görüntülerini panodan \
                    kopyalanmış gibi geçmişe ekler. Yalnızca gerçek ekran \
                    görüntüleri alınır, klasördeki başka dosyalara \
                    dokunulmaz. Klasöre erişim izni gerekir; izin \
                    reddedilirse anahtar kendiliğinden kapanır.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kısayol") {
                HStack {
                    LabeledContent("Şeridi aç", value: settings.combo.displayString)
                    Spacer()
                    Button(recorder.isRecording ? "Dinleniyor…" : "Değiştir") {
                        recorder.start { combo in
                            settings.combo = combo
                            onChange(settings)
                        }
                    }
                    .disabled(recorder.isRecording)
                }
                Text(recorder.isRecording
                     ? "Yeni kombinasyona bas. Vazgeçmek için Esc."
                     : "Değiştirmek için “Değiştir”e bas, sonra yeni kombinasyona bas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Yapıştırma filtreleri") {
                ForEach(PasteFilter.allCases, id: \.self) { filter in
                    Toggle(title(for: filter), isOn: binding(for: filter))
                }
                Text("Filtreler ⌥↵ ile yapıştırırken listedeki sırayla uygulanır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kaydedilmeyecek uygulamalar") {
                ForEach(Array(settings.blockedBundleIDs).sorted(), id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Kaldır") {
                            settings.blockedBundleIDs.remove(id); onChange(settings)
                        }
                    }
                }
                HStack {
                    TextField("Paket kimliği, ör. com.apple.Notes", text: $newBlockedBundleID)
                    Button("Ekle", action: addBlockedBundleID)
                }
                Text("Ters etki alanı biçiminde bir paket kimliği gerekir (ör. com.apple.Notes).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Raflar") {
                ForEach(shelves) { shelf in
                    HStack {
                        Text(shelf.name)
                        Spacer()
                        Button("Yeniden adlandır") { renameShelf(shelf) }
                            .buttonStyle(.borderless)
                        Button("Sil", role: .destructive) { confirmDeleteShelf(shelf) }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Yeni raf", text: $newShelfName)
                    Button("Ekle", action: createShelf)
                }
                Text("Bir rafı silmek içindeki kartları silmez, kartlar sadece rafsız kalır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Geçmiş") {
                // "Görseller VE önizlemeler": imagesByteSize() thumbs/'u da
                // sayıyor (bkz. ClipStore'daki gerekçe) — etiket yalnızca
                // "Görsellerin" derse gösterilen sayıyla uyuşmaz, kullanıcı
                // diskte gördüğünden daha büyük bir rakam görür.
                LabeledContent("Görsel ve önizlemelerin kapladığı alan", value: diskText)
                Button("Son bir saati temizle") {
                    try? store.deleteCreated(after: Date().addingTimeInterval(-3600))
                    refresh()
                }
                Button("Tümünü temizle", role: .destructive) {
                    try? store.deleteAll(); refresh()
                }
                Text("Sabitlediğin kartlar temizlemelerden etkilenmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("İzin") {
                LabeledContent("Erişilebilirlik",
                               value: accessibilityTrusted ? "verildi" : "verilmedi")
                if !accessibilityTrusted {
                    Button("Sistem Ayarları'nı aç") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Text("İzin olmadan Stash yapıştırmaz, sadece panoya kopyalar.")
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
                 dismissButton: .default(Text("Tamam")))
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
            errorAlert = AlertMessage(title: "Uygulama eklenemedi", detail: reason)
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
            errorAlert = AlertMessage(title: "Raf oluşturulamadı", detail: "\(error)")
        }
    }

    private func renameShelf(_ shelf: Shelf) {
        let alert = NSAlert()
        alert.messageText = "Rafı yeniden adlandır"
        alert.addButton(withTitle: "Kaydet")
        alert.addButton(withTitle: "Vazgeç")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = shelf.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.renameShelf(shelf.id, to: field.stringValue)
            refreshShelves()
        } catch {
            errorAlert = AlertMessage(title: "Yeniden adlandırılamadı", detail: "\(error)")
        }
    }

    private func confirmDeleteShelf(_ shelf: Shelf) {
        let alert = NSAlert()
        alert.messageText = "“\(shelf.name)” rafını sil?"
        alert.informativeText = "Raftaki kartlar silinmez, sadece rafsız kalır."
        alert.addButton(withTitle: "Sil")
        alert.addButton(withTitle: "Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.deleteShelf(shelf.id)
            refreshShelves()
        } catch {
            errorAlert = AlertMessage(title: "Silinemedi", detail: "\(error)")
        }
    }

    private func title(for filter: PasteFilter) -> String {
        switch filter {
        case .plainText: return "Düz metin olarak yapıştır"
        case .collapseWhitespace: return "Fazla boşlukları temizle"
        case .straightenQuotes: return "Akıllı tırnakları düzelt"
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
