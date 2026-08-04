import Testing
import Foundation
import PasteboardKit
import PasteEngine
import Store
@testable import StashCore

// I2: Stash panoya kendi yazdığı bir yapıştırmayı, 0,5 saniye sonra
// CaptureCoordinator onu yokladığında normal bir kullanıcı kopyalaması
// sanıp geri yakalıyordu. Sonuç: kartın sourceName'i "yapıştırıldığı"
// uygulamaya dönüyordu (provenance kayboluyordu) ve filtre uygulanan bir
// yapıştırma (metni değiştirdiği için farklı hash'e düşüyor) ikinci bir
// satır olarak ikileniyordu.
//
// `PasteWriting` (PasteEngine modülü) ve `PasteboardReading` (PasteboardKit
// modülü) bilerek birbirini bilmiyor; gerçek `NSPasteboard.general`i taklit
// eden bu tek sahte, ikisini de uygulayarak testte gerçek panonun "aynı
// changeCount, iki taraftan da görülür" özelliğini yeniden üretiyor —
// AppDelegate'in `engine.onWrite = { capture.suppressChangeCount($0) }`
// bağlantısının gerçek hayatta dayandığı garanti bu.
private final class FakeSharedPasteboard: PasteboardReading, PasteWriting, @unchecked Sendable {
    private(set) var changeCount = 0
    var types: [String] = []
    private var text: String?

    func string() -> String? { text }
    func imageData() -> Data? { nil }
    func fileURLStrings() -> [String]? { nil }
    func webURLString() -> String? { nil }

    /// Kullanıcının gerçek bir kopyalamasını simüle eder — `PasteWriting`
    /// üzerinden DEĞİL, panoyu doğrudan değiştirerek (Stash'in kendi
    /// yazdığından ayırt edilebilsin diye).
    func userCopy(_ value: String) {
        text = value
        types = ["public.utf8-plain-text"]
        changeCount += 1
    }

    @discardableResult
    func writeText(_ value: String, plainOnly: Bool) -> Int {
        text = value
        types = ["public.utf8-plain-text"]
        changeCount += 1
        return changeCount
    }
    @discardableResult
    func writeImage(_ data: Data) -> Int { changeCount += 1; return changeCount }
}

@MainActor
private func makeHarness() throws -> (CaptureCoordinator, ClipStore, PasteEngine, FakeSharedPasteboard) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-selfcapture-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    let shared = FakeSharedPasteboard()
    let capture = ClipCapture(pasteboard: shared, policy: CapturePolicy())
    let coordinator = CaptureCoordinator(store: store, capture: capture)
    let engine = PasteEngine(pasteboard: shared, keystrokes: TrustedKeys())
    // Bu, AppDelegate'in yaptığı tam bağlantı — bkz. AppDelegate.swift.
    engine.onWrite = { [weak capture] changeCount in capture?.suppressChangeCount(changeCount) }
    return (coordinator, store, engine, shared)
}

@MainActor @Test func pastingAnExistingClipDoesNotTouchItsRowOrAddANewOne() throws {
    let (coordinator, store, engine, shared) = try makeHarness()
    shared.userCopy("hello \"world\" again")
    coordinator.tick()
    let original = try #require(try store.recent(limit: 10).first)

    _ = engine.paste(text: original.text!, filters: [])
    coordinator.tick() // "0,5 saniye sonraki" yoklama

    let rows = try store.recent(limit: 10)
    #expect(rows.count == 1)
    #expect(rows[0].sourceBundleID == original.sourceBundleID)
    #expect(rows[0].sourceName == original.sourceName)
    #expect(rows[0].createdAt == original.createdAt)
}

@MainActor @Test func aFilteredPasteThatChangesTheTextStillDoesNotAddASecondRow() throws {
    // Filtreli yapıştırma (⌥↵) metni değiştirir (ör. tırnakları düzeltir),
    // bu yüzden ham self-capture'da FARKLI bir contentHash üretirdi —
    // suppressChangeCount içerik farkına bakmadan, sadece changeCount'a
    // bakarak bunu da atlamalı.
    let (coordinator, store, engine, shared) = try makeHarness()
    shared.userCopy("hello \"world\" again")
    coordinator.tick()
    #expect(try store.recent(limit: 10).count == 1)

    _ = engine.paste(text: "hello   \u{201C}world\u{201D}\n\nagain", filters: [])
    coordinator.tick()

    #expect(try store.recent(limit: 10).count == 1)
}

@MainActor @Test func aGenuineUserCopyImmediatelyAfterAPasteIsStillCaptured() throws {
    let (coordinator, store, engine, shared) = try makeHarness()
    shared.userCopy("ilk")
    coordinator.tick()
    #expect(try store.recent(limit: 10).count == 1)

    _ = engine.paste(text: "ilk", filters: [])
    // Yapıştırmadan hemen sonra kullanıcı gerçekten başka bir şey kopyalıyor;
    // bu, suppressChangeCount'un işaretlediği TEK changeCount'u geçiyor.
    shared.userCopy("gerçek kopya")
    coordinator.tick()

    let rows = try store.recent(limit: 10)
    #expect(rows.count == 2)
    #expect(rows.contains { $0.text == "gerçek kopya" })
}
