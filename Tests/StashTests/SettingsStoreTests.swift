import Testing
import HotKey
import StashCore
@testable import Stash

// Fix round 2: SettingsView artık ayarları bir `@State` anlık görüntüsü
// olarak değil, AppDelegate ile paylaşılan `SettingsStore` üzerinden okuyor.
// Bu test canlı bir pencere açmadan, `AppDelegate.openSettings`'in onChange
// kapanışının yaptığı hesaplamayı (reconcile + settingsStore.settings
// ataması) küçük ölçekte tekrarlayarak ayarlar yüzeyinin bir sonraki
// okumada gerçekten çalışan kombinasyonu gösterdiğini doğruluyor —
// reddedileni değil.

private let comboA = KeyCombo(keyCode: KeyCombo.keyCodeV, modifiers: KeyCombo.command | KeyCombo.option)
private let comboB = KeyCombo(keyCode: KeyCombo.keyCodeV, modifiers: KeyCombo.command | KeyCombo.control)

@MainActor
@Test func settingsSurfaceReadsBackThePreviousComboAfterARejectedChange() {
    let initial = StashCore.Settings(combo: comboA, activeFilters: [.plainText],
                                     blockedBundleIDs: [])
    let store = SettingsStore(initial)

    // Kullanıcı comboB'yi denedi, ama Carbon kaydı reddetti (ör. başka bir
    // uygulama kapmış).
    var proposed = initial
    proposed.combo = comboB
    let outcome = reconcileHotKeyChange(from: store.settings.combo, to: proposed.combo) { combo in
        combo == comboB ? .failure(.alreadyTaken) : .success(())
    }
    var finalSettings = proposed
    if case .reverted(let combo, _) = outcome { finalSettings.combo = combo }
    store.settings = finalSettings

    // Pencere (görünür olsun ya da sonra tekrar açılsın) `store.settings`i
    // okuyor; reddedilen comboB değil, hâlâ çalışan comboA'yı görmeli.
    #expect(store.settings.combo == comboA)
    #expect(store.settings.combo != comboB)
}

@MainActor
@Test func settingsSurfaceReadsBackTheNewComboWhenRegistrationSucceeds() {
    // Karşıt durum: başarılı bir değişiklik gerçekten yansımalı, "her zaman
    // eskiyi göster" gibi tembel bir düzeltmeyle yanlışlıkla donmamalı.
    let initial = StashCore.Settings(combo: comboA, activeFilters: [.plainText],
                                     blockedBundleIDs: [])
    let store = SettingsStore(initial)

    var proposed = initial
    proposed.combo = comboB
    let outcome = reconcileHotKeyChange(from: store.settings.combo, to: proposed.combo) { _ in .success(()) }
    var finalSettings = proposed
    if case .applied(let combo) = outcome { finalSettings.combo = combo }
    store.settings = finalSettings

    #expect(store.settings.combo == comboB)
}
