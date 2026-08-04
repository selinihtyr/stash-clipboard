import AppKit
import Testing
@testable import Stash

// Şeritin kapanma yolları dörttür (Escape, aynı kısayola tekrar basmak,
// dışarı tıklamak, yapıştırma sonrası) ama hepsi StripPanel.dismiss()'e
// çıkar. Süzgeci temizlemek onDismiss kancasında tek bir yerde yapılırsa,
// bu dört yol da otomatik olarak temiz başlar — burada doğrulanan bu.
@MainActor
@Test func plainDismissInvokesOnDismissHandler() {
    let panel = StripPanel(contentView: NSView())
    var handlerCalled = false
    panel.onDismiss = { handlerCalled = true }

    panel.dismiss()

    #expect(handlerCalled)
}

@MainActor
@Test func escapeGoesThroughTheSameDismissAsAnyOtherPath() {
    // cancelOperation, Escape'in AppKit tarafından yönlendirildiği yol;
    // onKey devreye girmese bile dismiss()'e (ve dolayısıyla onDismiss'e)
    // ulaşmalı — ayrı bir temizleme yolu olmadığını kanıtlıyor.
    let panel = StripPanel(contentView: NSView())
    var handlerCalled = false
    panel.onDismiss = { handlerCalled = true }

    panel.cancelOperation(nil)

    #expect(handlerCalled)
}
