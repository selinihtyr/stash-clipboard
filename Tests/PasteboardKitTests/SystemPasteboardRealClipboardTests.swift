import AppKit
import Testing
import Foundation
@testable import PasteboardKit

// C1'in kanıtı FakePasteboard ile YAKALANAMIYOR: sahte pano `files`i
// doğrudan döndürüyor, `readObjects(forClasses:)`in gerçek NSURL
// okuyucusunu (ve onun seçeneklerini) hiç çalıştırmıyor. Bug tam da o
// okuyucunun davranışındaydı, bu yüzden burada GERÇEK bir NSPasteboard
// kullanıyoruz — ama `.general` değil, adı her testte tekil üretilen bir
// pano: kullanıcının panosuna dokunmadan sistemin gerçek NSURL okuma
// yolunu sınıyoruz.
private func freshPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("social.selin.stash.test.\(UUID().uuidString)"))
}

@MainActor @Test func aBrowserStyleWebLinkOnARealPasteboardBecomesALinkClipWithTheFullURL() {
    let pb = freshPasteboard()
    let url = URL(string: "https://example.com/articles/2026?ref=twitter#top")!
    pb.clearContents()
    // NSURL, NSPasteboardWriting'e uyar; bir tarayıcının "Bağlantıyı Kopyala"
    // eylemi de aynı yoldan (writeObjects ile bir NSURL) panoya yazar.
    pb.writeObjects([url as NSURL])

    let system = SystemPasteboard(pb)
    let capture = ClipCapture(pasteboard: system, policy: CapturePolicy())
    let clip = capture.poll(frontmostBundleID: nil)

    #expect(clip?.kind == .link)
    #expect(clip?.text == url.absoluteString)
    // Eski davranış "/articles/2026" (yalnızca path) üretiyordu; şema, host,
    // sorgu ve parçanın hâlâ orada olduğunu açıkça doğruluyoruz.
    #expect(clip?.text?.contains("ref=twitter") == true)
    #expect(clip?.text?.contains("#top") == true)
}

@MainActor @Test func distinctWebLinksOnARealPasteboardDoNotCollideOnOneHash() {
    // Reproduksiyonun ikinci yarısı: farklı çıplak-host URL'ler eskiden
    // hepsi aynı ("", kind=.file) satırına düşüp tek boş karta birleşiyordu.
    let urls = [
        URL(string: "https://apple.com")!,
        URL(string: "https://anthropic.com")!,
        URL(string: "https://github.com")!,
    ]
    var hashes: Set<String> = []
    for url in urls {
        let pb = freshPasteboard()
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        let clip = ClipCapture(pasteboard: SystemPasteboard(pb), policy: CapturePolicy())
            .poll(frontmostBundleID: nil)
        #expect(clip?.kind == .link)
        #expect(clip?.text?.isEmpty == false)
        if let hash = clip?.contentHash { hashes.insert(hash) }
    }
    #expect(hashes.count == urls.count)
}

@MainActor @Test func aGenuineFileURLOnARealPasteboardBecomesAFileClipWithAUsablePath() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("stash-c1-test-\(UUID().uuidString).txt")
    try "merhaba".write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let pb = freshPasteboard()
    pb.clearContents()
    pb.writeObjects([tmp as NSURL])

    let system = SystemPasteboard(pb)
    let capture = ClipCapture(pasteboard: system, policy: CapturePolicy())
    let clip = capture.poll(frontmostBundleID: nil)

    #expect(clip?.kind == .file)
    #expect(clip?.text == tmp.path)
    #expect(FileManager.default.fileExists(atPath: clip?.text ?? ""))
}
