import Testing
import Foundation
import Store
import PasteboardKit
@testable import StashCore

// `CaptureCoordinator.onCaptureSound`in kendisi hiçbir ses çalmıyor — Stash
// hedefindeki `SoundFeedbackController` çalıyor. Burada test edilen, o
// kancanın NE ZAMAN tetiklendiği: açılıştaki ilk yakalamada ve atlanan
// (skip edilen) yakalamalarda asla, yalnızca gerçek bir sonraki
// kopyalamada. `FakeCapturePasteboard`, `CaptureCoordinatorTests.swift`te
// tanımlı (`private` değil) — burada da kullanılıyor.

@MainActor
private func makeCoordinator() throws -> (CaptureCoordinator, FakeCapturePasteboard) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-core-capture-sound-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    let pb = FakeCapturePasteboard()
    let capture = ClipCapture(pasteboard: pb, policy: CapturePolicy())
    let coordinator = CaptureCoordinator(store: store, capture: capture)
    return (coordinator, pb)
}

@MainActor @Test func theVeryFirstTickOfALaunchNeverFiresTheCaptureSoundHook() throws {
    // Görev kuralı 1: açılışta panoda zaten duran içerik "az önce
    // kopyalandı" değildir; onu sesli karşılamak her açılışta anlamsız bir
    // çınlamaya dönüşürdü.
    let (coordinator, pb) = try makeCoordinator()
    pb.putImage(Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03]))
    var soundFired = false
    coordinator.onCaptureSound = { soundFired = true }
    coordinator.tick()
    #expect(soundFired == false)
    // Karşılaştırma için: `onCapture` (model tazeleme) hâlâ tetiklenmeli —
    // yalnızca ses kancası açılışta sessiz, kart kaydı normal işliyor.
}

@MainActor @Test func firstTickStillReloadsTheModelEvenThoughItStaysSilent() throws {
    let (coordinator, pb) = try makeCoordinator()
    pb.putImage(Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03]))
    var reloaded = false
    coordinator.onCapture = { reloaded = true }
    coordinator.tick()
    #expect(reloaded == true)
}

@MainActor @Test func aGenuineCaptureAfterLaunchFiresTheSoundHookExactlyOnce() throws {
    let (coordinator, pb) = try makeCoordinator()
    pb.putImage(Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03]))
    coordinator.tick() // açılış yakalaması — sessiz kalmalı

    var soundCount = 0
    coordinator.onCaptureSound = { soundCount += 1 }
    pb.putImage(Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x04]))
    coordinator.tick()
    #expect(soundCount == 1)
}

@MainActor @Test func aSkippedCaptureNeverFiresTheSoundHook() throws {
    // Görev kuralı 2: concealed/transient tipli bir kopyalama `ClipCapture`
    // tarafından zaten kaydedilmiyor (`poll` nil dönüyor) — `tick()` bu
    // durumda erken çıkıyor, ses kancası da hiç tetiklenmemeli.
    let (coordinator, pb) = try makeCoordinator()
    coordinator.tick() // açılış: pano boş

    var soundFired = false
    coordinator.onCaptureSound = { soundFired = true }
    pb.text = "hunter2"
    pb.types = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
    pb.changeCount += 1
    coordinator.tick()
    #expect(soundFired == false)
}
