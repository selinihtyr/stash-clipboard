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
        guard text.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) else { return false }
        // Luhn olmadan bu, aynı uzunluktaki her rakam dizisini (ISBN-13,
        // kargo takip numarası, fatura kimliği) kart sanıyordu — "bu bir
        // kart" iddiası kart olmayan şeyler için yanlış çıkıyordu
        // (fix round 1, bulgu 2). Luhn-geçerli ama kart olmayan bir dizi
        // yine de maskelenir; bu güvenli yön, sorun değil.
        return isLuhnValid(digits)
    }

    /// Standart Luhn sağlaması: sağdan başlayıp her ikinci haneyi ikiye
    /// katlar, 9'dan büyükse 9 çıkarır, toplam 10'a bölünüyorsa geçerlidir.
    static func isLuhnValid(_ digits: String) -> Bool {
        var sum = 0
        var shouldDouble = false
        for char in digits.reversed() {
            guard let value = char.wholeNumberValue else { return false }
            var doubled = value
            if shouldDouble {
                doubled *= 2
                if doubled > 9 { doubled -= 9 }
            }
            sum += doubled
            shouldDouble.toggle()
        }
        return sum > 0 && sum % 10 == 0
    }

    /// Yol/URL/DSN ayraçları: dosya yolu "/", DSN şema ("postgres://"),
    /// kullanıcı@host ("user@localhost"), host:port ("localhost:5432") ve
    /// uzantı/alan adı ("IMG_...png", "localhost") hep bu dört karakterden
    /// birini kullanır. Gerçek API anahtarları ve oturum jetonları (ör.
    /// "sk-ant-api03-…", "ghp_…") yalnızca harf/rakam ve bazen "-"/"_"
    /// içerir, bunları hiç kullanmaz — bu yüzden bu karakter kümesi, "yapılan-
    /// dırılmış bir tanımlayıcı" ile "opak bir jeton"u ayırmak için isabetli
    /// bir sinyal (I4, fix round 1'in ardından ikinci tur: dosya yolu, git
    /// dalı adı — "feat/stash-v1-…" — ve DSN artık maskelenmiyor). 40
    /// karakterlik onaltılık bir git SHA'sı bu karakterlerin hiçbirini
    /// içermediği için bu elemeden geçer ve hâlâ maskelenir — bilinçli,
    /// kabul edilebilir bir maliyet olarak duruyor.
    private static let structuralDelimiters = Set("/:@.")

    static func isHighEntropyToken(_ text: String) -> Bool {
        // Tek parça, uzun, hem harf hem rakam içeren diziler: API anahtarları
        // ve oturum jetonları böyle görünür, normal cümleler görünmez.
        guard !text.contains(" "), text.count >= 24 else { return false }
        guard !text.contains(where: structuralDelimiters.contains) else { return false }
        let hasLetter = text.contains(where: \.isLetter)
        let hasDigit = text.contains(where: \.isNumber)
        guard hasLetter, hasDigit else { return false }
        let alphabet = Set(text.lowercased())
        return alphabet.count >= 12
    }
}
