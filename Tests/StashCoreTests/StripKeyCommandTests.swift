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
