import Foundation

/// GitHub'daki bir sürüm. Yalnızca kullanacağımız alanlar: yanıtın geri kalanını
/// modellemek, GitHub bir alan ekleyip değiştirdiğinde çözümlemeyi kırma riski
/// getirirdi.
public struct Release: Equatable, Sendable {
    public let version: AppVersion
    public let tag: String
    /// Sürüm notları (Markdown). Kullanıcıya olduğu gibi gösteriliyor — kendi
    /// yazdığımız bir "yenilikler" metni uydurmuyoruz.
    public let notes: String
    /// Kullanıcının kendi gözüyle bakabileceği sayfa. Otomatik kurulum
    /// yapılamadığı her durumda dönülecek yer burası.
    public let pageURL: URL
    public let downloadURL: URL
    public let downloadSize: Int
}

public enum ReleaseFeedError: Error, Equatable {
    case malformedJSON
    /// Etiket sürüm gibi görünmüyor (bkz. `AppVersion.init?`).
    case unreadableVersion(tag: String)
    /// Sürüm var ama indirilecek `.zip` eklenmemiş — yarım yayınlanmış bir
    /// sürümü "güncelleme var" diye göstermek, tıklayınca hiçbir şey
    /// olmamasıyla biterdi.
    case missingAsset(tag: String, expected: String)
    /// Taslak ya da ön sürüm. `/releases/latest` bunları zaten döndürmüyor;
    /// yine de kontrol ediyoruz, çünkü tek savunma "GitHub böyle davranır"
    /// varsayımı olmamalı.
    case notAStableRelease(tag: String)
}

/// GitHub `/releases/latest` yanıtını çözümler. Ağdan ayrı tutuluyor: gerçek
/// bir istek atmadan, kaydedilmiş yanıtlarla test edilebilsin diye.
public func parseLatestRelease(_ data: Data, assetName: String) throws -> Release {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = root["tag_name"] as? String
    else { throw ReleaseFeedError.malformedJSON }

    if root["draft"] as? Bool == true || root["prerelease"] as? Bool == true {
        throw ReleaseFeedError.notAStableRelease(tag: tag)
    }
    guard let version = AppVersion(tag) else {
        throw ReleaseFeedError.unreadableVersion(tag: tag)
    }
    guard let pageURL = (root["html_url"] as? String).flatMap(URL.init(string:)) else {
        throw ReleaseFeedError.malformedJSON
    }
    let assets = root["assets"] as? [[String: Any]] ?? []
    guard let asset = assets.first(where: { $0["name"] as? String == assetName }),
          let downloadURL = (asset["browser_download_url"] as? String).flatMap(URL.init(string:))
    else { throw ReleaseFeedError.missingAsset(tag: tag, expected: assetName) }

    return Release(
        version: version,
        tag: tag,
        notes: (root["body"] as? String) ?? "",
        pageURL: pageURL,
        downloadURL: downloadURL,
        downloadSize: asset["size"] as? Int ?? 0)
}

public enum UpdateAvailability: Equatable, Sendable {
    case upToDate
    case available(Release)
}

/// Yalnızca DAHA YENİ bir sürüm güncelleme sayılır. Eşitse ya da yayınlanan
/// sürüm çalışandan eskiyse (kaynaktan derleyip henüz yayınlanmamış bir sürümü
/// çalıştıran biri — yani bu depoyu klonlayan herkes) hiçbir şey önerilmiyor:
/// "downgrade" bir güncelleme değildir.
public func updateAvailability(current: AppVersion, latest: Release) -> UpdateAvailability {
    latest.version > current ? .available(latest) : .upToDate
}
