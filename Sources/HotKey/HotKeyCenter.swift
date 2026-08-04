import Carbon.HIToolbox
import Foundation

public enum HotKeyError: Error, Equatable {
    case alreadyTaken
    /// `RegisterEventHotKey` başarısız olmadan `InstallEventHandler` başarısız olursa
    /// çağıran taraf bunu `alreadyTaken`dan ayırt edebilmeli: aksi halde kısayol
    /// sessizce ölü kalır — hiçbir hata görünmeden basıldığında hiçbir şey olmaz.
    case handlerInstallFailed(OSStatus)
}

/// RegisterEventHotKey kullanıyoruz, CGEventTap değil: bu API Erişilebilirlik
/// izni istemiyor, dolayısıyla uygulama izin verilmeden de açılabiliyor.
///
/// @MainActor: register/unregister çağrıları ve C geri çağırımının okuduğu `handler`
/// aynı izolasyona bağlanmadan "sadece ana iş parçacığında çağrılır" bir sözleşmeden
/// ibaret kalıyordu — hiçbir şey `register()`'ın arka planda çağrılmasını engellemiyordu.
/// Tip artık bunu derleyicide zorluyor.
@MainActor
public final class HotKeyCenter {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private static var nextID: UInt32 = 1

    public init() {}

    public func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            // Carbon bu trampoline'ı uygulamanın ana çalışma döngüsünden çağırıyor;
            // bu yüzden MainActor.assumeIsolated burada geçerli bir varsayım. `center`
            // kasıtlı olarak izolasyon içinde, opak işaretçiden yeniden kuruluyor —
            // dışarıdan Sendable olmayan bir referans yakalamaktan kaçınmak için.
            MainActor.assumeIsolated {
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                center.handler?()
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        guard installStatus == noErr else {
            // Kurulum başarısız oldu: handlerRef'i temizle, ama henüz hiçbir
            // sistem kaynağı (hotkey kaydı) alınmadı, unregister() gerekmiyor.
            handlerRef = nil
            self.handler = nil
            throw HotKeyError.handlerInstallFailed(installStatus)
        }

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

    isolated deinit {
        unregister()
    }
}
