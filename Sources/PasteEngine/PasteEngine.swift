import Filters
import Foundation

public enum PasteOutcome: Equatable {
    case pastedIntoFrontmostApp
    case copiedOnlyNoAccessibilityPermission
    /// Permission was present but the synthetic ⌘V itself could not be
    /// posted (event construction failed). The content is safely on the
    /// pasteboard; the user still needs to press ⌘V themselves.
    case copiedOnlyKeystrokeFailed
}

public final class PasteEngine {
    private let pasteboard: PasteWriting
    private let keystrokes: KeystrokeSending

    /// Her başarılı pano yazımından hemen sonra, o yazımın ürettiği
    /// `changeCount` ile çağrılır. `PasteEngine` panoyu yoklayan tarafı
    /// (ayrı bir modülde yaşayan `ClipCapture`) hiç bilmiyor ve bilmemeli —
    /// bu kancayı kimin dinlediği tamamen çağırana kalmış (bkz.
    /// `AppDelegate`, iki modülü birbirine bağlayan tek yer). Boş bırakılırsa
    /// hiçbir şey değişmez, sadece kendi yazdığımız değişiklik normal bir
    /// kullanıcı kopyalaması gibi geri yakalanabilir hale gelir (I2).
    public var onWrite: ((Int) -> Void)?

    public init(pasteboard: PasteWriting, keystrokes: KeystrokeSending) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    public func paste(text: String, filters: [PasteFilter]) -> PasteOutcome {
        let changeCount = pasteboard.writeText(apply(filters, to: text),
                                               plainOnly: filters.contains(.plainText))
        onWrite?(changeCount)
        return deliver()
    }

    public func paste(imageData: Data) -> PasteOutcome {
        let changeCount = pasteboard.writeImage(imageData)
        onWrite?(changeCount)
        return deliver()
    }

    private func deliver() -> PasteOutcome {
        guard keystrokes.isTrusted else { return .copiedOnlyNoAccessibilityPermission }
        return keystrokes.sendCommandV() ? .pastedIntoFrontmostApp : .copiedOnlyKeystrokeFailed
    }
}
