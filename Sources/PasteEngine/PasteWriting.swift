import AppKit
import ApplicationServices
import Foundation

public protocol PasteWriting: AnyObject {
    /// Yazımdan sonraki pano `changeCount`'unu döndürür. `PasteEngine` bunu
    /// dışarı (bkz. `onWrite`) taşıyor ki kendi yazdığımız bir değişikliği
    /// panoyu yoklayan taraf (ayrı bir modülde, `PasteWriting`i hiç bilmeyen
    /// `ClipCapture`) kullanıcının yeni bir kopyalaması sanıp geri
    /// yakalamasın (I2). Panoyu asıl yazan bu tip olduğu için changeCount'u
    /// burada üretmek, çağıranın ayrıca panoyu okumasından daha güvenilir:
    /// arada başka bir değişiklik olma ihtimali sıfıra iner.
    @discardableResult func writeText(_ text: String, plainOnly: Bool) -> Int
    /// `fileURL`, görselin diskteki gerçek konumu (`Clip.imagePath`) —
    /// çağıran zaten baytları o yoldan okuduğu için burada zorunlu ve her
    /// zaman gerçek bir dosyayı gösteriyor: "dosyası olmayan bir görsel"
    /// diye bir çağrı yok, o durum (budanmış görsel) `paste`e hiç gelmeden
    /// StripModel'de eleniyor. Yazıcı yolu kendi başına türetmiyor ya da
    /// global bir yerden okumuyor — imzanın kendisi taşıyor.
    @discardableResult func writeImage(_ data: Data, fileURL: URL) -> Int
}

public protocol KeystrokeSending: AnyObject {
    var isTrusted: Bool { get }

    /// `true` once both key-down and key-up were posted; `false` if the
    /// events could not even be constructed. A silent failure here would
    /// leave the caller believing a paste happened when nothing did.
    @discardableResult
    func sendCommandV() -> Bool
}

public final class SystemPasteboardWriter: PasteWriting {
    private let pasteboard: NSPasteboard

    /// Varsayılan `.general`, üretimde kullanılan gerçek sistem panosu.
    /// Parametre var olmasının tek sebebi test izolasyonu: testler burada
    /// `.general`i sabitleseydi her `swift test` koşusu geliştiricinin o
    /// anki gerçek panosunu ezerdi (bkz. `PasteboardKit`teki `SystemPasteboard`
    /// aynı desen — adı testte tekil üretilen bir panoya işaret edebilir).
    public init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    /// `plainOnly` taşır ama burada dallanmaz: zaten yalnızca `.string`
    /// yazıyoruz, yani pano her zaten düz metin. Parametre, filtre listesinin
    /// niyetini pano katmanına taşıyor; zengin bir temsil eklenirse burası
    /// dallanacak yer olur.
    @discardableResult
    public func writeText(_ text: String, plainOnly: Bool) -> Int {
        let pb = pasteboard
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pb.changeCount
    }

    /// Terminal gibi yalnızca metin kabul eden bir hedef, ham görsel
    /// baytlarından hiçbir şey alamaz — panoda onun anlayacağı hiçbir tür
    /// yoktu, yapıştırma sessizce hiçbir şey yapmıyordu. Finder'ın kendi
    /// sözleşmesini izliyoruz: bir dosyayı kopyalayıp yapıştırınca hedef
    /// anladığını alır (Notlar görseli alır, Terminal yolu alır). Bunun
    /// için panoya üç temsil birden konuyor, TEK bir öğe üzerinde
    /// (`clearContents` sonrası `setData`/`setString` art arda çağrıları
    /// aynı öğeye tür ekler, üstüne yazmaz) — böylece hangi temsili hangi
    /// hedefin alacağı panoda BULUNAN türlere, hedefin kendi tercihine
    /// kalır, ikisi arasında seçim yapmamıza gerek kalmaz.
    ///
    /// Sıra (görsel → dosya URL'i → düz metin yol) rastgele değil: gerçek
    /// bir NSPasteboard üzerinde ölçüldü (bkz. `SystemPasteboardWriterTests`
    /// ve orada anlatılan deney) — `readObjects(forClasses:)` gibi modern
    /// okuyucular kendi sınıf sırasına göre seçim yapıyor, panonun yazım
    /// sırasına bakmıyor; yine de `NSPasteboard.types`in "en tercih edilen
    /// ÖNCE" sözleşmesine (Apple'ın `declareTypes:owner:` dokümantasyonu)
    /// ve panonun kendi tür sırasına bakan eski/basit okuyuculara karşı en
    /// zengin temsili önce yazmak tek güvenli seçim — asla tersini varsaymadık.
    @discardableResult
    public func writeImage(_ data: Data, fileURL: URL) -> Int {
        let pb = pasteboard
        pb.clearContents()
        pb.setData(data, forType: .png)
        pb.setString(fileURL.absoluteString, forType: .fileURL)
        pb.setString(fileURL.path, forType: .string)
        return pb.changeCount
    }
}

public final class SystemKeystrokeSender: KeystrokeSending {
    public init() {}

    /// Her yapıştırmadan önce bakıyoruz: kullanıcı izni Sistem Ayarları'ndan
    /// sonradan geri alabilir ve uygulama bunu başka türlü öğrenemez.
    public var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    public func sendCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
