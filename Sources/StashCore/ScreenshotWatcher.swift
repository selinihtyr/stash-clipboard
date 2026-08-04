import Foundation
import PasteboardKit
import Store

/// `ScreenshotWatcher.status`ün dört durumu — Ayarlar penceresi ve
/// `AppDelegate` bunu doğrudan gösterip/tepki verebilsin diye (görev kuralı
/// 7: "asla sessizce başarısız olma").
public enum ScreenshotWatchStatus: Equatable, Sendable {
    case stopped
    case watching(URL)
    /// Yapılandırılmış klasör bu yolda yok (silinmiş, taşınmış, harici bir
    /// diskte ve disk takılı değil). Çökme yok — sadece bekliyoruz, klasör
    /// geri gelirse bir sonraki `tick()` bunu görür.
    case folderMissing(URL)
    /// Klasörün içeriğini okuma denemesi hata fırlattı — gerçek dünyada bu
    /// neredeyse hep TCC izninin reddedilmesi demek (Masaüstü/Belgeler
    /// korumalı). İzleyici burada KENDİNİ durdurur (bkz. `tick()`): aksi
    /// halde her tur aynı reddedilen okumaya yeniden çarpardı.
    case permissionDenied
}

/// Ekran görüntüsü klasörünü izleyip yeni, tamamlanmış ve GERÇEKTEN ekran
/// görüntüsü olan dosyaları panodan kopyalanmış gibi geçmişe ekler.
///
/// Sahibinin alışkanlığı ⌘⇧4: PNG doğrudan diske yazılır, pano hiç
/// tetiklenmez — `ClipCapture` panoyu yokladığı için bunu asla göremez (bkz.
/// görev tanımının "Why" bölümü). Bu sınıf o boşluğu, panoyu değil bir
/// klasörü yoklayarak kapatıyor; `CaptureCoordinator`ın zaten kurduğu
/// "zamanlayıcıyla yokla" desenini tekrarlıyor (macOS klasör içeriği
/// değişimini de bildirmiyor).
///
/// Opt-in, varsayılan KAPALI (görev kuralı 8) — `start()`ı çağırmak (ya da
/// çağırmamak) sorumluluğu tamamen `AppDelegate`e ait; bu sınıf kendi
/// başına asla bir klasör okumaz.
@MainActor
public final class ScreenshotWatcher {
    /// Bir dosya "durulmuş" (tamamen yazılmış) sayılmadan önce sınıflandırma
    /// için tanınan yeniden deneme sayısı. Neden gerekli: elle deneyle
    /// doğrulandı — bir dosyaya `com.apple.metadata:kMDItemIsScreenCapture`
    /// genişletilmiş özniteliğini yazmak, `MDItemCopyAttribute`in onu ANINDA
    /// görmesini garanti ETMİYOR (`mdworker`ın dosyayı yeniden indekslemesi
    /// gerekiyor, bu senkron değil — taze bir dosyada birkaç saniye
    /// sürebilir). Sınıflandırıcı bu pencerede `nil`/`false` dönebilir; tek
    /// seferde vazgeçmek gerçek bir ekran görüntüsünü sessizce kaçırırdı —
    /// özelliğin var olma amacının tam tersi. Sabit `interval`e (varsayılan
    /// 1sn) göre bu, indekslemeye ~10 saniyelik bir bekleme payı tanıyor;
    /// hâlâ belirlenemiyorsa dosyaya bir daha dokunmuyoruz (görev kuralı 2:
    /// "belirlenemiyorsa içe aktarmama yönünde hata yap" — sonsuza dek değil
    /// sonlu bir denemeden sonra).
    public static let defaultMaxClassificationAttempts = 10

    private let store: ClipStore
    private let folder: () -> URL
    private let reader: ScreenshotDirectoryReading
    private let classifier: ScreenshotClassifying
    private let interval: TimeInterval
    private let maxClassificationAttempts: Int
    private var timer: Timer?

