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

    // MARK: - Yapısal muafiyet (yol/URL/tanımlayıcı zinciri), daraltılmış

    // "_" ve "-" I4 üçüncü turda eklendi: bir dosya adı "Screenshot_2026-
    // 08-04_at_11.33.55.png" gibi kelime/tarih parçalarını bu iki karakterle
    // ayırır. Onlar ayraç SAYILMAZSA tek bir "Screenshot_2026-08-04_at_11"
    // parçası ortaya çıkar — bu, hem harf hem rakam içeren >=24 karakterlik
    // bir dize olduğu için jeton sanılır ve tüm yolun muafiyetini bozar.
    // Gerçek jetonların (AWS gizli anahtarı, JWT parçaları, rastgele base64
    // blob) alfabesi bu iki karakteri neredeyse hiç taşımaz (bkz. Monte
    // Carlo ölçümü, item 1) — bu yüzden onları ayraç sayınca zararsız
    // dosya adlarını kurtarırken gerçek kimlik bilgilerini ele vermiyoruz.
    private static let structuralDelimiters = Set("/:@._-")

    /// Bir dizenin gerçekten bir dosya yolu, URL ya da yapılandırılmış bir
    /// tanımlayıcı zinciri (maven koordinatı, docker imaj referansı,
    /// derleyici konumu, ISO zaman damgası, e-posta) gibi GÖRÜNÜP
    /// görünmediğine karar verir — eski kural gibi "içinde ayraç var mı"ya
    /// değil, dizenin BAŞINA ve BİÇİMİNE bakar. Ayrıca ayraçla ayrılmış
    /// hiçbir parçası tek başına jeton gibi görünmemeli: aksi halde
    /// "/tmp/<jwt>" ya da "https://host/reset?token=<jwt>" gibi bir kimlik
    /// bilgisini bir yol/URL'nin İÇİNE gizlemek onu görünür kılardı — hem
    /// eski hem önceki yeni kural bunu kaçırıyordu.
    static func looksStructural(_ text: String) -> Bool {
        let pathish = text.hasPrefix("/") || text.hasPrefix("~/")
            || text.hasPrefix("./") || text.hasPrefix("../")
        let urlish = text.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*://"#,
                                options: .regularExpression) != nil
        // Eski `refish`in genellemesi (I4, üçüncü tur): yalnızca "/" değil,
        // "/", ":", "@" ayraçlarından HERHANGİ BİRİYLE ayrılmış bir zincir
        // de yapılandırılmış bir tanımlayıcı gibi görünür. Maven koordinatı
        // ("grup:artefakt:sürüm"), docker imaj referansı
        // ("kayıt/ad:etiket"), derleyici konumu ("dosya:satır:sütun"),
        // ISO-8601 zaman damgası ("ss:dd:ss") ve e-posta ("yerel@alan")
        // hepsi bu biçimde ama hiçbiri "/" ile başlamıyor ya da bir URL
        // şeması taşımıyor — eski `refish` yalnızca "/" ayracını kabul
        // ettiği için hepsini "yüksek entropili jeton" sanıyordu.
        let identifierish = text.range(
            of: #"^[A-Za-z0-9._+\-]+([/:@][A-Za-z0-9._+\-]+)+$"#,
            options: .regularExpression) != nil
        guard pathish || urlish || identifierish else { return false }
        return !containsTokenShapedSegment(text)
    }

    /// `text`i `structuralDelimiters`e göre parçalara ayırıp herhangi bir
    /// parçanın tek başına jeton gibi görünüp görünmediğine bakar —
    /// `looksStructural`in (dosya yolu/URL biçimi) kullandığı ortak
    /// mekanizma; `isSensitiveLink` de aynısını URL yolu/sorgu parçaları
    /// için yeniden kullanacak (I4, üçüncü tur, madde 3).
    private static func containsTokenShapedSegment(_ text: String) -> Bool {
        text.split(whereSeparator: { structuralDelimiters.contains($0) })
            .contains { isTokenShapedSegment(String($0)) }
    }

    // MARK: - URL içindeki jetonlar (I4, üçüncü tur)

    /// `ClipMasking.shouldMask` `.link` klipleri için bu fonksiyonu çağırır
    /// — `isSensitive` DEĞİL, çünkü bir bağlantının tamamı (sorgu dizesi +
    /// parça dahil) genel yüksek-entropi kuralına göre neredeyse her zaman
    /// "jeton gibi" görünür (fix round 1, bulgu 1: bu yüzden `.link` baştan
    /// tamamen muaf tutulmuştu). Ama bu, çıplak bir bağlantıyı korumak için
    /// yola çıkıp bir parola sıfırlama/magic-link/presigned URL'nin
    /// TAŞIDIĞI jetonu da görünür bırakıyordu — omuz üstünden okumaya karşı
    /// bu özelliğin var olma sebebi tam olarak bu senaryo.
    ///
    /// Çözüm ikisini ayırmak: bağlantıyı YOL ve SORGU parçalarına ayırıp
    /// (URLComponents ile), her birine `looksStructural`in kullandığı aynı
    /// "bu parça jeton gibi mi" testini uyguluyoruz. Düz bir yol
    /// (`/pull/14/files`) ya da kısa bir parça (`#diff-abc123`) hiçbir
    /// zaman tetiklemez; bir jeton değeri (`?token=eyJ...`, presigned
    /// imza) her zaman tetikler.
    public static func isSensitiveLink(_ text: String) -> Bool {
        // `isSensitive` trims before classifying (yukarıda), ama bu fonksiyon
        // trim ETMİYORDU — bir panoya yapıştırılan bağlantının başında tek
        // bir boşluk ya da satır başı olduğunda `URLComponents(string:)` nil
        // dönüyor, guard hemen `false`a düşüyor ve içindeki jeton (magic-link,
        // parola sıfırlama) hiç maskelenmeden kalıyordu — tam da bu özelliğin
        // korumak için var olduğu senaryo. Sondaki boşluk sorun değildi
        // (`URLComponents` onu tolere ediyor); asimetriyi ortadan kaldırmak
        // için `isSensitive`le aynı trim'i burada da uyguluyoruz.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return false }
        if isHiddenCredential(components.path) { return true }
        if let query = components.query {
            // Sorgu dizesini "&"/"=" üzerinden anahtar/değer parçalarına
            // ayırıyoruz: bir jeton genelde TEK bir değer olarak durur
            // (ör. "token=<jwt>"), tüm sorgu dizesini tek parça sayıp
            // `structuralDelimiters`e bırakırsak "&" bir ayraç olmadığı
            // için birden çok parametre tek, çok uzun bir segmente
            // yapışıp kaçabilirdi.
            let pieces = query.split(whereSeparator: { $0 == "&" || $0 == "=" }).map(String.init)
            if pieces.contains(where: isHiddenCredential) { return true }
        }
        if let fragment = components.fragment, isHiddenCredential(fragment) { return true }
        return false
    }

    /// `text` (bir URL yolu ya da tek bir sorgu anahtarı/değeri/parçası)
    /// kendisi bilinen bir kimlik bilgisi biçiminde mi, yoksa bir dosya
    /// yolunun jeton gizleyebilmesiyle aynı şekilde birini İÇİNDE mi
    /// taşıyor.
    private static func isHiddenCredential(_ text: String) -> Bool {
        isKnownCredential(text) || containsTokenShapedSegment(text)
    }

    /// Tek bir yol/URL parçasının kendi başına bir jeton gibi görünüp
    /// görünmediği — iki bağımsız sinyal, ikisi de yeterli:
    ///
    /// 1) Eski kural: 24+ karakter, harf+rakam karışımı, 12+ ayrı karakter.
    ///    Uzun tanımlayıcıları yakalar ama bir "/" tam ortadan bölünce her
    ///    iki yarı da bu eşiğin altına düşebilir (BLOCKING bulgu): 40
    ///    karakterlik bir sırrın ortasına tek bir "/" koymak her iki
    ///    yarıyı da "jeton değil" gösterip yapısal muafiyeti kandırıyordu
    ///    — Monte Carlo ölçümü rastgele base64 dizelerinin %13-47'sinin bu
    ///    yüzden düz metin kaldığını gösterdi.
    /// 2) Yeni sinyal: büyük/küçük harf VE rakam karışımı, ama 40 karakter
    ///    EŞİTLİĞİ olmadan, 14 karakter gibi daha kısa bir eşikle — AWS
    ///    gizli anahtarı tespitçisinin (aşağıda `isKnownCredential`) zaten
    ///    tam bu sinyale güvendiğinin aynısı, sadece segment başına ve
    ///    uzunluk eşitliği koşulu olmadan uygulanıyor. Sıradan yapılandırılmış
    ///    tanımlayıcı parçaları (tarih, sürüm, dal adı) neredeyse hiç bu
    ///    kısalıkta üç türü birden karıştırmaz.
    private static func isTokenShapedSegment(_ segment: String) -> Bool {
        if segment.count >= 24, segment.contains(where: \.isLetter),
           segment.contains(where: \.isNumber), Set(segment.lowercased()).count >= 12 {
            return true
        }
        guard segment.count >= 14 else { return false }
        return segment.contains(where: \.isUppercase) && segment.contains(where: \.isLowercase)
            && segment.contains(where: \.isNumber)
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
