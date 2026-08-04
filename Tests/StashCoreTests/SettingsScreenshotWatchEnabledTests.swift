import Testing
import Foundation
@testable import StashCore

// Bu özellikten ÖNCE kaydedilmiş bir ayarlar blob'unda `screenshotWatchEnabled`
// anahtarı hiç yok. `SettingsSoundsEnabledTests`in aynı senaryosunun tam
// tersi bir varsayılanla: eksik anahtar burada KAPALI'ya düşmeli — bu
// özellik açılınca bir TCC izin istemi tetikliyor (görev kuralı 8), eski bir
// ayarlar dosyasını sessizce yükseltip kullanıcıyı hiç istemediği bir izin
// istemiyle karşılaştırmak yanlış olurdu.

@Test func decodingAnOldSettingsBlobWithoutTheScreenshotWatchKeyDefaultsItToOff() throws {
    let legacyJSON = """
    {
        "combo": {"keyCode": 9, "modifiers": 1048576},
        "activeFilters": ["plainText"],
        "blockedBundleIDs": ["com.1password.1password"],
        "soundsEnabled": true
    }
    """
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(legacyJSON.utf8))
    #expect(decoded.screenshotWatchEnabled == false)
    // Diğer alanlar bu arada bozulmamalı.
    #expect(decoded.blockedBundleIDs == ["com.1password.1password"])
    #expect(decoded.soundsEnabled == true)
}

@Test func decodingASettingsBlobWithTheScreenshotWatchKeyExplicitlyOnRespectsIt() throws {
    let json = """
    {
        "combo": {"keyCode": 9, "modifiers": 1048576},
        "activeFilters": ["plainText"],
        "blockedBundleIDs": [],
        "soundsEnabled": true,
        "screenshotWatchEnabled": true
    }
    """
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    #expect(decoded.screenshotWatchEnabled == true)
}

@Test func roundTrippingThroughEncodeAndDecodePreservesScreenshotWatchEnabled() throws {
    var settings = Settings.defaults
    settings.screenshotWatchEnabled = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)
    #expect(decoded.screenshotWatchEnabled == true)
}

@Test func defaultsHaveScreenshotWatchDisabled() {
    #expect(Settings.defaults.screenshotWatchEnabled == false)
}
