import AppKit
import Testing
@testable import Stash

// "Şerit açık mı?" sorusunun cevabı üç ayrı hatadan öğrenildi ve üçü de
// kullanıcıya AYNI şekilde görünüyor: kısayol da menü de ölü, tek çare
// uygulamayı yeniden başlatmak. Sebep her seferinde panelin "açık" sayılıp
// kapatılması oldu. Bu yüzden kural burada, saf bir fonksiyonda tutuluyor.

private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
private let stripHeight: CGFloat = 300
private let shown = NSRect(x: 0, y: 0, width: 1440, height: stripHeight)

@Test func aPanelDrawnOnTheActiveSpaceIsShowing() {
    #expect(stripIsShowing(isVisible: true, isOnActiveSpace: true,
                           panelFrame: shown, screens: [screen]))
}

@Test func aPanelStrandedOnAnotherSpaceIsNotShowing() {
    // Tam ekran bir Space varken pencere sunucusu paneli tek bir Space'e
    // iliştirebiliyor: AppKit'e göre görünür, çerçevesi de ekranla kesişiyor,
    // ama kullanıcının baktığı yerde çizilmiyor. "Açık" sayılırsa bir sonraki
    // basış onu kapatır ve şerit bir daha hiç görünmez.
    #expect(stripIsShowing(isVisible: true, isOnActiveSpace: false,
                           panelFrame: shown, screens: [screen]) == false)
}

@Test func aPanelStuckBelowTheScreenIsNotShowing() {
    // Animasyon bastırıldığında (uykudan uyanma, "Hareketi azalt") panel
    // başlangıç konumunda — ekranın altında — kalıyor.
    let stuck = NSRect(x: 0, y: -stripHeight, width: 1440, height: stripHeight)
    #expect(stripIsShowing(isVisible: true, isOnActiveSpace: true,
                           panelFrame: stuck, screens: [screen]) == false)
}

@Test func aPanelThatWasNeverOrderedInIsNotShowing() {
    #expect(stripIsShowing(isVisible: false, isOnActiveSpace: true,
                           panelFrame: shown, screens: [screen]) == false)
}

@Test func theTwoFailuresCanHappenTogether() {
    // Uykudan uyanma ikisini birden üretebiliyor; biri diğerini maskelememeli.
    let stuck = NSRect(x: 0, y: -stripHeight, width: 1440, height: stripHeight)
    #expect(stripIsShowing(isVisible: true, isOnActiveSpace: false,
                           panelFrame: stuck, screens: [screen]) == false)
}
