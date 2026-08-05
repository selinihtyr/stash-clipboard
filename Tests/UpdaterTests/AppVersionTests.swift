import Testing
@testable import Updater

@Test func versionsCompareNumericallyNotAsText() {
    // Metin karşılaştırmasının sessizce yanlış cevap verdiği asıl vaka:
    // "0.10.0" < "0.9.0" derdi ve onuncu sürüm kimseye hiç önerilmezdi.
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.0")!)
    #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
    #expect(AppVersion("0.2.1")! > AppVersion("0.2.0")!)
}

@Test func tagPrefixAndMissingComponentsDoNotChangeTheVersion() {
    // Etiket "v0.2", Info.plist "0.2.0" yazar; ikisi de aynı sürüm olmalı,
    // yoksa uygulama zaten çalıştırdığı sürümü güncelleme diye önerirdi.
    #expect(AppVersion("v0.2.0") == AppVersion("0.2"))
    #expect(AppVersion("V1.5")! == AppVersion("1.5.0")!)
}

@Test func prereleaseSortsBelowTheSameStableVersion() {
    #expect(AppVersion("0.3.0-beta.1")! < AppVersion("0.3.0")!)
    #expect(AppVersion("0.3.0-beta.2")! > AppVersion("0.3.0-beta.1")!)
    // Ön sürüm etiketi, sayıların karşılaştırmasını GÖLGELEMEZ.
    #expect(AppVersion("0.4.0-beta.1")! > AppVersion("0.3.0")!)
}

@Test func buildMetadataIsIgnored() {
    #expect(AppVersion("0.2.0+build.7") == AppVersion("0.2.0"))
}

@Test func unrecognisableTagsAreRejectedRatherThanGuessed() {
    // Tanımadığımız bir etiket "yeni sürüm" sayılsaydı, kullanıcıyı ne olduğunu
    // bilmediğimiz bir binary'ye taşırdık.
    #expect(AppVersion("nightly") == nil)
    // Tarih etiketi SemVer'e göre "2026 sürümünün 08-05 ön sürümü" diye
    // okunabilir; kabul edilseydi 0.x çalıştıran herkese "yeni sürüm" diye
    // gösterilirdi.
    #expect(AppVersion("2026-08-05") == nil)
    #expect(AppVersion("1") == nil)
    #expect(AppVersion("") == nil)
    #expect(AppVersion("0.2.0.1") == nil)
    #expect(AppVersion("0.2.x") == nil)
    #expect(AppVersion("0.2.0-") == nil)
}
