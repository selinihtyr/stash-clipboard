import AppKit
import StashCore
import Updater

/// Menüdeki güncelleme öğesinin arkasındaki durum makinesi.
///
/// Ayrım bilinçli: `Updater` modülü ne bir uyarı penceresi açar ne de menüyü
/// bilir (saf, test edilebilir), bu sınıf da sürüm karşılaştırması ya da imza
/// doğrulaması yapmaz — sadece ikisini birbirine bağlar ve kullanıcıya ne
/// gösterileceğine karar verir.
/// `NSObject`: menü öğesinin hedefi olabilmesi için. `NSMenuItem.target`
/// `AnyObject?` aldığı için düz bir Swift sınıfı atamak derlenir, ama tıklama
/// ObjC mesajı olarak gönderildiğinden çalışma zamanında sessizce hiçbir şey
/// olmaz — menüde duran ama tıklanınca ölü bir öğe.
@MainActor
final class UpdateController: NSObject {
    enum State: Equatable {
        case idle
        case checking
        case available(Release)
        case downloading(Release)
    }

    /// Otomatik kontrolün ne sıklıkta "vakti geldi mi" diye bakacağı. Kontrolün
    /// kendisi günde bir (bkz. `UpdateSchedule.interval`); bu sadece uykudan
    /// dönen, günlerce açık kalan bir Mac'te o günün kontrolünün kaçmamasını
    /// sağlayan nabız.
    private static let pollInterval: TimeInterval = 30 * 60
    private static let lastCheckDefaultsKey = "lastUpdateCheck"