    public private(set) var status: ScreenshotWatchStatus = .stopped
    /// `status` her değiştiğinde tetiklenir. `AppDelegate` `.permissionDenied`i
    /// görünce anahtarı gerçek duruma göre kapatıp görünür bir uyarı gösterir
    /// — `LoginItem.setEnabled` başarısızlığının Ayarlar'a yansıtılma
    /// şekliyle aynı desen (görev kuralı 7).
    public var onStatusChange: ((ScreenshotWatchStatus) -> Void)?
    /// Bir ekran görüntüsü depoya yazıldığında (kart listesini tazelemek
    /// için) — `CaptureCoordinator.onCapture`ın karşılığı.
    public var onIngest: (() -> Void)?
    /// `onIngest`ten AYRI, tıpkı `CaptureCoordinator.onCaptureSound`daki
    /// gibi: ses çalma kararı burada değil, çağıran tarafta (bkz. o
    /// dosyadaki gerekçe — `SoundFeedbackController` anahtarı okuyup çalar).
    public var onIngestSound: (() -> Void)?

    /// `start()`ta bir kez dolduruluyor, bir daha asla eklenmiyor: izleme
    /// BAŞLAMADAN ÖNCE var olan her dosyanın yolu. Görev kuralı 3 — yaratılış
    /// TARİHİNE değil (saat kayması, dosyayı kopyalayıp taşımak gibi
    /// işlemler tarihi koruyabilir/değiştirebilir) bu ilk anlık görüntüye
    /// dayanmak daha güvenilir ve saf: "bu yol izlemeye başladığımda zaten
    /// oradaydı" sorusuna kesin cevap verir.
    private var baseline: Set<URL> = []
    /// Karara bağlanmış (içe aktarılmış YA DA kalıcı olarak atlanmış)
    /// dosyalar — `baseline` de dahil. Aynı dosyayı sonsuza dek yeniden
    /// denemeyelim.
    private var resolved: Set<URL> = []
    /// Henüz karara bağlanmamış adaylar: son gözlemlenen boyut + kaç kez
    /// sınıflandırma denendi. Boyut bir turdan diğerine DEĞİŞMEDEN kalırsa
    /// (ve sıfırdan büyükse) dosya "durulmuş" sayılıp sınıflandırma denenir
    /// — görev kuralı 4: sabit bir uyku yerine bu poll-tabanlı istikrar
    /// kontrolü, zaten var olan yoklama ritmine oturuyor.
    private struct Pending { var lastSize: Int; var classificationAttempts = 0 }
    private var pending: [URL: Pending] = [:]

    public init(store: ClipStore,
                folder: @escaping () -> URL = { ScreenshotFolder.resolve() },
                reader: ScreenshotDirectoryReading = FileManagerScreenshotDirectoryReader(),
                classifier: ScreenshotClassifying = SpotlightScreenshotClassifier(),
                interval: TimeInterval = 1.0,
                maxClassificationAttempts: Int = ScreenshotWatcher.defaultMaxClassificationAttempts) {
        self.store = store
        self.folder = folder
        self.reader = reader
        self.classifier = classifier
        self.interval = interval
        self.maxClassificationAttempts = maxClassificationAttempts
    }

