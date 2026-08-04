import Testing
import Foundation
import AppKit
import Store
import PasteboardKit
@testable import StashCore

final class FakeCapturePasteboard: PasteboardReading, @unchecked Sendable {
    var changeCount = 0
    var types: [String] = []
    var text: String?
    var image: Data?
    var files: [String]?
    func string() -> String? { text }
    func imageData() -> Data? { image }
    func fileURLStrings() -> [String]? { files }
    func webURLString() -> String? { nil }

    /// Panoya "yeni bir kopyalama" gibi görünmesi için changeCount'u da artırır;
    /// aksi halde ClipCapture.poll ikinci çağrıda değişiklik görmez.
    func putImage(_ data: Data) {
        image = data; text = nil; files = nil
        types = ["public.png"]
        changeCount += 1
    }
}

@MainActor
private func makeCoordinator() throws -> (CaptureCoordinator, ClipStore, FakeCapturePasteboard) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-core-capture-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    let pb = FakeCapturePasteboard()
    let capture = ClipCapture(pasteboard: pb, policy: CapturePolicy())
    let coordinator = CaptureCoordinator(store: store, capture: capture)
    return (coordinator, store, pb)
}

@MainActor @Test func repeatedImageCaptureDoesNotLeaveOrphanFiles() throws {
    // Aynı ekran görüntüsü iki kez kopyalanınca upsert var olan satırı
    // günceller (yeni satır açmaz); ikinci yakalama dosyayı hiç yazmamalı,
    // yoksa hiçbir satırın işaret etmediği bir dosya diskte kalır.
    let (coordinator, store, pb) = try makeCoordinator()
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
    pb.putImage(png)
    coordinator.tick()
    pb.putImage(png)
    coordinator.tick()

    let rows = try store.recent(limit: 10)
    #expect(rows.count == 1)

    let path = try #require(rows.first?.imagePath)
    #expect(FileManager.default.fileExists(atPath: path))

    let files = try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectory.path)
    #expect(files.count == 1)
}

/// Sahte PNG başlıkları (bu dosyadaki `png` sabiti gibi) NSImage tarafından
/// çözülemez — küçük resim üretimi "başarısız olmalı" testleri için doğru,
/// ama "başarılı olmalı" testleri gerçek, çözülebilir bir görsel ister.
private func makeRealPNG(width: Int = 900, height: Int = 600) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemPurple.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

@MainActor @Test func capturingAnImageWritesBothTheOriginalAndAThumbnail() throws {
    let (coordinator, store, pb) = try makeCoordinator()
    pb.putImage(makeRealPNG())
    coordinator.tick()

    let clip = try #require(try store.recent(limit: 10).first)
    #expect(FileManager.default.fileExists(atPath: try #require(clip.imagePath)))
    let thumbPath = try #require(clip.thumbPath)
    #expect(FileManager.default.fileExists(atPath: thumbPath))
}

@MainActor @Test func theThumbnailIsSmallerOnDiskThanTheOriginal() throws {
    let (coordinator, store, pb) = try makeCoordinator()
    pb.putImage(makeRealPNG())
    coordinator.tick()

    let clip = try #require(try store.recent(limit: 10).first)
    let originalSize = try FileManager.default.attributesOfItem(
        atPath: try #require(clip.imagePath))[.size] as? Int
    let thumbSize = try FileManager.default.attributesOfItem(
        atPath: try #require(clip.thumbPath))[.size] as? Int
    #expect(try #require(thumbSize) < (try #require(originalSize)))
}

@MainActor @Test func aCaptureWhoseThumbnailCannotBeWrittenStillStoresTheClipAndItsOriginal() throws {
    // Küçük resim türetilmiş bir dosya; bu klibin görsel verisi NSImage
    // tarafından hiç çözülemiyor (sahte başlık), yani üretim baştan
    // başarısız olacak — capture'ın buna rağmen tamamlandığını doğruluyoruz.
    let (coordinator, store, pb) = try makeCoordinator()
    let undecodable = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
    pb.putImage(undecodable)
    coordinator.tick()

    let clip = try #require(try store.recent(limit: 10).first)
    let imagePath = try #require(clip.imagePath)
    #expect(FileManager.default.fileExists(atPath: imagePath))
    // Küçük resim yok — ama bu klibi kaybetmedi, sadece kartı orijinale
    // düşürüyor (bkz. ClipCardView).
    #expect(!FileManager.default.fileExists(atPath: try #require(clip.thumbPath)))
}
