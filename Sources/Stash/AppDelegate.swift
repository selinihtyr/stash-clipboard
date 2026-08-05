import AppKit
import HotKey
import PasteboardKit
import PasteEngine
import StashCore
import Store
import SwiftUI
import Updater

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    // Menü sadece launch'ta bir kez kuruluyor; kullanıcı Ayarlar'dan
    // kombinasyonu değiştirince bu öğeyi elde tutmadan güncelleyecek bir yer
    // yok — bkz. openSettings içindeki applyShortcut çağrısı.
    private var openMenuItem: NSMenuItem?
    // Aynı gerekçe: başlığı ("Update to 0.2.0…") ve etkinliği durum
    // değiştikçe güncelleniyor, bkz. `refreshUpdateMenuItem`.
    private var updateMenuItem: NSMenuItem?
    private var updateController: UpdateController?
    private var panel: StripPanel?
    private var hotKey = HotKeyCenter()
    // Kayıtlı kombinasyonun sahibi. `settingsStore` bu iş için KULLANILAMAZ:
    // ayarlar penceresi mağazayı `onChange`den önce güncelliyor, bkz.
    // HotKeyCoordinator'daki gerekçe. `lazy` çünkü başlangıç değeri
    // `settingsStore`u okuyor; ilk erişim AÇILIŞTA (aşağıdaki
    // `registerCurrent()`) olmak ZORUNDA — ilk kez ayarlardan gelen bir
    // değişiklikte kurulsaydı başlangıç değeri olarak mağazadaki güncellenmiş
    // (yeni) kombinasyonu okur ve düzeltilen hata geri gelirdi.
    private lazy var hotKeyCoordinator = HotKeyCoordinator(
        currentCombo: settingsStore.settings.combo,
        register: { [weak self] combo in
            guard let self else { return .failure(.alreadyTaken) }
            return self.attemptRegister(combo)
        })
    private var coordinator: CaptureCoordinator?
    private var model: StripModel?
    // `Settings` çıplak yazılınca bu dosya SwiftUI'yi de import ettiği için
    // SwiftUI.Settings (bir Scene tipi) ile çakışıyor; bugüne kadar yalnızca
    // SwiftUI.Settings'in `load(from:)` üyesi olmaması sayesinde doğru
    // çözülüyordu — StashCore.Settings modül önekiyle bunu derleyiciye
    // bırakmıyoruz (fix round 1, bulgu 4).
    //
    // `settings` artık `SettingsStore` içinde: ayarlar penceresiyle paylaşılan
    // tek doğruluk kaynağı bu, aksi halde pencere reddedilen bir kısayolun
    // geri alındığını hiç görmezdi (fix round 2, bkz. SettingsStore.swift).
    private let settingsStore = SettingsStore(.load())
    private var store: ClipStore?
    private var capture: ClipCapture?
    private var settingsController: SettingsWindowController?
    // Opt-in, varsayılan kapalı (görev kuralı 8) — `applicationDidFinishLaunching`
    // yalnızca `settingsStore.settings.screenshotWatchEnabled` açıksa `start()`
    // çağırır. Nesne yine de her zaman kuruluyor: kapalıyken bile Ayarlar'dan
    // sonradan açılabilmesi gerekiyor (bkz. `reconcileScreenshotWatcher`).
    private var screenshotWatcher: ScreenshotWatcher?
    // `lazy`: varsayılan değer `self.settingsStore`a bakıyor, bir stored
    // property initializer'ı `self`e henüz erişemez — bkz. Swift'in
    // property initialization sırası. `settingsStore` yukarıda zaten
    // `self`e ihtiyaç duymadan kendi kendine kuruluyor, bu yüzden `lazy`
    // ilk erişimde onu güvenle okuyabiliyor.
    private lazy var soundFeedback = SoundFeedbackController(
        settingsStore: settingsStore, player: BundledSoundPlayer())

    /// Güncelleme kontrolünün baktığı yer ve kabul ettiği imza. Depo herkese
    /// açık olduğu için bu satırlar da denetlenebilir: Stash'in ağda konuştuğu
    /// tek adres ve indirdiği bir binary'yi çalıştırmasının tek şartı burada.
    private static let updateOwner = "selinihtyr"
    private static let updateRepo = "stash-clipboard"
    private static let updateAssetName = "Stash.zip"
    private static let updateSignaturePolicy = CodeSignaturePolicy(
        teamIdentifier: "HN964HX2UA", bundleIdentifier: "social.selin.stash")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Her şeyden önce: çalışan başka bir kopya varsa devral. Kısayolu
        // kaydetmeden önce olmak ZORUNDA — iki kopya aynı kombinasyonu
        // kaydettiğinde ölmekte olan eski kopya sistem yuvasını boşaltıyor ve
        // yeni kopyanın kaydı hiçbir hata vermeden ölü kalıyor
        // (bkz. takeOverFromOtherInstances).
        takeOverFromOtherInstances()
        setUpUpdateController()
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
            self.store = store
            // Bu, uygulamanın çökmesine ya da başlamayı reddetmesine yol
            // açan fatal bir durum DEĞİL: store zaten boş ve sağlıklı bir
            // veritabanıyla açıldı, kullanıcıya sadece ne olduğunu
            // söylüyoruz — presentFatal'daki gibi terminate etmiyoruz.
            if let backup = store.recoveredFromCorruption {
                let alert = NSAlert()
                alert.messageText = "Couldn't read clipboard history"
                alert.informativeText = """
                    Stash opened with an empty history. The old file wasn't \
                    deleted — it was copied next to it: \(backup.lastPathComponent)
                    """
                alert.runModal()
            }
            let engine = PasteEngine(pasteboard: SystemPasteboardWriter(),
                                     keystrokes: SystemKeystrokeSender())
            let model = StripModel(store: store, engine: engine, settings: settingsStore.settings)
            self.model = model

            // blockedBundleIDs burada ClipCapture'a ulaşmazsa uygulamanın
            // merkezi mahremiyet sözü (şifre yöneticilerinden asla kopya
            // kaydetme) hiçbir yerde uygulanmamış olur — bkz. Task 8 incelemesi.
            // `capture`'ı da tutuyoruz: ayarlar penceresinde kara liste
            // değişince updatePolicy(_:) ile canlı güncellenmesi gerekiyor,
            // yoksa çalışan yakalama kullanıcının az önce engellediği
            // uygulamadan kopyalamayı sürdürür (bkz. Task 13 için taşınan bulgu).
            let capture = ClipCapture(pasteboard: SystemPasteboard(),
                                      policy: CapturePolicy(blockedBundleIDs: settingsStore.settings.blockedBundleIDs))
            self.capture = capture
            // PasteEngine ve ClipCapture ayrı modüllerde, birbirini hiç
            // bilmiyor (bkz. PasteEngine.onWrite gerekçesi); AppDelegate
            // ikisini birbirine bağlayan tek yer. Bağlantı olmadan Stash
            // kendi yaptığı her yapıştırmayı 0,5 saniye sonra normal bir
            // kullanıcı kopyalaması sanıp geri yakalar — kartın sourceName'i
            // yapıştırılan uygulamaya döner, filtreli bir yapıştırma da
            // (metni değiştirdiği için) ayrı bir satır olarak ikilenir (I2).
            engine.onWrite = { [weak capture] changeCount in
                capture?.suppressChangeCount(changeCount)
            }
            let coordinator = CaptureCoordinator(store: store, capture: capture)
            coordinator.onCapture = { [weak self] in try? self?.model?.reload() }
            // `onCaptureSound`, açılıştaki ilk yakalamada ve atlanan
            // (engellenen uygulama, concealed/transient tip) yakalamalarda
            // hiç tetiklenmiyor — o ayrım `CaptureCoordinator` seviyesinde
            // zaten yapılıyor (bkz. gerekçesi). Burada sadece anahtarı
            // okuyup sesi çalıyoruz.
            coordinator.onCaptureSound = { [weak self] in self?.soundFeedback.captured() }
            coordinator.onError = { [weak self] _ in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle",
                    accessibilityDescription: "Stash: disk error")
            }
            coordinator.start()
            self.coordinator = coordinator

            // Görev "Why": ⌘⇧4 pano'ya hiç uğramadan doğrudan diske yazar,
            // `capture` bunu asla göremez — bu ayrı izleyici o boşluğu
            // kapatıyor. Nesne her zaman kuruluyor (kapalıyken bile Ayarlar
            // penceresi sonradan `start()` çağırabilsin diye), ama yalnızca
            // ayar açıksa hemen başlatılıyor.
            let watcher = ScreenshotWatcher(store: store)
            watcher.onIngest = { [weak self] in try? self?.model?.reload() }
            watcher.onIngestSound = { [weak self] in self?.soundFeedback.captured() }
            watcher.onStatusChange = { [weak self] status in
                self?.handleScreenshotWatchStatusChange(status)
            }
            self.screenshotWatcher = watcher
            if settingsStore.settings.screenshotWatchEnabled {
                watcher.start()
            }
        } catch {
            presentFatal(error)
            return
        }

        // İlk açılışta geri dönülecek "önceki çalışan kombinasyon" diye bir
        // şey yok; başarısız olursa tek yapılabilecek kullanıcıyı bilgilendirmek.
        // Ayarlar penceresinden gelen değişiklikler ayrı bir yoldan
        // (reconcileHotKeyChange) geçer ve geri yükleme dener — bkz. openSettings.
        if case .failure(let error) = hotKeyCoordinator.registerCurrent() {
            presentHotKeyAlert(for: error, combo: hotKeyCoordinator.currentCombo)
            return
        }
        refreshHotKeyAfterLaunch()
    }

    /// Açılıştan kısa süre sonra kaydı bir kez tazeler.
    ///
    /// Kayıt "başarılı" dönüp de tuşun hiç gelmediği bir durum var: açılış
    /// sırasında ölmekte olan başka bir süreç (eski Stash kopyası ya da aynı
    /// kombinasyonu tutan başka bir uygulama) sistemdeki yuvayı bizden SONRA
    /// bırakırsa, elimizdeki `EventHotKeyRef` geçerli görünür ama olay
    /// akmaz. Ölçüldü: temiz açılışların ~5'te 1'i böyle çıkıyordu, ve
    /// kullanıcı bunu "Stash bozuldu" diye yaşıyor.
    ///
    /// `takeOverFromOtherInstances` bilinen sebebi ortadan kaldırıyor; bu
    /// tazeleme, bilmediğimiz sebepler için ikinci savunma. Ucuz: iki saniye
    /// sonra tek bir unregister/register çifti, kullanıcıya görünmeyen.
    private func refreshHotKeyAfterLaunch() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard case .failure = hotKeyCoordinator.registerCurrent() else { return }
            // Tazeleme başarısız olduysa `register` önce unregister ettiği için
            // artık HİÇ kaydımız yok — sessizce geçmek kullanıcıyı kısayolsuz
            // bırakırdı. Bir kez daha deniyoruz, o da olmazsa söylüyoruz.
            if case .failure(let error) = hotKeyCoordinator.registerCurrent() {
                presentHotKeyAlert(for: error, combo: hotKeyCoordinator.currentCombo)
            }
        }
    }

    /// Tek bir kombinasyonu kaydetmeyi dener. NSAlert göstermez — çağıran
    /// taraf (launch ya da ayarlar değişikliği) sonucu farklı yorumluyor:
    /// launch'ta geri dönülecek bir şey yok, ayarlarda ise
    /// `reconcileHotKeyChange` başarısızlığı önceki kombinasyona dönmek için
    /// kullanıyor. Alanı burada karıştırmamak `reconcileHotKeyChange`'in
    /// Carbon'a ya da bir uyarı penceresine dokunmadan test edilebilmesini
    /// sağlıyor (fix round 1, bulgu 1).
    private func attemptRegister(_ combo: KeyCombo) -> Result<Void, HotKeyError> {
        do {
            try hotKey.register(combo) { [weak self] in self?.toggleStrip() }
            return .success(())
        } catch let error as HotKeyError {
            return .failure(error)
        } catch {
            // hotKey.register yalnızca HotKeyError fırlatır; bu dal pratikte
            // hiç çalışmaz ama derleyici genel bir catch istiyor.
            return .failure(.alreadyTaken)
        }
    }

    private func presentHotKeyAlert(for error: HotKeyError, combo: KeyCombo) {
        let alert = NSAlert()
        alert.messageText = "Couldn't register shortcut"
        switch error {
        case .alreadyTaken:
            // Gerçek çakışma: kullanıcı başka bir kısayol seçebilir.
            alert.informativeText = """
                \(combo.displayString) is already in use by another app. \
                Pick a different combination from Settings.
                """
        case .handlerInstallFailed(let status):
            // Çakışma değil, dahili bir kurulum hatası: kullanıcıyı başka bir
            // kombinasyon denemeye yönlendirmek yanlış teşhis olur — sebep
            // sistemde, kısayolda değil.
            alert.informativeText = """
                The system event handler couldn't be installed (status \(status)). \
                This isn't a shortcut conflict — it's an internal error. Try \
                restarting the app.
                """
        }
        alert.runModal()
    }

    /// Sürüm bilgisi Info.plist'ten okunuyor: ikinci bir yerde sabit yazsaydık
    /// `scripts/release.sh` birini güncelleyip diğerini unutabilir, uygulama da
    /// zaten kurulu olan sürümü "yeni" diye önerebilirdi.
    private func setUpUpdateController() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let raw, let version = AppVersion(raw) else { return }
        let controller = UpdateController(
            client: GitHubReleaseClient(owner: Self.updateOwner, repo: Self.updateRepo,
                                        userAgent: "Stash/\(raw) (+https://github.com/"
                                            + "\(Self.updateOwner)/\(Self.updateRepo))"),
            policy: Self.updateSignaturePolicy,
            assetName: Self.updateAssetName,
            currentVersion: version)
        controller.automaticChecksEnabled = { [weak self] in
            self?.settingsStore.settings.automaticUpdateChecks ?? false
        }
        controller.onStateChange = { [weak self] in self?.refreshUpdateMenuItem() }
        updateController = controller
        controller.startAutomaticChecks()
    }

    private func refreshUpdateMenuItem() {
        guard let item = updateMenuItem, let controller = updateController else { return }
        item.title = controller.menuTitle
        item.isEnabled = controller.menuItemEnabled
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Güncelleme öğesi indirme sürerken kapalı görünmeli. AppKit'in
        // otomatik etkinleştirmesi açık kalsaydı, hedefi seçiciye yanıt
        // verdiği için öğeyi her zaman etkin çizerdi ve `isEnabled = false`
        // hiçbir işe yaramazdı.
        menu.autoenablesItems = false
        let openItem = menu.addItem(withTitle: "Open Stash", action: #selector(toggleStrip), keyEquivalent: "")
        openItem.target = self
        applyShortcut(settingsStore.settings.combo, to: openItem)
        openMenuItem = openItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        // Güncelleme öğesinin BAŞLIĞI duruma göre değişiyor ("Check for
        // Updates…" → "Update to 0.2.0…"): arka planda bulunan bir güncellemeyi
        // kullanıcıya modal bir pencereyle dayatmak yerine menüde bekletiyoruz.
        let updateItem = menu.addItem(withTitle: "Check for Updates…",
                                      action: #selector(UpdateController.checkNow),
                                      keyEquivalent: "")
        updateItem.target = updateController
        updateMenuItem = updateItem
        refreshUpdateMenuItem()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Kısayolu menü öğesine native biçimde (sağa hizalı tuş kombinasyonu)
    /// yazar. `combo.keyEquivalent` nil dönerse (bilinmeyen bir tuş kodu)
    /// hiçbir kısayol göstermiyoruz — yanlış bir tuş göstermek, hiç
    /// göstermemekten daha kötü (bkz. KeyCombo.keyEquivalent gerekçesi).
    private func applyShortcut(_ combo: KeyCombo, to item: NSMenuItem) {
        if let character = combo.keyEquivalent {
            item.keyEquivalent = character
            item.keyEquivalentModifierMask = combo.eventModifierFlags
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }

    /// Pencereyi tek bir kontrolcü üzerinden tutuyoruz: her açılışta yeni bir
    /// tane kurmak eskisinin kapatılmadan arkada birikmesine (ve kullanıcının
    /// aynı anda birden çok ayarlar penceresi görmesine) yol açardı.
    @objc func openSettings() {
        guard let store = self.store else { return }
        let controller = settingsController ?? SettingsWindowController(
            settingsStore: settingsStore, store: store) { [weak self] updated in
                guard let self else { return }

                // Karşılaştırma GERÇEKTEN KAYITLI olan kombinasyona karşı
                // yapılıyor, `settingsStore.settings.combo`ya karşı değil: bu
                // geri çağırım çalıştığında ayarlar penceresi paylaşılan
                // mağazayı çoktan yeni kombinasyonla güncellemiş oluyor, o
                // yüzden mağazadan okumak "değişmedi" yanılgısına düşerdi
                // (bkz. HotKeyCoordinator).
                //
                // Kombinasyon değişmediyse register hiç çağrılmaz —
                // filtre/kara liste/raf değişikliklerinde gereksiz bir
                // unregister/register döngüsüne girmemek için (fix round 1,
                // bulgu 1'in üçüncü parçası). Değiştiyse önce yeniyi dener,
                // olmazsa kullanıcıyı kısayolsuz bırakmamak için eskiye döner —
                // ve başarısız kombinasyon diske hiç yazılmaz.
                let outcome = self.hotKeyCoordinator.apply(updated.combo)
                var finalSettings = updated
                switch outcome {
                case .applied(let combo):
                    finalSettings.combo = combo
                case .reverted(let combo, let reason):
                    finalSettings.combo = combo
                    self.presentHotKeyAlert(for: reason, combo: updated.combo)
                case .revertFailed(let attempted, let previous, let reason):
                    // Eskisi de kaydolamadı: kullanıcının şu an hiçbir çalışan
                    // kısayolu yok. Bunu üstünü örtmeden, açıkça söylüyoruz.
                    finalSettings.combo = previous
                    self.presentHotKeyAlert(for: reason, combo: previous)
                    let alert = NSAlert()
                    alert.messageText = "Couldn't restore shortcut"
                    alert.informativeText = """
                        Neither \(attempted.displayString) nor the previous \(previous.displayString) \
                        could be registered. Stash currently has no working shortcut; \
                        try a different combination from Settings.
                        """
                    alert.runModal()
                }

                // settingsStore.settings'i (bir struct kopyası değil, ayarlar
                // penceresiyle paylaşılan gözlemlenebilir nesneyi) güncelliyoruz:
                // pencere hâlâ açıksa ya da daha sonra tekrar açılırsa, geri
                // alınan kombinasyonu (varsa) otomatik gösterir — fix round 2'nin
                // tek bulgusu buydu.
                self.settingsStore.settings = finalSettings
                // Menü launch'ta bir kez kuruldu; kombinasyon değiştiyse (ya
                // da başarısız olup eskiye döndüyse) öğeyi burada elle
                // güncellemezsek menü eski kısayolu göstermeyi sürdürür.
                if let item = self.openMenuItem {
                    self.applyShortcut(finalSettings.combo, to: item)
                }
                // Başarısız bir kombinasyonu diske yazmıyoruz: finalSettings.combo
                // her zaman gerçekten kaydolmuş bir değer (yeni ya da eski) —
                // aksi halde sonraki açılış aynı hatayı sessizce tekrar ederdi.
                finalSettings.save()

                // Kara liste değiştiyse çalışan yakalama bunu görmezse ayarlar
                // penceresi yalan söylemiş olur — kullanıcı bir uygulamayı
                // engelledi sanır, yakalama eski listeyle sürer (bkz. Task 8
                // incelemesinden Task 13'e taşınan bulgu).
                self.capture?.updatePolicy(CapturePolicy(blockedBundleIDs: finalSettings.blockedBundleIDs))
                self.model?.settings = finalSettings

                // Anahtar burada AÇIK/KAPALI değişmiş olabilir — izleyiciyi
                // gerçek isteğe göre başlat/durdur. `start()` senkron:
                // izin daha önce hiç sorulmadıysa BURADA (Ayarlar
                // penceresindeki tıklamayla aynı anda) bir TCC istemi
                // gösterir, tıpkı `LoginItem.setEnabled`ın yaptığı gibi.
                self.reconcileScreenshotWatcher(desired: finalSettings.screenshotWatchEnabled)
            }
        settingsController = controller
        controller.present()
    }

    /// Ayarlar penceresinden gelen isteği izleyicinin gerçek durumuna
    /// uygular. `start()`ın kendisi `stop()`u önce çağırdığı için burada
    /// zaten çalışıyorken tekrar `start()` çağırmak (ör. kısayol değişikliği
    /// gibi ilgisiz bir ayar güncellemesi bu closure'ı her tetiklediğinde)
    /// zararsız ama gereksiz olurdu — yalnızca durum gerçekten "izlemiyor"sa
    /// (kapalı/klasör-yok/izin-reddedildi) yeniden deniyoruz.
    private func reconcileScreenshotWatcher(desired: Bool) {
        guard let watcher = screenshotWatcher else { return }
        if desired {
            if case .watching = watcher.status {} else { watcher.start() }
        } else {
            watcher.stop()
        }
    }

    /// `ScreenshotWatcher.onStatusChange`e bağlanır. Yalnızca izin reddi
    /// ilgimizi çekiyor: anahtar zaten kapalıysa (kullanıcı kendi kapattı)
    /// ya da klasör geçici olarak yok (harici disk bağlı değil vb.) burada
    /// yapılacak bir şey yok — `folderMissing` sessizce beklemeye devam
    /// eder, klasör geri gelirse `tick()` kendiliğinden toparlanır.
    ///
    /// Görev kuralı 7: izin reddedilirse özellik sessizce çalışmıyormuş gibi
    /// görünmemeli. `LoginItem.setEnabled` başarısızlığının Ayarlar'a
    /// yansıtılma şekliyle AYNI desen — anahtarı gerçek duruma (kapalı)
    /// geri döndürüp diske yazıyoruz, sonra görünür bir uyarı gösteriyoruz.
    private func handleScreenshotWatchStatusChange(_ status: ScreenshotWatchStatus) {
        guard status == .permissionDenied, settingsStore.settings.screenshotWatchEnabled else { return }
        var updated = settingsStore.settings
        updated.screenshotWatchEnabled = false
        settingsStore.settings = updated
        updated.save()
        let alert = NSAlert()
        alert.messageText = "Couldn't access the screenshot folder"
        alert.informativeText = """
            Stash needs permission to read the screenshot folder. Grant it in \
            System Settings, then turn the toggle back on.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        }
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
                self.attemptPaste(model: model, applyingFilters: filtered)
            case .pasteIndex(let index):
                // Görünürden az kart varken ⌘N basılırsa hiçbir şey olmamalı;
                // aksi halde eski seçim sessizce yapıştırılır — yanlış kartı
                // panoya göndermek boş yapmaktan daha kötü.
                guard model.visible.indices.contains(index) else { break }
                model.select(index: index)
                self.attemptPaste(model: model, applyingFilters: false)
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

    /// Şeridi kapatıp klavye odağını önce yapıştırılacak uygulamaya geri
    /// veren, ANCAK BUNDAN SONRA sentetik ⌘V'nin gönderilmesine izin veren
    /// tek yer. `StripModel.attemptPaste`in `restoreFocus` parametresi tam
    /// olarak bunun için var (bkz. `PasteEngine.FocusRestoration`): panel
    /// hâlâ key window iken tuş gönderilirse tuş panelin kendisine düşer,
    /// öndeki uygulamaya asla ulaşmaz — kritik hatanın kendisi buydu.
    ///
    /// `panel?.dismiss()` senkron (orderOut çağırıyor) ama pencere sunucusunun
    /// bir sonraki uygulamayı GERÇEKTEN key window yapması aynı run loop
    /// turunda garanti değil; bu yüzden `proceed()`i bir sonraki turda
    /// çağırıyoruz. Bu kancayı hiç sağlamamak (ya da `proceed()`i hemen,
    /// senkron çağırmak) eski hatayı birebir geri getirir — API bunu
    /// atlamayı imkansız kılıyor ama YANLIŞ implemente etmeyi engellemiyor,
    /// bu yüzden bu tek nokta özenle doğru tutulmalı.
    private func attemptPaste(model: StripModel, applyingFilters: Bool) {
        model.attemptPaste(applyingFilters: applyingFilters, restoreFocus: { [weak self] proceed in
            self?.panel?.dismiss()
            // `proceed`i aynı turda değil, bir sonraki main-actor turunda
            // çağırıyoruz: dismiss() (orderOut) senkron dönse de pencere
            // sunucusunun bir sonraki uygulamayı GERÇEKTEN key window yapması
            // aynı turda garanti değil — sentetik ⌘V'yi aynı turda göndermek
            // asıl hatanın kendisiydi. `Task { @MainActor in }`, hem `self`
            // hem `proceed` zaten bu @MainActor sınıfın içinde yaşadığı için
            // GCD'nin `@Sendable` şartına takılmadan aynı erteleme etkisini
            // veriyor.
            Task { @MainActor in proceed() }
        }, completion: { [weak self] attempt in
            self?.handle(attempt)
        })
    }

    /// `attemptPaste`in üç sonucunu yorumlar (I3): hiçbir kart seçili
    /// değilse (boş şerit) sessizce hiçbir şey yapmaz — panel açık kalır,
    /// zaten boş durumda başlıktaki "Henüz bir şey kopyalamadın." sebebini
    /// söylüyor, ayrı bir uyarıya gerek yok. Görünür bir kart seçiliyken
    /// yapıştıracak içeriği kalmamışsa (ör. budanmış bir görsel) bunu artık
    /// ayırt edip görünür bir uyarı gösteriyor — eskiden ikisi de aynı
    /// sessizliğe düşüyordu, kullanıcı görünen bir kartın üstünde ↵'e basıp
    /// hiçbir şey olmadığını görüyordu.
    private func handle(_ attempt: StripModel.PasteAttempt) {
        switch attempt {
        case .nothingSelected:
            return
        case .nothingToPaste:
            presentNothingToPasteAlert()
        case .outcome(let outcome):
            finishPaste(outcome)
        }
    }

    /// `attemptPaste`, `.nothingToPaste`i klibin `kind`'ına BAKMADAN, yapıştırma
    /// nil dönen HER klip için üretir (bkz. StripModel.PasteAttempt üstündeki
    /// gerekçe) — ama bu metin "Görseli" diyerek her zaman görsel varsayıyordu.
    /// Bugün bu yol pratikte yalnızca budanmış bir görselle tetikleniyor
    /// (metin/bağlantı/dosya kliplerinin `text`i neredeyse hiç nil olmuyor),
    /// ama kod yolu türden bağımsız olduğu sürece metin de öyle olmalı —
    /// aksi halde "her zaman görsel diyor" iddiası bir gün yalan çıkar.
    private func presentNothingToPasteAlert() {
        let alert = NSAlert()
        alert.messageText = "Nothing to paste on this card"
        alert.informativeText = "The content is no longer available. Delete it, or copy it again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Panel burada DEĞİL, `attemptPaste(model:applyingFilters:)` içindeki
    /// `restoreFocus` kancasında kapanıyor — yani `deliver()` (dolayısıyla bu
    /// fonksiyonun çağrılması) her zaman panel zaten kapandıktan SONRA
    /// gerçekleşiyor. Burada ikinci bir `dismiss()` çağırmak zararsız olurdu
    /// ama yanıltıcı olurdu: sırayı garanti eden yerin burası olduğu izlenimi
    /// verirdi, oysa gerçek garanti restoreFocus kancasında.
    private func finishPaste(_ outcome: PasteOutcome) {
        // Ses, gösterilecek uyarıdan BAĞIMSIZ karar veriliyor (bkz.
        // `soundForPasteOutcome`): `.pastedIntoFrontmostApp` "yapıştırıldı"
        // sesini, iki `copiedOnly` sonucu da (uyarı gösterseler de
        // göstermeseler de) dürüstçe "kopyalandı" sesini çalar.
        soundFeedback.pasted(outcome)
        switch outcome {
        case .pastedIntoFrontmostApp:
            return
        case .copiedOnlyNoAccessibilityPermission:
            // Sessizce kopyalayıp bırakmıyoruz: kullanıcı ⌘V beklerken hiçbir şey
            // olmadığını görürse uygulamayı bozuk sanır.
            let alert = NSAlert()
            alert.messageText = "Copied to clipboard"
            alert.informativeText = """
                Stash needs Accessibility permission to paste directly. \
                For now, paste with ⌘V.
                """
            alert.addButton(withTitle: "Grant permission")
            alert.addButton(withTitle: "Not now")
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
            alert.messageText = "Copied to clipboard"
            alert.informativeText = "Automatic paste didn't happen this time. The content is on the clipboard — paste it with ⌘V."
            alert.addButton(withTitle: "OK")
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
        let newItem = menu.addItem(withTitle: "New Shelf…",
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
        alert.messageText = "New Shelf"
        alert.informativeText = "Give the shelf a name."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
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
            errorAlert.messageText = "Couldn't create shelf"
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
        alert.messageText = "Stash couldn't start"
        alert.informativeText = "\(error)"
        alert.runModal()
        NSApp.terminate(nil)
    }
}
