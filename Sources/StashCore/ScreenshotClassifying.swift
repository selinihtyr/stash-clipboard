import CoreServices
import Foundation

/// Bir dosyanın GERÇEK bir ekran görüntüsü olup olmadığını söyler.
///
/// Dosya adı yanlış ayırt edici: yerelleştirilmiş ("Screenshot 2026-…" vs.
/// "Ekran Resmi 2026-…") ve `defaults write com.apple.screencapture name …`
/// ile kullanıcı tarafından değiştirilebilir (görev kuralı 2). macOS gerçek
/// ekran görüntülerini `screencapture` aracının kendisinin yazdığı
/// `com.apple.metadata:kMDItemIsScreenCapture` genişletilmiş özniteliğiyle
/// damgalıyor — `mdls -name kMDItemIsScreenCapture` ile doğrulandı: gerçek
/// bir ekran görüntüsünde `1`, sıradan bir PNG'de `(null)`. Bu tek güvenilir
/// ayırt edici.
///
/// Dönüş `Bool?`: `nil` "belirlenemedi" demek. Bunun iki gerçek nedeni var:
/// (1) `MDItemCreateWithURL` dosya için hiç bir Spotlight öğesi
/// döndüremiyor, (2) öznitelik henüz indekslenmemiş (bkz.
/// `ScreenshotWatcher`teki sınıflandırma-yeniden-deneme gerekçesi: elle
/// deneyle doğrulandı, bir dosyaya genişletilmiş öznitelik yazmak `mdls`in
/// onu ANINDA görmesini garanti etmiyor — `mdworker`ın dosyayı yeniden
/// indekslemesi gerekiyor, bu senkron değil). Çağıran taraf hem `false` hem
/// `nil`i "içe aktarma" olarak ele alıyor (görev kuralı 2: "belirlenemiyorsa
/// içe aktarmama yönünde hata yap") — protokolün ayrımı sadece testlerin iki
/// senaryoyu (kesin hayır / bilinmiyor) ayrı ayrı kanıtlayabilmesi için var.
public protocol ScreenshotClassifying: Sendable {
    func isScreenCapture(at url: URL) -> Bool?
}

/// `Metadata.framework` (CoreServices şemsiyesi altında) üzerinden gerçek
/// Spotlight sorgusu.
public struct SpotlightScreenshotClassifier: ScreenshotClassifying {
    public init() {}

    public func isScreenCapture(at url: URL) -> Bool? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        // "kMDItemIsScreenCapture" belgelenmemiş bir öznitelik: Metadata.framework
        // başlıklarında dışa aktarılan bir `kMDItemIsScreenCapture` sembolü YOK
        // (`MDItem.h`de aranıp doğrulandı) — literal dize olarak geçiliyor, tıpkı
        // `mdls -name kMDItemIsScreenCapture`in komut satırında yaptığı gibi.
        guard let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
