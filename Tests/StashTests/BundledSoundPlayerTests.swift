import Testing
import AppKit
@testable import Stash

// `FeedbackSound.resourceFileName` + `BundledSoundPlayer` yükleme dayanıklılığı.
// Gerçek `.play()` burada HİÇ çağrılmıyor: `isCapturedLoaded`/`isPastedLoaded`
// bir `NSSound`in belleğe başarıyla okunduğunu, sesi gerçekten çalmadan
// doğruluyor (görev isteği: "test ederken gerçekten ses çalma" hâlâ geçerli
// — bu artık `SystemSoundPlayer` için değil `BundledSoundPlayer` için).

// MARK: - FeedbackSound → dosya adı eşlemesi

@Test func capturedMapsToTheCopyFile() {
    #expect(FeedbackSound.captured.resourceFileName == "copy")
}

@Test func pastedMapsToTheDistinctPasteFile() {
    #expect(FeedbackSound.pasted.resourceFileName == "paste")
}

// MARK: - Gerçek paket dosyaları çökmeden yükleniyor

/// `#filePath`ten repo köküne çıkıp gerçek `Resources/Sounds`u bulur —
/// `Bundle.module` yerine (bu hedef SwiftPM kaynak paketlemesi kullanmıyor,
/// bkz. `SoundFeedback.swift` gerekçesi), tıpkı kurulu `.app`in
/// `Contents/Resources/Sounds`i bulacağı gibi gerçek dosyaları okuyoruz.
private func realSoundsDirectory(file: String = #filePath) -> URL {
    var url = URL(fileURLWithPath: file)
    url.deleteLastPathComponent() // BundledSoundPlayerTests.swift
    url.deleteLastPathComponent() // Tests/StashTests
    url.deleteLastPathComponent() // Tests
    return url.appendingPathComponent("Sources/Stash/Resources/Sounds", isDirectory: true)
}

@MainActor @Test func realBundledFilesLoadWithoutCrashing() {
    let player = BundledSoundPlayer(resourceDirectory: realSoundsDirectory())
    #expect(player.isCapturedLoaded)
    #expect(player.isPastedLoaded)
}

// MARK: - Eksik/yanlış konum: sessizlik, çökme yok, sistem sesine geri dönüş yok

@MainActor @Test func aMissingResourceDirectoryLoadsNothing() {
    let player = BundledSoundPlayer(resourceDirectory: nil)
    #expect(!player.isCapturedLoaded)
    #expect(!player.isPastedLoaded)
}

@MainActor @Test func aDirectoryWithoutTheExpectedFilesLoadsNothing() {
    let empty = FileManager.default.temporaryDirectory
        .appendingPathComponent("stash-sound-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }

    let player = BundledSoundPlayer(resourceDirectory: empty)
    #expect(!player.isCapturedLoaded)
    #expect(!player.isPastedLoaded)
}

@MainActor @Test func playingWithNothingLoadedNeverCrashesAndStaysSilent() {
    // Gerçek çöküş riski `NSSound(contentsOf:)` yerine `play()`in nil
    // üzerinde güvenle no-op olmasında; burada bunu doğruluyoruz — hiçbir
    // ses çalınmıyor çünkü `captured`/`pasted` zaten nil.
    let player = BundledSoundPlayer(resourceDirectory: nil)
    player.play(.captured)
    player.play(.pasted)
}
