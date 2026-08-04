import AppKit
import Foundation
import PasteboardKit
import Store

/// Panoyu yoklayıp yakalananı diske yazar. macOS pano değişimini bildirmediği
/// için zamanlayıcı tek yol; 0,5 saniye kullanıcıya anlık hissettiriyor ve
/// boşta ölçülebilir CPU yakmıyor.
@MainActor
public final class CaptureCoordinator {
    private let store: ClipStore
    private let capture: ClipCapture
    private let interval: TimeInterval
    private var timer: Timer?
    public var onError: ((Error) -> Void)?
    public var onCapture: (() -> Void)?
    /// `onCapture`tan AYRI: `onCapture` her başarılı yakalamada (açılıştaki
    /// ilk yakalama dahil) tetiklenmeli çünkü model listesini tazelemesi
    /// gerekiyor — o kart gerçekten kaydedildi. Bir ses eklendiğinde ise
    /// (bkz. Stash hedefindeki `SoundFeedbackController`) açılış yakalaması
    /// SESSİZ kalmalı (görev kuralı 1); `CaptureCoordinator` sesin kendisini
    /// hiç bilmiyor (bkz. `PasteEngine.onWrite`deki aynı ayrım gerekçesi),
    /// sadece "bu, kullanıcının gerçekten az önce yaptığı bir kopyalama mı"
    /// sorusunun cevabını `CapturedClip.isFirstCapture` üzerinden taşıyor.
    public var onCaptureSound: (() -> Void)?

    // Bulgu 4 (Important): pruneImages() koşulsuz sweepOrphanFiles() +
    // imagesByteSize() çalıştırıyordu — dört dizin taraması + tam bir SQL
    // sorgusu, her yakalamadan sonra (metin dahil), @MainActor'da. Ölçüm:
    // 3000 görsel+küçük resimde 46ms, süpürmenin kendisi 32ms — kullanıcı
    // yazarken bu maliyeti saniyede iki kez (0,5sn yoklama) ödemenin
    // anlamı yok. 60 saniyelik aralık: `pruneImages`in tek başına maliyeti
    // (en kötü durumda ~46ms) bu pencereye yayılınca ihmal edilebilir
    // kalırken (~%0,08), "bir öksüz sonunda 2 GB beklemeden geri kazanılır"
    // vaadi en fazla 60 saniyelik bir gecikmeyle sürüyor — kullanıcının
    // fark edeceği bir süre değil.
    public static let defaultPruneInterval: TimeInterval = 60
    private let pruneInterval: TimeInterval
    private var lastPruneAt: Date?

    public init(store: ClipStore, capture: ClipCapture, interval: TimeInterval = 0.5,
                pruneInterval: TimeInterval = CaptureCoordinator.defaultPruneInterval) {
        self.store = store
        self.capture = capture
        self.interval = interval
        self.pruneInterval = pruneInterval
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    func tick() {
        let front = NSWorkspace.shared.frontmostApplication
        guard let captured = capture.poll(frontmostBundleID: front?.bundleIdentifier) else { return }
        do {
            // Görsel yolu artık `ImageClipWriter`e taşındı (bkz. o dosyadaki
            // gerekçe): var olan satırı ID'siyle birlikte bulup dosyayı
            // gerektiğinde yeniden yazan, `ScreenshotWatcher`in de aynen
            // paylaştığı tek yer — orphan-önleme sırasının iki çağıranda da
            // ayrı ayrı doğru tutulması umuduna kalmıyor.
            if captured.kind == .image, let data = captured.imageData {
                try ImageClipWriter(store: store).write(
                    imageData: data, contentHash: captured.contentHash,
                    sourceBundleID: front?.bundleIdentifier, sourceName: front?.localizedName)
            } else {
                // Metin/bağlantı/dosya klipleri: ID'yi yalnızca var olan bir
                // satır varsa onunkiyle yeniden kullanıyoruz (upsert zaten
                // contentHash'e göre UPDATE dener, INSERT sadece hiçbir satır
                // güncellenmediğinde devreye girer — bu durumda `id` gerçekte
                // sadece o INSERT dalında kullanılır).
                let existing = try store.find(contentHash: captured.contentHash)
                let id = existing?.id ?? UUID()
                try store.upsert(Clip(
                    id: id, createdAt: Date(),
                    kind: ClipKind(rawValue: captured.kind.rawValue) ?? .text,
                    text: captured.text, imagePath: nil,
                    sourceBundleID: front?.bundleIdentifier,
                    sourceName: front?.localizedName,
                    pinned: false, shelfID: nil,
                    contentHash: captured.contentHash,
                    byteSize: captured.text?.utf8.count ?? 0))
            }
            // `lastPruneAt == nil`: açılıştan beri hiç budanmadı — açılışta
            // bir kez KOŞULSUZ çalıştır (bkz. sınıf üstündeki gerekçe).
            // Sonrasında yalnızca aralık dolunca — ara ticklerde tamamen
            // atlanır.
            let now = Date()
            if lastPruneAt == nil || now.timeIntervalSince(lastPruneAt!) >= pruneInterval {
                lastPruneAt = now
                try store.pruneImages(highWater: 2_000_000_000, lowWater: 1_500_000_000)
            }
            onCapture?()
            if !captured.isFirstCapture { onCaptureSound?() }
        } catch {
            // Disk hatası uygulamayı düşürmemeli: o kopya kaybolur, menü
            // çubuğu uyarır, yoklama devam eder.
            onError?(error)
        }
    }
}
