import AppKit
import Testing
import Foundation
@testable import PasteEngine

// Bu dosya `FakePasteboardWriter` kullanmıyor, GERÇEK bir `NSPasteboard`
// kullanıyor — ama `.general` değil, adı her testte tekil üretilen bir
// pano (bkz. `SystemPasteboardRealClipboardTests.swift`teki aynı desen):
// asıl sorduğumuz soru "hangi temsili sistemin kendi okuyucusu seçer"
// olduğu için, bunu bir sahteyle kanıtlayamayız — sahte, `readObjects`in
// gerçek karar mantığını hiç çalıştırmaz.
private func freshPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("social.selin.stash.test.\(UUID().uuidString)"))
}

/// Gerçekten NSImage tarafından çözülebilen küçük bir PNG. `Data([1, 2, 3])`
/// gibi rastgele baytlar `readObjects(forClasses: [NSImage.self])`in
/// sessizce boş dönmesine yol açar (geçersiz görsel verisi) — bu da
/// "hangi temsili görsel-yetkin bir okuyucu alır" sorusunu yanlış
/// cevaplandırabilir. Gerçek bir görüntüleyicinin göreceği gibi gerçek
/// baytlarla test etmek şart.
private func realPNGData() -> Data {
    let size = NSSize(width: 1, height: 1)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    let tiff = image.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

@Test func writingAnImageClipPutsImageDataAFileURLAndATextPathOnThePasteboard() throws {
    let pb = freshPasteboard()
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("stash-paste-test-\(UUID().uuidString).png")
    let png = realPNGData()
    try png.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let writer = SystemPasteboardWriter(pb)
    writer.writeImage(png, fileURL: tmp)

    // Terminal gibi metin-yalnız bir hedefin alacağı yol: budanmamış,
    // gerçek POSIX yolu.
    #expect(pb.string(forType: .string) == tmp.path)
    // Finder'ın yükleme alanı gibi dosya-URL'i anlayan bir hedefin alacağı:
    // gerçek dosyayı işaret eden bir URL, salt metin değil.
    let urls = pb.readObjects(forClasses: [NSURL.self],
                              options: [.urlReadingFileURLsOnly: true]) as? [URL]
    #expect(urls == [tmp])
    // Notlar/Mail gibi görsel kabul eden bir hedefin alacağı: ham baytlar.
    #expect(pb.data(forType: .png) == png)
}

@Test func anImageCapableDestinationTakesTheImageRepresentationNotThePath() throws {
    // Görsel kabul eden gerçek bir hedef (Notlar, Mail, Preview) kendi
    // okuyucu tercih sırasını kendisi verir ve görseli EN ÖNCE ister —
    // panonun yazım sırası bunu değiştirmez (`readObjects(forClasses:)`
    // panonun değil OKUYUCUNUN sınıf sırasına göre seçer — bu, kodu
    // yazmadan önce gerçek bir `NSPasteboard` üzerinde doğrulandı, panonun
    // tür sırasına dair bir varsayım değil). Bu test tam da o hedefin
    // gördüğünü kanıtlıyor: verilen sınıflardan biri NSImage ise ve
    // görsel geçerliyse, sonuç bir path/URL değil bir NSImage'dir.
    let pb = freshPasteboard()
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("stash-paste-test-\(UUID().uuidString).png")
    let png = realPNGData()
    try png.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    SystemPasteboardWriter(pb).writeImage(png, fileURL: tmp)

    let picked = pb.readObjects(forClasses: [NSImage.self, NSURL.self, NSString.self], options: nil)
    #expect(picked?.first is NSImage, "görsel-yetkin bir okuyucu bir path/URL değil bir NSImage almalı")
}

@Test func writingAnImageClearsAnyPreviousPasteboardContent() {
    // `writeText`teki aynı sözleşme: yeni bir yapıştırma eskisinin
    // artıklarını (ör. önceki bir metnin `.string` temsilini) arkada
    // bırakmamalı.
    let pb = freshPasteboard()
    pb.clearContents()
    pb.setString("eski içerik", forType: .string)

    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("stash-paste-test-\(UUID().uuidString).png")
    let png = realPNGData()
    try? png.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    SystemPasteboardWriter(pb).writeImage(png, fileURL: tmp)
    #expect(pb.string(forType: .string) != "eski içerik")
    #expect(pb.string(forType: .string) == tmp.path)
}
