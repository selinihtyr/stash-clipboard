import Testing
@testable import Stash

// C4: README "Ayarlar'dan başka uygulama da eklenebilir" diyordu ama
// blockedBundleIDs'in tek mutasyonu remove(id:) idi — Ekle diye bir kontrol
// yoktu. Bu testler, SettingsView'dan koparılmış saf karar mantığını
// (reconcileHotKeyChange'deki gibi) sınıyor; fonksiyon bugünkü kodda hiç
// yok, bu yüzden bu dosya derlenmeden bile kırmızıdır.

@Test func blankBundleIDIsRejectedWithAVisibleReason() {
    #expect(validateBlockedBundleID("   ", existing: [])
        == .invalid(reason: "Bundle ID can't be empty."))
}

@Test func aPlausibleReverseDNSBundleIDIsAccepted() {
    // C4, ikinci tur: kabul edilen değer küçük harfe normalize edilir (bkz.
    // validInputIsNormalizedToLowercase) — girdiğin biçim korunmuyor.
    #expect(validateBlockedBundleID("com.apple.Notes", existing: [])
        == .valid("com.apple.notes"))
}

@Test func inputIsTrimmedBeforeValidating() {
    #expect(validateBlockedBundleID("  com.apple.Notes  ", existing: [])
        == .valid("com.apple.notes"))
}

// C4, ikinci tur: "COM.APPLE.NOTES" ayrı, geçerli bir girdi olarak kabul
// ediliyordu ama ClipCapture Set.contains ile karşılaştırdığı için hiçbir
// zaman gerçek "com.apple.notes" kopyalarını engellemiyordu — kullanıcı bir
// uygulamayı engellediğini SANIYORDU. Depolama ve karşılaştırma artık tutarlı
// şekilde küçük harfe normalize ediliyor.

@Test func validInputIsNormalizedToLowercase() {
    #expect(validateBlockedBundleID("COM.APPLE.NOTES", existing: [])
        == .valid("com.apple.notes"))
}

@Test func aDuplicateThatDiffersOnlyByCaseIsRejectedNotAddedAsASecondEntry() {
    guard case .invalid = validateBlockedBundleID(
        "COM.APPLE.NOTES", existing: ["com.apple.notes"]) else {
        Issue.record("yalnızca büyük/küçük harf farkı olan bir tekrar eklenmemeliydi")
        return
    }
}

@Test func anUnderscoreInABundleIDComponentIsAccepted() {
    // Kurallı değil ama gerçek: bazı uygulamalar ters etki alanında alt
    // çizgi kullanır (ör. "com.my_company.app") — bunu implausible diye
    // reddetmek gerçek bir bundle ID'yi kullanıcının elinden alır.
    #expect(validateBlockedBundleID("com.my_company.app", existing: [])
        == .valid("com.my_company.app"))
}

@Test func aSingleWordWithNoDotIsRejectedAsImplausible() {
    // "notepad" hiçbir gerçek bundle ID'nin şeklinde değil; boş bırakmaktan
    // hiç farkı yok — sessizce kabul etmek "her yazdığın eklenir" der.
    guard case .invalid = validateBlockedBundleID("notepad", existing: []) else {
        Issue.record("tek kelimelik girdi kabul edilmemeliydi")
        return
    }
}

@Test func inputWithSpacesIsRejectedAsImplausible() {
    guard case .invalid = validateBlockedBundleID("com apple notes", existing: []) else {
        Issue.record("boşluklu girdi kabul edilmemeliydi")
        return
    }
}

@Test func aBundleIDAlreadyOnTheListIsRejected() {
    guard case .invalid = validateBlockedBundleID(
        "com.apple.Notes", existing: ["com.apple.Notes"]) else {
        Issue.record("zaten listede olan tekrar eklenmemeliydi")
        return
    }
}
