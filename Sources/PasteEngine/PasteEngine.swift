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

    public init(pasteboard: PasteWriting, keystrokes: KeystrokeSending) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    public func paste(text: String, filters: [PasteFilter]) -> PasteOutcome {
        pasteboard.writeText(apply(filters, to: text),
                             plainOnly: filters.contains(.plainText))
        return deliver()
    }

    public func paste(imageData: Data) -> PasteOutcome {
        pasteboard.writeImage(imageData)
        return deliver()
    }

    private func deliver() -> PasteOutcome {
        guard keystrokes.isTrusted else { return .copiedOnlyNoAccessibilityPermission }
        return keystrokes.sendCommandV() ? .pastedIntoFrontmostApp : .copiedOnlyKeystrokeFailed
    }
}
