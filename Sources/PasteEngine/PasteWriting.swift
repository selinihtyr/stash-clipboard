import AppKit
import ApplicationServices
import Foundation

public protocol PasteWriting: AnyObject {
    func writeText(_ text: String, plainOnly: Bool)
    func writeImage(_ data: Data)
}

public protocol KeystrokeSending: AnyObject {
    var isTrusted: Bool { get }
    func sendCommandV()
}

public final class SystemPasteboardWriter: PasteWriting {
    public init() {}

    /// `plainOnly` taşır ama burada dallanmaz: zaten yalnızca `.string`
    /// yazıyoruz, yani pano her zaten düz metin. Parametre, filtre listesinin
    /// niyetini pano katmanına taşıyor; zengin bir temsil eklenirse burası
    /// dallanacak yer olur.
    public func writeText(_ text: String, plainOnly: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
    public func writeImage(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }
}

public final class SystemKeystrokeSender: KeystrokeSending {
    public init() {}

    /// Her yapıştırmadan önce bakıyoruz: kullanıcı izni Sistem Ayarları'ndan
    /// sonradan geri alabilir ve uygulama bunu başka türlü öğrenemez.
    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