    private let client: ReleaseFetching
    private let installer: UpdateInstaller
    private let policy: CodeSignaturePolicy
    private let assetName: String
    private let currentVersion: AppVersion
    private let defaults: UserDefaults
    private let launchedAt: Date
    private var timer: Timer?

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?() } }
    }
    /// Menü başlığını tazelemek için AppDelegate'in taktığı kanca.
    var onStateChange: (() -> Void)?
    /// Otomatik kontrolün açık olup olmadığını canlı okur — ayarlar
    /// penceresinden kapatıldığında bir sonraki nabızda etkisini göstermeli,
    /// yeniden başlatmayı beklememeli.
    var automaticChecksEnabled: () -> Bool = { true }

    init(client: ReleaseFetching, policy: CodeSignaturePolicy, assetName: String,
         currentVersion: AppVersion, defaults: UserDefaults = .standard,
         launchedAt: Date = Date()) {
        self.client = client
        self.policy = policy
        self.assetName = assetName
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.launchedAt = launchedAt
        self.installer = UpdateInstaller(policy: policy)
        super.init()
    }

    /// Menü öğesinin başlığı. Durum burada okunuyor çünkü kullanıcının
    /// güncellemeden haberi olmasının yolu bu: arka plan kontrolü bir şey
    /// bulunca ekranın ortasına modal bir pencere ATMIYORUZ — menü öğesi
    /// "Update to 0.2.0…" oluyor, kullanıcı hazır olduğunda tıklıyor.
    var menuTitle: String {
        switch state {
        case .idle: return "Check for Updates…"
        case .checking: return "Checking for Updates…"
        case .available(let release): return "Update to \(release.version)…"
        case .downloading: return "Downloading Update…"
        }
    }

    var menuItemEnabled: Bool {
        switch state {
        case .idle, .available: return true
        case .checking, .downloading: return false
        }
    }

    func startAutomaticChecks() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        // `.common`: menü açıkken ya da bir sürükleme sürerken de ateşlensin.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        checkIfDue()
    }

    private func checkIfDue() {
        guard case .idle = state else { return }
        let lastCheck = defaults.object(forKey: Self.lastCheckDefaultsKey) as? Date
        guard UpdateSchedule.shouldCheck(enabled: automaticChecksEnabled(),
                                         lastCheck: lastCheck,
                                         launchedAt: launchedAt,
                                         now: Date())
        else { return }
        Task { await check(announceResult: false) }
    }

    /// Menüden elle tetiklenen kontrol. Otomatik kontrolden tek farkı sonucu
    /// göstermesi: kullanıcı tıkladıysa "her şey güncel"i de görmeli, yoksa
    /// tıklamanın hiçbir şey yapmadığını sanır.
    @objc func checkNow() {
        if case .available(let release) = state {
            presentUpdate(release)
            return
        }
        Task { await check(announceResult: true) }
    }

    private func check(announceResult: Bool) async {
        guard case .idle = state else { return }
        state = .checking
        defer { if case .checking = state { state = .idle } }
        do {
            let data = try await client.latestReleaseJSON()
            defaults.set(Date(), forKey: Self.lastCheckDefaultsKey)
            let release = try parseLatestRelease(data, assetName: assetName)
            switch updateAvailability(current: currentVersion, latest: release) {
            case .upToDate:
                state = .idle
                if announceResult { presentUpToDate() }
            case .available(let release):
                state = .available(release)
                if announceResult { presentUpdate(release) }
            }
        } catch {
            // Henüz yayınlanmış sürüm yoksa bu bir arıza değil (kaynaktan
            // derleyen herkes için normal); elle sorulduysa yine de dürüstçe
            // söylüyoruz, arka planda sessiz geçiyoruz.
            state = .idle
            if announceResult { presentCheckFailure(error) }
        }
    }

    // MARK: - Kullanıcıya gösterilenler

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "Stash is up to date"
        alert.informativeText = "You're running \(currentVersion)."
        alert.runModal()
    }

    private func presentCheckFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        if case ReleaseClientError.noReleaseYet = error {
            alert.informativeText = """
                No release has been published yet. You're running a build from \
                source (\(currentVersion)); update it with git pull and \
                ./scripts/bundle.sh.
                """
        } else {
            alert.informativeText = """
                \(friendlyReason(for: error)) You can always download the latest \
                version from the releases page.
                """
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Releases Page")
            if alert.runModal() == .alertSecondButtonReturn { openReleasesPage() }
            return
        }
        alert.runModal()
    }

    private func presentUpdate(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Stash \(release.version) is available"
        var body = "You're running \(currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            // Sürüm notları uzun olabilir; uyarı penceresini ekrandan taşıracak
            // kadarını kesip tamamı için sayfaya yönlendiriyoruz.
            let trimmed = notes.count > 700 ? String(notes.prefix(700)) + "…" : notes
            body += "\n\n" + trimmed
        }
        if !runningCopyMatchesPolicy {
            // Kaynaktan kendi imzasıyla derleyen biri, yayınlanan imzalı
            // sürüme geçtiğinde imza kimliği değişir ve Erişilebilirlik izni
            // düşer (bkz. README, "Signing"). Bunu sonradan "yapıştırma
            // bozuldu" olarak yaşamaktansa önceden söylüyoruz.
            body += """


                Note: this copy of Stash wasn't signed by the release identity \
                (you probably built it yourself), so macOS will treat the update \
                as a different app — you'll need to grant Accessibility again \
                for direct pasting.
                """
        }
        alert.informativeText = body
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    private var runningCopyMatchesPolicy: Bool {
        (try? verifyCodeSignature(ofBundleAt: Bundle.main.bundleURL, policy: policy)) != nil
    }

    private func openReleasesPage() {
        NSWorkspace.shared.open(URL(string:
            "https://github.com/selinihtyr/stash-clipboard/releases")!)
    }

    // MARK: - Kurulum

    private func install(_ release: Release) {
        let destination = Bundle.main.bundleURL
        do {
            // Uygulamayı kapatmadan ÖNCE: yazılamayan bir yere kurulmuşsa
            // takas yarıda kalır ve kullanıcı çalıştırılacak hiçbir şey
            // olmadan kalırdı.
            try installer.preflight(destination: destination)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Can't update in place"
            alert.informativeText = """
                Stash is installed somewhere it can't replace itself \
                (\(destination.path)). Move Stash to your Applications folder and \
                try again, or download the new version manually.
                """
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Releases Page")
            if alert.runModal() == .alertSecondButtonReturn { openReleasesPage() }
            return
        }

        state = .downloading(release)
        Task {
            do {
                let zip = try await client.download(release.downloadURL)
                let staged = try installer.stageVerifiedApp(
                    fromZip: zip, expectedVersion: release.version)
                try handOff(stagedApp: staged, destination: destination, zip: zip)
            } catch {
                state = .available(release)
                presentInstallFailure(error, release: release)
            }
        }
    }

    /// Takası yapacak betiği yazar, başlatır ve uygulamadan çıkar.
    private func handOff(stagedApp: URL, destination: URL, zip: URL) throws {
        // Betik, temizlenecek dizinlerin DIŞINDA duruyor: çalışan bir kabuk
        // betiğini altından silmek, `sh`in dosyayı parça parça okuması yüzünden
        // betiğin ortasında kesilmesine yol açabilir.
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("stash-update-\(UUID().uuidString).sh")
        let body = updateHandoffScript(
            stagedApp: stagedApp, destination: destination,
            quittingPID: ProcessInfo.processInfo.processIdentifier,
            cleanUp: [stagedApp.deletingLastPathComponent(), zip])
        try body.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()

        // Çıkmadan önce betiğin beklemeye başlaması için değil — betik zaten
        // sürecin ölmesini bekliyor — kullanıcının menüden bir şey seçmiş
        // olmasının sonucunu görmesi için kısa bir an bırakıyoruz.
        NSApp.terminate(nil)
    }

    private func presentInstallFailure(_ error: Error, release: Release) {
        let alert = NSAlert()
        alert.messageText = "Couldn't install the update"
        alert.informativeText = """
            \(friendlyReason(for: error)) Nothing on your Mac was changed — the \
            copy you're running is untouched. You can download \(release.tag) \
            yourself from the releases page.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases Page")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    /// Ham hata metnini kullanıcıya basmıyoruz; ne olduğunu insanca söylüyoruz.
    /// Özellikle imza reddi: bunu "bir şeyler ters gitti" diye geçiştirmek
    /// yanlış olur — kullanıcının bilmesi gereken bir güvenlik olayı.
    private func friendlyReason(for error: Error) -> String {
        switch error {
        case is SignatureCheckError:
            return """
                The downloaded update wasn't signed by the same identity that \
                signs Stash, so it was rejected and deleted.
                """
        case UpdateInstallError.versionMismatch, UpdateInstallError.wrongBundleIdentifier:
            return "The downloaded file wasn't the version it claimed to be, so it was rejected."
        case UpdateInstallError.noAppInArchive, UpdateInstallError.extractionFailed:
            return "The downloaded archive couldn't be opened."
        case ReleaseFeedError.missingAsset:
            return "That release doesn't include a downloadable build yet."
        case ReleaseClientError.http(let status):
            return "GitHub replied with an error (HTTP \(status))."
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            return "There's no internet connection."
        default:
            return "The update couldn't be completed."
        }
    }
}
