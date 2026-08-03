import Testing
import Foundation
import Filters
@testable import PasteEngine

final class FakePasteboardWriter: PasteWriting {
    var lastText: String?
    var lastPlainOnly = false
    var lastImage: Data?
    func writeText(_ text: String, plainOnly: Bool) { lastText = text; lastPlainOnly = plainOnly }
    func writeImage(_ data: Data) { lastImage = data }
}

final class FakeKeystrokes: KeystrokeSending {
    var isTrusted = true
    var sentCount = 0
    func sendCommandV() { sentCount += 1 }
}

@Test func pastingWritesToThePasteboardThenSendsCommandV() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(text: "merhaba", filters: [])
    #expect(pb.lastText == "merhaba")
    #expect(keys.sentCount == 1)
    #expect(outcome == .pastedIntoFrontmostApp)
}

@Test func withoutAccessibilityPermissionItCopiesAndSaysSo() {
    // İzin yoksa uygulama çalışmaya devam etmeli; sessizce hiçbir şey
    // yapmamak en kötü davranış olurdu.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(text: "merhaba", filters: [])
    #expect(pb.lastText == "merhaba")
    #expect(keys.sentCount == 0)
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}

@Test func filtersRunBeforeTheTextReachesThePasteboard() {
    let pb = FakePasteboardWriter()
    _ = PasteEngine(pasteboard: pb, keystrokes: FakeKeystrokes())
        .paste(text: "  a   b  ", filters: [.collapseWhitespace])
    #expect(pb.lastText == "a b")
}

@Test func plainTextFilterAsksThePasteboardForPlainOnly() {
    // .plainText metni değiştirmez; anlamı zengin temsilleri yazmamaktır,
    // ve bu karar pano katmanında verilir.
    let pb = FakePasteboardWriter()
    _ = PasteEngine(pasteboard: pb, keystrokes: FakeKeystrokes())
        .paste(text: "kalın metin", filters: [.plainText])
    #expect(pb.lastPlainOnly == true)
}

@Test func imagesGoThroughTheSamePermissionLogic() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(imageData: Data([1, 2, 3]))
    #expect(pb.lastImage == Data([1, 2, 3]))
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}
