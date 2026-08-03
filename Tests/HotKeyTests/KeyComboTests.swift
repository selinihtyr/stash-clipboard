import Foundation
import Testing
@testable import HotKey

@Test func defaultComboIsOptionCommandV() {
    #expect(KeyCombo.defaultCombo.displayString == "⌥⌘V")
}

@Test func displayStringOrdersModifiersTheWayMacOSDoes() {
    // macOS her yerde ⌃⌥⇧⌘ sırasını kullanır; kendi sıramızı uydurursak
    // ayarlar penceresi sistemin geri kalanından farklı görünür.
    let combo = KeyCombo(keyCode: KeyCombo.keyCodeV,
                         modifiers: KeyCombo.control | KeyCombo.option
                                  | KeyCombo.shift | KeyCombo.command)
    #expect(combo.displayString == "⌃⌥⇧⌘V")
}

@Test func combosRoundTripThroughCodableSoSettingsCanStoreThem() throws {
    let data = try JSONEncoder().encode(KeyCombo.defaultCombo)
    #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == KeyCombo.defaultCombo)
}

@Test @MainActor func registeringTheSameComboTwiceReportsItIsTaken() throws {
    // Kısayol kapılıysa sessizce ölü bir kısayol bırakmak yerine hata veriyoruz;
    // ayarlar bunu kırmızı uyarıya çevirecek.
    let first = HotKeyCenter()
    try first.register(.defaultCombo) {}
    defer { first.unregister() }
    let second = HotKeyCenter()
    #expect(throws: HotKeyError.alreadyTaken) {
        try second.register(.defaultCombo) {}
    }
}

@Test func handlerInstallFailureIsDistinguishableFromAlreadyTaken() {
    // register()'ın iki başarısızlık yolu (InstallEventHandler ve
    // RegisterEventHotKey) artık ayrı case'ler; çağıran taraf "kısayol kapılı"
    // ile "kısayol hiç kurulamadı" durumlarını ayırt edebilmeli.
    //
    // Gerçek bir InstallEventHandler başarısızlığını bu test ortamından
    // tetiklemenin Carbon'u sahtelemeden güvenilir bir yolu yok — register()'ın
    // bu yolda gerçekten handlerInstallFailed fırlattığını doğrulayan bir test
    // yazamadık. Burada doğrulanan, temsilin (enum case'lerinin) birbirinden
    // ayırt edilebilir olduğu; register()'ın gerçek dünyada bu case'e düştüğü
    // değil.
    #expect(HotKeyError.handlerInstallFailed(-50) != HotKeyError.alreadyTaken)
}
