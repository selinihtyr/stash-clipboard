import Testing
@testable import Stash

// C4: README "Ayarlar'dan başka uygulama da eklenebilir" diyordu ama
// blockedBundleIDs'in tek mutasyonu remove(id:) idi — Ekle diye bir kontrol
// yoktu. Bu testler, SettingsView'dan koparılmış saf karar mantığını
// (reconcileHotKeyChange'deki gibi) sınıyor; fonksiyon bugünkü kodda hiç
// yok, bu yüzden bu dosya derlenmeden bile kırmızıdır.

@Test func blankBundleIDIsRejectedWithAVisibleReason() {
    #expect(validateBlockedBundleID("   ", existing: [])
        == .invalid(reason: "Paket kimliği boş olamaz."))
}

@Test func aPlausibleReverseDNSBundleIDIsAccepted() {
    #expect(validateBlockedBundleID("com.apple.Notes", existing: [])
        == .valid("com.apple.Notes"))
}

@Test func inputIsTrimmedBeforeValidating() {
    #expect(validateBlockedBundleID("  com.apple.Notes  ", existing: [])
        == .valid("com.apple.Notes"))
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
