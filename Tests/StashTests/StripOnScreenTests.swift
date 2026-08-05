import AppKit
import Testing
@testable import Stash

// Şerit açılırken önce ekranın ALTINA konup animasyonla yukarı kayıyor.
// Animasyon çalışmazsa (ekran uykudan uyandığında, "Hareketi azalt" açıkken)
// panel başlangıç konumunda kalıyor: `isVisible` true ama ekranda yok. Bu
// yüzden "açık mı" sorusunun cevabı isVisible değil, ekranla kesişim.

private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
private let stripHeight: CGFloat = 300

@Test func aStripSittingAtTheBottomOfTheScreenCountsAsShowing() {
    let shown = NSRect(x: 0, y: 0, width: 1440, height: stripHeight)
    #expect(stripIsOnScreen(panelFrame: shown, screens: [screen]))
}

@Test func aStripStuckBelowTheScreenDoesNotCountAsShowing() {
    // Tam da takılma durumu: panel görünür ama ekranın dışında. Bu "açık"
    // sayılsaydı, bir sonraki kısayol basışı onu kapatmaya çalışır ve şerit
    // bir daha hiç görünmezdi.
    let stuck = NSRect(x: 0, y: -stripHeight, width: 1440, height: stripHeight)
    #expect(stripIsOnScreen(panelFrame: stuck, screens: [screen]) == false)
}

@Test func aStripOnASecondDisplayStillCountsAsShowing() {
    let external = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
    let onExternal = NSRect(x: 1440, y: 0, width: 1920, height: stripHeight)
    #expect(stripIsOnScreen(panelFrame: onExternal, screens: [screen, external]))
}

@Test func aStripOnADisplayThatIsGoneDoesNotCountAsShowing() {
    // Harici ekran çıkarıldığında panel oraya ait koordinatlarda kalabilir;
    // bu da görünmez bir "açık" panel demek.
    let orphaned = NSRect(x: 1440, y: 0, width: 1920, height: stripHeight)
    #expect(stripIsOnScreen(panelFrame: orphaned, screens: [screen]) == false)
}
