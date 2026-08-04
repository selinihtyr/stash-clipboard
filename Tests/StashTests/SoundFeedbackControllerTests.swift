import Testing
import HotKey
import PasteEngine
import StashCore
@testable import Stash

// `soundForPasteOutcome` + `SoundFeedbackController` testleri: gerçek
// `NSSound` hiç çağrılmıyor (görev isteği), `FakeSoundPlayer` çalınan
// sesleri sadece bir diziye kaydediyor.

@MainActor
private final class FakeSoundPlayer: SoundPlaying {
    private(set) var played: [FeedbackSound] = []
    func play(_ sound: FeedbackSound) { played.append(sound) }
}

private let baseSettings = StashCore.Settings(
    combo: .defaultCombo, activeFilters: [.plainText], blockedBundleIDs: [])

// MARK: - soundForPasteOutcome: `PasteOutcome` → ses eşlemesi (görev kuralı 4)

@Test func onlyARealDeliveryMapsToThePasteSound() {
    #expect(soundForPasteOutcome(.pastedIntoFrontmostApp) == .pasted)
}

@Test func missingAccessibilityPermissionMapsToTheCopySoundNotThePasteSound() {
    // İçerik yalnızca panoya yazıldı, öndeki uygulamaya asla ulaşmadı —
    // "yapıştırıldı" sesi çalmak yalan olurdu.
    #expect(soundForPasteOutcome(.copiedOnlyNoAccessibilityPermission) == .captured)
}

@Test func aFailedKeystrokeAlsoMapsToTheCopySoundNotThePasteSound() {
    #expect(soundForPasteOutcome(.copiedOnlyKeystrokeFailed) == .captured)
}

// MARK: - SoundFeedbackController: anahtar + eşleme birlikte

@MainActor @Test func capturedPlaysTheCaptureSoundWhenTheToggleIsOn() {
    let player = FakeSoundPlayer()
    let feedback = SoundFeedbackController(settingsStore: SettingsStore(baseSettings), player: player)
    feedback.captured()
    #expect(player.played == [.captured])
}

@MainActor @Test func capturedStaysSilentWhenTheToggleIsOff() {
    var settings = baseSettings
    settings.soundsEnabled = false
    let player = FakeSoundPlayer()
    let feedback = SoundFeedbackController(settingsStore: SettingsStore(settings), player: player)
    feedback.captured()
    #expect(player.played.isEmpty)
}

@MainActor @Test func theToggleIsReadLiveNotSnapshottedAtConstruction() {
    // `SettingsStore` paylaşılan tek doğruluk kaynağı (bkz. gerekçesi) —
    // ayarlar penceresi kapanmadan anahtar kapatılırsa bir sonraki
    // yakalama/yapıştırma bunu hemen görmeli, kurulduğu andaki değere
    // takılı kalmamalı. Bu, `SettingsStore`taki `@State` anlık görüntüsü
    // hatasının aynısına düşmemek için.
    let store = SettingsStore(baseSettings) // başlangıçta açık
    let player = FakeSoundPlayer()
    let feedback = SoundFeedbackController(settingsStore: store, player: player)
    store.settings.soundsEnabled = false
    feedback.captured()
    #expect(player.played.isEmpty)
}

@MainActor @Test func pastedRespectsTheOutcomeMappingEndToEnd() {
    let player = FakeSoundPlayer()
    let feedback = SoundFeedbackController(settingsStore: SettingsStore(baseSettings), player: player)
    feedback.pasted(.pastedIntoFrontmostApp)
    feedback.pasted(.copiedOnlyNoAccessibilityPermission)
    feedback.pasted(.copiedOnlyKeystrokeFailed)
    #expect(player.played == [.pasted, .captured, .captured])
}

@MainActor @Test func pastedRespectsTheToggleToo() {
    var settings = baseSettings
    settings.soundsEnabled = false
    let player = FakeSoundPlayer()
    let feedback = SoundFeedbackController(settingsStore: SettingsStore(settings), player: player)
    feedback.pasted(.pastedIntoFrontmostApp)
    #expect(player.played.isEmpty)
}
