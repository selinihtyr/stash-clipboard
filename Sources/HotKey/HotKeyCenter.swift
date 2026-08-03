import Carbon.HIToolbox
import Foundation

public enum HotKeyError: Error, Equatable { case alreadyTaken }

/// RegisterEventHotKey kullanıyoruz, CGEventTap değil: bu API Erişilebilirlik
/// izni istemiyor, dolayısıyla uygulama izin verilmeden de açılabiliyor.
public final class HotKeyCenter {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?
    // Swift 6 sıkı eşzamanlılık denetimi statik mutable state'e itiraz ediyor;
    // burada gerçek bir veri yarışı yok (kayıt ana iş parçacığında yapılıyor,
    // sadece kimlikleri benzersiz kılmak için artan bir sayaç).
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    public init() {}

    public func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            let fire = center.handler
            DispatchQueue.main.async { MainActor.assumeIsolated { fire?() } }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x53545348 /* "STSH" */), id: Self.nextID)
        Self.nextID += 1
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            unregister()
            throw HotKeyError.alreadyTaken
        }
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        handler = nil
    }

    deinit { unregister() }
}
