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
        // Yüksek isabetli tespitçiler ÖNCE ve yapısal muafiyetin DIŞINDA
        // çalışır (I4, ikinci tur): JWT, AWS anahtarları, vendor önekli
        // jetonlar hepsi "/", ":", "@" ya da "." içerebilir (JWT'nin kendi
        // üç nokta ayracı gibi) — yapısal kural bunları yol/URL sanıp
        // geçirirdi. Gerçek bir kimlik doğrulama biçimini tanımak, "bu
        // ayraç içeriyor" gibi genel bir sinyale güvenmekten daha güvenli.
        if isKnownCredential(trimmed) { return true }
        if looksStructural(trimmed) { return false }
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

    // MARK: - Bilinen kimlik bilgisi biçimleri (yapısal muafiyetten önce)

    /// Vendor'a özel önekler: hepsi opak, önekten sonrası harf/rakam/"-"/"_"
    /// dışında bir şey içermez — yol/URL ayracı taşımazlar, ama kısalıkları
    /// (bazıları 24 karakter genel eşiğinin altında kalabilir) ya da içlerinde
    /// tesadüfen "." geçen bir varyant genel kuraldan kaçabilir. Önek + asgari
    /// uzunluk kontrolü, uzunluk/entropi sezgisine hiç ihtiyaç duymadan
    /// bunları doğrudan yakalar.
    private static let credentialPrefixes = [
        "sk-", "sk_live_", "sk_test_", "rk_live_", "pk_live_",
        "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_",
        "glpat-", "npm_", "hf_", "dop_v1_", "shpat_", "shpss_",
        "xoxb-", "xoxp-", "xoxa-", "xoxs-", "xoxr-",
    ]

    /// Kart dışı ama gerçek dünyada karşılığı olan kimlik bilgisi biçimlerini
    /// tanır: JWT, AWS erişim anahtarı kimliği, Google API anahtarı, vendor
    /// önekli jetonlar, PEM özel anahtar bloğu, AWS gizli erişim anahtarı.
    /// Bunların hepsi "yol/URL gibi görünme" muafiyetinin ÖNÜNDE kontrol
    /// edilir çünkü ikisi de aynı ayraçları ("/" JWT'de yok ama AWS gizli
    /// anahtarında olabilir, "." JWT'de üç parçayı ayırır) taşıyabilir.
    static func isKnownCredential(_ text: String) -> Bool {
        // JWT: base64url başlık '{"'nin base64'ü olan "eyJ" ile başlar, üç
        // nokta-ayrılmış parçadan oluşur. Geliştirici panosunda başka hiçbir
        // şey bu şekle sahip değil.
        if text.range(of: #"^eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*$"#,
                      options: .regularExpression) != nil { return true }
        // AWS erişim anahtarı kimliği / geçici anahtar kimliği: sabit 20
        // karakterlik biçim.
        if text.range(of: #"^(AKIA|ASIA|AIDA|AROA|ANPA|AIPA)[0-9A-Z]{16}$"#,
                      options: .regularExpression) != nil { return true }
        // Google API anahtarı.
        if text.range(of: #"^AIza[0-9A-Za-z_-]{35}$"#, options: .regularExpression) != nil { return true }
        if credentialPrefixes.contains(where: { text.hasPrefix($0) }) && text.count >= 20 { return true }
        // PEM özel anahtar bloğu.
        if text.contains("-----BEGIN") && text.contains("PRIVATE KEY") { return true }
        // AWS gizli erişim anahtarı: tam olarak 40 karakter, base64
        // alfabesinden, hem harf hem rakam hem büyük hem küçük harf içerir.
        // Bu kadar dar bir eşleşme, yol/dal adlarıyla çakışmaz — onların tam
        // 40 karakter OLMASI, karışık büyük/küçük harf OLMASI ve rakam
        // İÇERMESİ aynı anda gerekir.
        if text.count == 40, text.range(of: #"^[A-Za-z0-9/+]{40}$"#, options: .regularExpression) != nil,
           text.contains(where: \.isNumber), text.contains(where: { $0.isLowercase }),
           text.contains(where: { $0.isUppercase }) { return true }
        return false
    }

    // MARK: - Yapısal muafiyet (yol/URL/dal adı), daraltılmış

    private static let structuralDelimiters = Set("/:@.")

    /// Bir dizenin gerçekten bir dosya yolu, URL ya da git dalı gibi
    /// GÖRÜNÜP görünmediğine karar verir — eski kural gibi "içinde ayraç
    /// var mı"ya değil, dizenin BAŞINA ve BİÇİMİNE bakar. Ayrıca ayraçla
    /// ayrılmış hiçbir parçası tek başına jeton gibi görünmemeli: aksi
    /// halde "/tmp/<jwt>" ya da "https://host/reset?token=<jwt>" gibi bir
    /// kimlik bilgisini bir yol/URL'nin İÇİNE gizlemek onu görünür kılardı
    /// — hem eski hem önceki yeni kural bunu kaçırıyordu.
    static func looksStructural(_ text: String) -> Bool {
        let pathish = text.hasPrefix("/") || text.hasPrefix("~/")
            || text.hasPrefix("./") || text.hasPrefix("../")
        let urlish = text.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*://"#,
                                options: .regularExpression) != nil
        let refish = text.range(of: #"^[A-Za-z0-9._\-]+(/[A-Za-z0-9._\-]+)+$"#,
                                options: .regularExpression) != nil
        guard pathish || urlish || refish else { return false }

        let segments = text.split(whereSeparator: { structuralDelimiters.contains($0) })
        let anyTokenShapedSegment = segments.contains { isTokenShapedSegment(String($0)) }
        return !anyTokenShapedSegment
    }

    /// Tek bir yol/URL parçasının kendi başına bir jeton gibi görünüp
    /// görünmediği — genel yüksek-entropi kuralıyla aynı eşikler, ama tek
    /// bir segmente uygulanıyor.
    private static func isTokenShapedSegment(_ segment: String) -> Bool {
        segment.count >= 24 && segment.contains(where: \.isLetter)
            && segment.contains(where: \.isNumber) && Set(segment.lowercased()).count >= 12
    }

    static func isHighEntropyToken(_ text: String) -> Bool {
        // Tek parça, uzun, hem harf hem rakam içeren diziler: API anahtarları
        // ve oturum jetonları böyle görünür, normal cümleler görünmez. Bu
        // genel kural artık ayraç içeriğine bakmıyor — o kararı yukarıdaki
        // `looksStructural` daha isabetli biçimde veriyor.
        guard !text.contains(" "), text.count >= 24 else { return false }
        let hasLetter = text.contains(where: \.isLetter)
        let hasDigit = text.contains(where: \.isNumber)
        guard hasLetter, hasDigit else { return false }
        let alphabet = Set(text.lowercased())
        return alphabet.count >= 12
    }
}
