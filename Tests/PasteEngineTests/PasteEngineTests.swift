import Testing
import Foundation
import Filters
@testable import PasteEngine

final class FakePasteboardWriter: PasteWriting {
    var lastText: String?
    var lastPlainOnly = false
    var lastImage: Data?
    /// Gerçek `NSPasteboard.changeCount` gibi her yazımda ilerler; I2'nin
    /// `onWrite` kancasının doğru değeri taşıdığını test edebilmek için.
    var changeCount = 0
    func writeText(_ text: String, plainOnly: Bool) -> Int {
        lastText = text; lastPlainOnly = plainOnly
        changeCount += 1
        return changeCount
    }
    func writeImage(_ data: Data) -> Int {
        lastImage = data
        changeCount += 1
        return changeCount
    }
}

final class FakeKeystrokes: KeystrokeSending {
    var isTrusted = true
    var sentCount = 0
    var succeeds = true
    func sendCommandV() -> Bool {
        sentCount += 1
        return succeeds
    }
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

@Test func keystrokeFailureLeavesTheCopyIntactAndSaysSo() {
    // İzin var ama sentetik ⌘V gönderilemedi: içerik panoda kalmalı ve
    // sonuç bunu ayırt etmeli, aksi halde kullanıcı hiçbir şey olmadığını
    // sanır.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.succeeds = false
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(text: "merhaba", filters: [])
    #expect(pb.lastText == "merhaba")
    #expect(outcome == .copiedOnlyKeystrokeFailed)
}

@Test func onWriteReportsTheChangeCountProducedByTheWrite() {
    // I2: bunu dinleyen taraf (bkz. AppDelegate) kendi yazdığı değişikliği
    // ClipCapture'a "bunu atla" diye iletiyor. Yanlış ya da eski bir sayı
    // taşırsa ya kendi yazdığımızı yakalarız (I2'nin ta kendisi) ya da
    // ardından gelen gerçek bir kopyalamayı yanlışlıkla atlarız.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    var reported: [Int] = []
    let engine = PasteEngine(pasteboard: pb, keystrokes: keys)
    engine.onWrite = { reported.append($0) }
    _ = engine.paste(text: "bir", filters: [])
    _ = engine.paste(imageData: Data([1, 2, 3]))
    #expect(reported == [pb.changeCount - 1, pb.changeCount])
}

@Test func imagesGoThroughTheSamePermissionLogic() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(imageData: Data([1, 2, 3]))
    #expect(pb.lastImage == Data([1, 2, 3]))
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}
