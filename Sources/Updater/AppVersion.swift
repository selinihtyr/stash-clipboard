import Foundation

/// Sürüm numarası karşılaştırması. Metin karşılaştırması YETMEZ: "0.10.0" <
/// "0.9.0" derdi ve kullanıcı onuncu sürümü hiç görmezdi — güncelleme
/// mekanizmasının en sessiz başarısızlık biçimi bu olurdu.
///
/// Ön sürüm (`0.3.0-beta.1`) kararlı sürümden KÜÇÜK sayılıyor: SemVer'in kuralı
/// bu ve pratikte doğrusu da bu — beta çalıştıran biri 0.3.0 çıkınca ona
/// yükselmeli, tersi değil.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    /// Her zaman üç haneye tamamlanır: "0.2" ile "0.2.0" aynı sürümdür,
    /// GitHub etiketiyle Info.plist'in aynı biçimde yazılmasına güvenmiyoruz.
    public let numbers: [Int]
    /// `-` sonrası ön sürüm etiketi (`beta.1`), yoksa nil.
    public let prerelease: String?

    /// `nil` dönmesi bir hata değil, bir karar: tanımadığımız bir etiketle
    /// (`nightly`, `2026-08-05`) karşılaşırsak "yeni sürüm var" DEMİYORUZ.
    /// Karşılaştıramadığımız bir sürüme yükseltme önermek, kullanıcıyı ne
    /// olduğunu bilmediğimiz bir binary'ye taşımak olurdu.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Etiketler "v0.2.0", Info.plist "0.2.0" yazıyor; ikisi de aynı sürüm.
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        // Yapı üstverisi (`+build.7`) SemVer'de karşılaştırmaya KATILMAZ.
        if let plus = text.firstIndex(of: "+") { text = String(text[text.startIndex..<plus]) }

        var pre: String?
        if let dash = text.firstIndex(of: "-") {
            pre = String(text[text.index(after: dash)...])
            text = String(text[text.startIndex..<dash])
            if pre?.isEmpty == true { return nil }
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        // En az iki hane (`0.2`) şart. Tek haneli bir çekirdek, tarih etiketi
        // gibi sürüm olmayan şeyleri içeri alırdı: "2026-08-05" SemVer'e göre
        // "2026 sürümünün 08-05 ön sürümü" diye okunur ve 0.x çalıştıran
        // herkese "yeni sürüm" diye gösterilirdi. Stash'in sürümleri her zaman
        // X.Y[.Z] biçiminde; tanımadığımız bir şeyi sürüm saymaktansa
        // reddediyoruz.
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            parsed.append(value)
        }
        while parsed.count < 3 { parsed.append(0) }
        numbers = parsed
        prerelease = pre
    }

    public var description: String {
        let core = numbers.map(String.init).joined(separator: ".")
        return prerelease.map { "\(core)-\($0)" } ?? core
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (l, r) in zip(lhs.numbers, rhs.numbers) where l != r { return l < r }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        // Ön sürüm, aynı numaraların kararlı sürümünden küçüktür.
        case (.some, nil): return true
        case (nil, .some): return false
        case (.some(let l), .some(let r)): return l.compare(r, options: .numeric) == .orderedAscending
        }
    }
}
