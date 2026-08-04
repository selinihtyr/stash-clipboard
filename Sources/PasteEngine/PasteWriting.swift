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
    @discardableResult func writeImage(_ data: Data) -> Int
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
    public init() {}

    /// `plainOnly` taşır ama burada dallanmaz: zaten yalnızca `.string`
    /// yazıyoruz, yani pano her zaten düz metin. Parametre, filtre listesinin
    /// niyetini pano katmanına taşıyor; zengin bir temsil eklenirse burası
    /// dallanacak yer olur.
    @discardableResult
    public func writeText(_ text: String, plainOnly: Bool) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pb.changeCount
    }
    @discardableResult
    public func writeImage(_ data: Data) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
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
