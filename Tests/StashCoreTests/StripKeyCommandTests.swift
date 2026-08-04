import Testing
import AppKit
@testable import StashCore

@Test func arrowKeysMoveTheSelection() {
    #expect(stripCommand(keyCode: 123, characters: nil, modifiers: []) == .moveLeft)
    #expect(stripCommand(keyCode: 124, characters: nil, modifiers: []) == .moveRight)
}

@Test func returnPastesAndOptionReturnPastesFiltered() {
    #expect(stripCommand(keyCode: 36, characters: "\r", modifiers: []) == .paste(filtered: false))
    #expect(stripCommand(keyCode: 36, characters: "\r", modifiers: [.option]) == .paste(filtered: true))
}

@Test func commandDigitsPasteByPosition() {
    #expect(stripCommand(keyCode: 18, characters: "1", modifiers: [.command]) == .pasteIndex(0))
    #expect(stripCommand(keyCode: 26, characters: "9", modifiers: [.command]) == .pasteIndex(8))
}

@Test func controlPPins() {
    #expect(stripCommand(keyCode: 35, characters: "p", modifiers: [.control]) == .togglePin)
}

@Test func controlSMovesToAShelf() {
    #expect(stripCommand(keyCode: 1, characters: "s", modifiers: [.control]) == .moveToShelf)
}

@Test func plainCharactersBecomeSearchInput() {
    #expect(stripCommand(keyCode: 0, characters: "a", modifiers: []) == .type("a"))
}

@Test func modifiedCharactersAreNotSearchInput() {
    // ⌘A "hepsini seç" olabilir; arama alanına 'a' yazmak yanlış olurdu.
    #expect(stripCommand(keyCode: 0, characters: "a", modifiers: [.command]) != .type("a"))
}

@Test func escapeDismisses() {
    #expect(stripCommand(keyCode: 53, characters: nil, modifiers: []) == .dismiss)
}

// Delete tuşu önce kart siliyordu (Adım 3); arama açıkken bu davranış
// harf silmeyi imkansız kılıyordu. Adım 5'te Delete arama metnini siler,
// kart silme ⌘⌫'e taşınır.
@Test func deleteEditsTheSearchTextAndCommandDeleteRemovesTheCard() {
    #expect(stripCommand(keyCode: 51, characters: nil, modifiers: []) == .backspace)
    #expect(stripCommand(keyCode: 51, characters: nil, modifiers: [.command]) == .delete)
}

@Test func arrowKeysNeverLeakIntoTheSearchText() {
    // AppKit ok/fonksiyon tuşlarını U+F700 aralığındaki karakterlerle bildirir.
    // Yukarı/aşağı eşlenmediği için bunlar `.type`'a düşüp arama kutusuna
    // görünmeyen çöp yazıyordu (kullanıcı kutulu soru işareti görüyordu).
    let up = Character(UnicodeScalar(0xF700)!)      // NSUpArrowFunctionKey
    let down = Character(UnicodeScalar(0xF701)!)    // NSDownArrowFunctionKey
    #expect(stripCommand(keyCode: 126, characters: String(up), modifiers: []) == nil)
    #expect(stripCommand(keyCode: 125, characters: String(down), modifiers: []) == nil)
}

@Test func functionAndControlKeysAreNotTypable() {
    let f1 = Character(UnicodeScalar(0xF704)!)      // NSF1FunctionKey
    let pageUp = Character(UnicodeScalar(0xF72C)!)  // NSPageUpFunctionKey
    #expect(stripCommand(keyCode: 122, characters: String(f1), modifiers: []) == nil)
    #expect(stripCommand(keyCode: 116, characters: String(pageUp), modifiers: []) == nil)
    #expect(stripCommand(keyCode: 48, characters: "\t", modifiers: []) == .nextTab)
}

@Test func ordinaryTypingStillReachesTheSearchField() {
    #expect(stripCommand(keyCode: 0, characters: "a", modifiers: []) == .type("a"))
    #expect(stripCommand(keyCode: 0, characters: "ş", modifiers: []) == .type("ş"))
    #expect(stripCommand(keyCode: 0, characters: "A", modifiers: [.shift]) == .type("A"))
    #expect(stripCommand(keyCode: 49, characters: " ", modifiers: []) == .type(" "))
}
