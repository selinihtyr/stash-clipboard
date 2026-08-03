import Foundation

/// Kart içeriğinin omuz üstünden okunmasını engeller. Kayıt silinmez —
/// kullanıcı kendi verisine erişebilmeli — sadece varsayılan olarak gizlenir.
///
/// Bilerek `@MainActor` DEĞİL: SwiftUI view'lerinden (ClipCardView) senkron
/// çağrılıyor; izole olsaydı her çağrı `await` isteyip görünüm kodunu
/// gereksiz yere karmaşıklaştırırdı. Saf, durumsuz statik fonksiyonlar zaten
/// hangi iş parçacığından çağrılırsa çağrılsın güvenli.
public enum SensitivePatterns {
    public static func isSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }
        if isCardNumber(trimmed) { return true }
        return isHighEntropyToken(trimmed)
    }

    public static func mask(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCardNumber(trimmed) {
            let digits = trimmed.filter(\.isNumber)
            return "•••• " + String(digits.suffix(4))
        }
        return String(repeating: "•", count: min(trimmed.count, 24))
    }

    static func isCardNumber(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }
        // Rakam ve boşluk/tire dışında bir şey varsa kart numarası değildir.
        return text.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" }
    }

    static func isHighEntropyToken(_ text: String) -> Bool {
        // Tek parça, uzun, hem harf hem rakam içeren diziler: API anahtarları
        // ve oturum jetonları böyle görünür, normal cümleler görünmez.
        guard !text.contains(" "), text.count >= 24 else { return false }
        let hasLetter = text.contains(where: \.isLetter)
        let hasDigit = text.contains(where: \.isNumber)
        guard hasLetter, hasDigit else { return false }
        let alphabet = Set(text.lowercased())
        return alphabet.count >= 12
    }
}
