import Testing
import Foundation
@testable import StashCore

// Ses özelliğinden ÖNCE kaydedilmiş bir ayarlar blob'unda `soundsEnabled`
// anahtarı hiç yok. Sentezlenmiş bir `Decodable` burada tüm decode'u
// düşürürdü — `Settings.load` sonra sessizce `.defaults`e düşer ve sahibin
// kısayolu, filtreleri, kara listesi hiç sebepsiz sıfırlanırdı. `Settings`in
// elle yazılmış `init(from:)`i eksik anahtarı AÇIK'a düşürerek bunu önlüyor
// (görev kuralı 5: "Default it on").

@Test func decodingAnOldSettingsBlobWithoutTheSoundsKeyDefaultsItToOn() throws {
    let legacyJSON = """
    {
        "combo": {"keyCode": 9, "modifiers": 1048576},
        "activeFilters": ["plainText"],
        "blockedBundleIDs": ["com.1password.1password"]
    }
    """
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(legacyJSON.utf8))
    #expect(decoded.soundsEnabled == true)
    // Diğer alanlar bu arada bozulmamalı — eksik anahtar sadece kendi
    // varsayılanına düşmeli, geri kalan decode'u etkilememeli.
    #expect(decoded.blockedBundleIDs == ["com.1password.1password"])
}

@Test func decodingASettingsBlobWithTheSoundsKeyExplicitlyOffRespectsIt() throws {
    let json = """
    {
        "combo": {"keyCode": 9, "modifiers": 1048576},
        "activeFilters": ["plainText"],
        "blockedBundleIDs": [],
        "soundsEnabled": false
    }
    """
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    #expect(decoded.soundsEnabled == false)
}

@Test func roundTrippingThroughEncodeAndDecodePreservesSoundsEnabled() throws {
    var settings = Settings.defaults
    settings.soundsEnabled = false
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)
    #expect(decoded.soundsEnabled == false)
}

@Test func defaultsHaveSoundsEnabled() {
    #expect(Settings.defaults.soundsEnabled == true)
}
