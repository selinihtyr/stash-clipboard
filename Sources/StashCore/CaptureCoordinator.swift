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
            // Var olan satırı ID'siyle birlikte alıyoruz: bir satır zaten
            // varsa dosyayı onun ID'siyle adlandırıp yeniden yazıyoruz (yeni
            // bir ID ile yazmak, upsert contentHash'e göre eski satırı
            // güncelleyeceği için hiçbir satırın adlandırmadığı bir dosya
            // bırakırdı — tam da bu fonksiyonun kaçınmaya çalıştığı orphan).
            let existing = try store.find(contentHash: captured.contentHash)
            let id = existing?.id ?? UUID()
            var imagePath = existing?.imagePath
            // Dosya gerçekten yazılmalı mı? Satır hiç yoksa (ilk yakalama)
            // ya da satır var ama dosyası yok (budanmış — I3: `imagePath`
            // NULL'a düşmüş — ya da diskten elle silinmiş) evet; satır zaten
            // geçerli bir dosyaya işaret ediyorsa hayır — burada yeniden
            // yazmak, hiçbir satırın işaret etmediği bir dosya bırakmaz ama
            // gereksiz bir yazma+orphan riski de taşımaz (asıl orphan
            // korumasının nedeni buydu, C3/pruneImages'ın üstündeki gerekçeye
            // bkz.) — o korumayı burada da koruyoruz.
            let fileMissing = imagePath.map { !FileManager.default.fileExists(atPath: $0) } ?? true
            // Diske yazma satır eklemeden/güncellemeden önce olmalı: yazma
            // başarısız olursa hiç var olmayan bir dosyaya işaret eden satır
            // oluşmaz/güncellenmez.
            if fileMissing, let data = captured.imageData {
                let url = store.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
                try data.write(to: url)
                imagePath = url.path
                // Küçük resim türetilmiş bir dosya, orijinalin yerini tutmaz:
                // üretimi başarısız olsa da (ör. çözülemeyen veri) yakalama
                // hâlâ başarılı sayılır — kart o zaman orijinali kendisi
                // çözer (bkz. ClipCardView), daha yavaş ama klip kaybolmaz.
                if let thumbData = ThumbnailGenerator.makeJPEG(from: data) {
                    let thumbURL = store.thumbsDirectory.appendingPathComponent("\(id.uuidString).jpg")
                    try? thumbData.write(to: thumbURL)
                }
            }
            try store.upsert(Clip(
                id: id, createdAt: Date(),
                kind: ClipKind(rawValue: captured.kind.rawValue) ?? .text,
                text: captured.text, imagePath: imagePath,
                sourceBundleID: front?.bundleIdentifier,
                sourceName: front?.localizedName,
                pinned: false, shelfID: nil,
                contentHash: captured.contentHash,
                byteSize: captured.imageData?.count ?? (captured.text?.utf8.count ?? 0)))
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
        } catch {
            // Disk hatası uygulamayı düşürmemeli: o kopya kaybolur, menü
            // çubuğu uyarır, yoklama devam eder.
            onError?(error)
        }
    }
}
