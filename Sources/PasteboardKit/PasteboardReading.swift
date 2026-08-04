import AppKit
import Foundation

/// Panoyu protokolün arkasına alıyoruz: yakalama kararlarının tamamı saf kodla
/// test edilebilsin, testler gerçek panoyu kirletmesin.
public protocol PasteboardReading: Sendable {
    var changeCount: Int { get }
    var types: [String] { get }
    func string() -> String?
    func imageData() -> Data?
    func fileURLStrings() -> [String]?
    /// Panodaki tam web bağlantısı (şema+host+sorgu+parça dahil), varsa.
    /// `NSURL` okuyucusu `readObjects` seçeneksiz çağrıldığında hem dosya hem
    /// web URL'lerini aynı kovaya atıyordu (C1); bunu ayrı bir uç yaparak
    /// `fileURLStrings()`in artık yalnızca gerçek `file://` URL'lerini
    /// döndürmesini, bağlantıların da `.path` gibi budayan bir dönüşümden
    /// geçmeden tam metniyle taşınmasını sağlıyoruz.
    func webURLString() -> String?
}

public struct SystemPasteboard: PasteboardReading, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    public init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public var changeCount: Int { pasteboard.changeCount }
    public var types: [String] { (pasteboard.types ?? []).map(\.rawValue) }
    public func string() -> String? { pasteboard.string(forType: .string) }
    public func imageData() -> Data? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return data }
        }
        return nil
    }
    /// `.urlReadingFileURLsOnly: true` olmadan bu okuyucu bir tarayıcının
    /// bıraktığı web bağlantısını da bir `NSURL` olarak döndürüyordu; çağıran
    /// `.path`i alınca "https://example.com/articles/2026?ref=twitter#top"
    /// sessizce "/articles/2026"a düşüyor, şema/host/sorgu/parça kayboluyordu
    /// (C1). Seçenek eklemek bu uca yalnızca gerçek dosya URL'lerini bırakır.
    public func fileURLStrings() -> [String]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return nil }
        return urls.map(\.path)
    }
    /// Seçeneksiz okuma hem dosya hem web URL'lerini döndürür; burada
    /// dosyaları eleyip ilk web bağlantısının TAM metnini (`absoluteString`)
    /// veriyoruz — `.path` gibi budayan bir alana değil.
    public func webURLString() -> String? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return nil }
        return urls.first(where: { !$0.isFileURL })?.absoluteString
    }
}