    /// Klasörü çözer, o anki içeriği "zaten vardı" olarak damgalar (görev
    /// kuralı 3) ve zamanlayıcıyı kurar. Klasör yoksa ya da ilk okuma
    /// izinle reddedilirse zamanlayıcı hiç kurulmaz — `status` çağırana
    /// gerçek durumu söyler, `AppDelegate` buna göre anahtarı geri alır.
    public func start() {
        stop()
        let url = folder()
        guard FileManager.default.fileExists(atPath: url.path) else {
            setStatus(.folderMissing(url))
            return
        }
        do {
            let entries = try reader.contentsOfDirectory(at: url)
            baseline = Set(entries.map(\.url))
            resolved = baseline
            pending = [:]
            setStatus(.watching(url))
        } catch {
            setStatus(.permissionDenied)
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        if status != .stopped { setStatus(.stopped) }
    }

    private func setStatus(_ newStatus: ScreenshotWatchStatus) {
        guard status != newStatus else { return }
        status = newStatus
        onStatusChange?(newStatus)
    }

    func tick() {
        // Klasör kullanıcı çalışırken değişebilir (görev kuralı 1): her
        // turda yeniden çözüyoruz, yeniden başlatma gerekmiyor.
        let url = folder()
        guard FileManager.default.fileExists(atPath: url.path) else {
            setStatus(.folderMissing(url))
            return
        }
        let entries: [ScreenshotFileInfo]
        do {
            entries = try reader.contentsOfDirectory(at: url)
        } catch {
            // İzin sonradan reddedilmiş olabilir (ör. Sistem Ayarları'ndan
            // elle kaldırılmış). Sessizce sürdürmüyoruz: durumu bildirip
            // zamanlayıcıyı KENDİMİZ durduruyoruz — aksi halde her tur aynı
            // (muhtemelen kalıcı) izin reddine yeniden çarpar.
            setStatus(.permissionDenied)
            stop()
            return
        }
        setStatus(.watching(url))

        let currentURLs = Set(entries.map(\.url))
        // Kaybolan (silinmiş/taşınmış) dosyaları bekleyen kayıttan temizle;
        // aksi halde var olmayan bir dosya için sonsuza dek bellek tutulur.
        pending = pending.filter { currentURLs.contains($0.key) }

        for entry in entries {
            guard !resolved.contains(entry.url) else { continue }
            let previous = pending[entry.url]
            if let previous, previous.lastSize == entry.size, entry.size > 0 {
                classify(entry, attempts: previous.classificationAttempts)
            } else {
                // İlk gözlem ya da boyut değişti (dosya hâlâ yazılıyor):
                // en az bir tur daha bekle, henüz sınıflandırma denemiyoruz.
                pending[entry.url] = Pending(lastSize: entry.size,
                                             classificationAttempts: previous?.classificationAttempts ?? 0)
            }
        }
    }

    private func classify(_ entry: ScreenshotFileInfo, attempts: Int) {
        if classifier.isScreenCapture(at: entry.url) == true {
            resolved.insert(entry.url)
            pending.removeValue(forKey: entry.url)
            ingest(entry)
            return
        }
        let nextAttempts = attempts + 1
        if nextAttempts >= maxClassificationAttempts {
            // Sınıflandırma denemesi tükendi: görev kuralı 2 gereği
            // belirlenemeyen bir dosya içe aktarılmaz — kalıcı olarak
            // atlıyoruz, her turda yeniden denemiyoruz.
            resolved.insert(entry.url)
            pending.removeValue(forKey: entry.url)
        } else {
            pending[entry.url] = Pending(lastSize: entry.size, classificationAttempts: nextAttempts)
        }
    }

    private func ingest(_ entry: ScreenshotFileInfo) {
        guard let data = try? Data(contentsOf: entry.url), !data.isEmpty else { return }
        // `ClipCapture.hash` ile AYNI algoritma: aynı görsel panodan da
        // kopyalanırsa ikisi aynı contentHash'e düşüp `ClipStore.upsert`te
        // TEK satırda birleşir (görev kuralı 6) — bkz. `ClipCapture.hash`
        // üstündeki gerekçe.
        let contentHash = ClipCapture.hash(.image, data)
        do {
            try ImageClipWriter(store: store).write(
                imageData: data, contentHash: contentHash,
                sourceBundleID: nil,
                // Görev kuralı 5: bu yoldan gelen klipler `loginwindow` gibi
                // anlamsız bir öndeki-uygulama adı değil, uygulamanın kendi
                // sesiyle konuşan bir açıklama taşır.
                sourceName: "Screenshot")
            onIngest?()
            onIngestSound?()
        } catch {
            // Disk hatası bu izleyiciyi düşürmemeli (bkz.
            // `CaptureCoordinator`daki aynı gerekçe): bu dosya kaybolur,
            // izleme bir sonraki dosyayla sürer.
        }
    }
}
