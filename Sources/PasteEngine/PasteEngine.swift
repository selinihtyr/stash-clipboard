import Filters
import Foundation

public enum PasteOutcome: Equatable {
    case pastedIntoFrontmostApp
    case copiedOnlyNoAccessibilityPermission
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
        keystrokes.sendCommandV()
        return .pastedIntoFrontmostApp
    }
}
