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

/// Testlerin çoğu odağı gerçekten geri vermekle ilgilenmiyor — `proceed`u
/// hemen çağıran bu, "restoreFocus'u atlayıp deliver'a geç" isteyen bir
/// çağıranın API'de bunu yapabileceği bir yol OLMADIĞINI kanıtlıyor: tek
/// yol budur, ve o da engine'in kendisi tarafından çağrılıyor.
func immediateFocusRestoration(_ proceed: @escaping () -> Void) { proceed() }

/// paste(...)'in senkron bir dönüş değeri kalmadığı için testler sonucu
/// completion kancasına yakalıyor. `immediateFocusRestoration` senkron
/// olduğu sürece tüm zincir (yaz → restoreFocus → deliver → completion)
/// aynı çağrı içinde biter, bu yüzden aşağıdaki #expect'ler hâlâ hemen
/// ardından güvenle okunabiliyor.
@discardableResult
func syncPaste(_ engine: PasteEngine, text: String, filters: [PasteFilter] = []) -> PasteOutcome {
    var result: PasteOutcome!
    engine.paste(text: text, filters: filters, restoreFocus: immediateFocusRestoration) { result = $0 }
    return result
}

@discardableResult
func syncPaste(_ engine: PasteEngine, imageData: Data) -> PasteOutcome {
    var result: PasteOutcome!
    engine.paste(imageData: imageData, restoreFocus: immediateFocusRestoration) { result = $0 }
    return result
}

@Test func pastingWritesToThePasteboardThenSendsCommandV() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    let outcome = syncPaste(PasteEngine(pasteboard: pb, keystrokes: keys), text: "merhaba")
    #expect(pb.lastText == "merhaba")
    #expect(keys.sentCount == 1)
    #expect(outcome == .pastedIntoFrontmostApp)
}

@Test func withoutAccessibilityPermissionItCopiesAndSaysSo() {
    // İzin yoksa uygulama çalışmaya devam etmeli; sessizce hiçbir şey
    // yapmamak en kötü davranış olurdu.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = syncPaste(PasteEngine(pasteboard: pb, keystrokes: keys), text: "merhaba")
    #expect(pb.lastText == "merhaba")
    #expect(keys.sentCount == 0)
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}

@Test func filtersRunBeforeTheTextReachesThePasteboard() {
    let pb = FakePasteboardWriter()
    syncPaste(PasteEngine(pasteboard: pb, keystrokes: FakeKeystrokes()),
             text: "  a   b  ", filters: [.collapseWhitespace])
    #expect(pb.lastText == "a b")
}

@Test func plainTextFilterAsksThePasteboardForPlainOnly() {
    // .plainText metni değiştirmez; anlamı zengin temsilleri yazmamaktır,
    // ve bu karar pano katmanında verilir.
    let pb = FakePasteboardWriter()
    syncPaste(PasteEngine(pasteboard: pb, keystrokes: FakeKeystrokes()),
             text: "kalın metin", filters: [.plainText])
    #expect(pb.lastPlainOnly == true)
}

@Test func keystrokeFailureLeavesTheCopyIntactAndSaysSo() {
    // İzin var ama sentetik ⌘V gönderilemedi: içerik panoda kalmalı ve
    // sonuç bunu ayırt etmeli, aksi halde kullanıcı hiçbir şey olmadığını
    // sanır.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.succeeds = false
    let outcome = syncPaste(PasteEngine(pasteboard: pb, keystrokes: keys), text: "merhaba")
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
    syncPaste(engine, text: "bir")
    syncPaste(engine, imageData: Data([1, 2, 3]))
    #expect(reported == [pb.changeCount - 1, pb.changeCount])
}

@Test func imagesGoThroughTheSamePermissionLogic() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = syncPaste(PasteEngine(pasteboard: pb, keystrokes: keys), imageData: Data([1, 2, 3]))
    #expect(pb.lastImage == Data([1, 2, 3]))
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}

// MARK: - Odak geri verme sırası (bkz. PasteEngine.FocusRestoration gerekçesi)
//
// Kritik hata buradaydı: sentetik ⌘V, şerit paneli hâlâ key window iken
// gönderiliyordu, tuş kendi panelimize düşüyordu. Aşağıdaki testler ordering'i
// doğruluyor — write → restoreFocus → (yalnızca proceed çağrılınca) deliver.

/// `restoreFocus`u hiç çağırmayan bir odak geri verici: deliver'ın GERÇEKTEN
/// bu kancadan geçmeden asla tetiklenmediğini kanıtlıyor. Çağrılmazsa ne
/// tuş gönderilir ne de completion çağrılır.
@Test func deliverNeverHappensIfRestoreFocusNeverCallsProceed() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    var completionCalled = false
    PasteEngine(pasteboard: pb, keystrokes: keys)
        .paste(text: "merhaba", filters: [], restoreFocus: { _ in /* proceed çağrılmıyor */ }) { _ in
            completionCalled = true
        }
    #expect(pb.lastText == "merhaba", "yazma restoreFocus'tan ÖNCE olmalı")
    #expect(keys.sentCount == 0, "restoreFocus proceed'i çağırmadıysa tuş asla gitmemeli")
    #expect(completionCalled == false)
}

@Test func writeHappensBeforeRestoreFocusIsInvoked() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    var textOnPasteboardWhenRestoreFocusRan: String?
    PasteEngine(pasteboard: pb, keystrokes: keys)
        .paste(text: "merhaba", filters: [], restoreFocus: { proceed in
            textOnPasteboardWhenRestoreFocusRan = pb.lastText
            proceed()
        }) { _ in }
    #expect(textOnPasteboardWhenRestoreFocusRan == "merhaba")
}

@Test func keystrokeIsPostedOnlyAfterRestoreFocusCallsProceed() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    var sentCountWhileInsideRestoreFocus = -1
    PasteEngine(pasteboard: pb, keystrokes: keys)
        .paste(text: "merhaba", filters: [], restoreFocus: { proceed in
            // Kancanın kendisi çalışırken, proceed'i henüz çağırmadan: tuş
            // hâlâ gönderilmemiş olmalı — sıra budur, aksi halde eski hata.
            sentCountWhileInsideRestoreFocus = keys.sentCount
            proceed()
        }) { _ in }
    #expect(sentCountWhileInsideRestoreFocus == 0)
    #expect(keys.sentCount == 1)
}

@Test func deferredRestoreFocusStillDeliversTheOutcome() {
    // Gerçek dünyada restoreFocus asenkron (panel kapanıp bir sonraki
    // run loop turunda proceed çağrılıyor) — engine bunu beklemeli, aynı
    // turda deliver'a zorlamamalı.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    var storedProceed: (() -> Void)?
    var outcome: PasteOutcome?
    PasteEngine(pasteboard: pb, keystrokes: keys)
        .paste(text: "merhaba", filters: [], restoreFocus: { proceed in storedProceed = proceed }) {
            outcome = $0
        }
    #expect(keys.sentCount == 0)
    #expect(outcome == nil)
    storedProceed?()
    #expect(keys.sentCount == 1)
    #expect(outcome == .pastedIntoFrontmostApp)
}

@Test func imagePasteFollowsTheSameRestoreFocusOrdering() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    var sentCountWhileInsideRestoreFocus = -1
    PasteEngine(pasteboard: pb, keystrokes: keys)
        .paste(imageData: Data([1, 2, 3]), restoreFocus: { proceed in
            sentCountWhileInsideRestoreFocus = keys.sentCount
            proceed()
        }) { _ in }
    #expect(sentCountWhileInsideRestoreFocus == 0)
    #expect(keys.sentCount == 1)
}
