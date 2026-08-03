import Testing
import Foundation
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
