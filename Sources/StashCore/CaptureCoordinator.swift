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

    public init(store: ClipStore, capture: ClipCapture, interval: TimeInterval = 0.5) {
        self.store = store
        self.capture = capture
        self.interval = interval
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
            let id = UUID()
            var imagePath: String?
            // Aynı içerik zaten depolanıyorsa upsert var olan satırı günceller
            // (imagePath'e dokunmadan) — burada yeni bir dosya yazarsak hiçbir
            // satır ona işaret etmez ve orphan dosya, imagesByteSize() üzerinden
            // pruneImages'ı bozar (görülemeyen dosyalar hedefi hep yüksek tutar).
            // Önce kontrol ederek "yaz sonra sil" dansından da kaçınıyoruz.
            let alreadyStored = try store.find(contentHash: captured.contentHash) != nil
            // Diske yazma satır eklemeden önce olmalı: yazma başarısız olursa
            // hiç var olmayan bir dosyaya işaret eden satır oluşmaz.
            if !alreadyStored, let data = captured.imageData {
                let url = store.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
                try data.write(to: url)
                imagePath = url.path
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
            try store.pruneImages(highWater: 2_000_000_000, lowWater: 1_500_000_000)
            onCapture?()
        } catch {
            // Disk hatası uygulamayı düşürmemeli: o kopya kaybolur, menü
            // çubuğu uyarır, yoklama devam eder.
            onError?(error)
        }
    }
}
