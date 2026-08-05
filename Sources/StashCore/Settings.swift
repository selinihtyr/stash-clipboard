import Filters
import Foundation
import HotKey

public struct Settings: Codable, Sendable, Equatable {
    public var combo: KeyCombo
    public var activeFilters: [PasteFilter]
    public var blockedBundleIDs: Set<String>
    /// Yakalama ve yapıştırma sesleri (bkz. Stash hedefindeki
    /// `SoundFeedbackController`). `Settings` bu ikisinin nasıl çaldığını
    /// bilmiyor — yalnızca açık/kapalı anahtarı taşıyor, tıpkı
    /// `activeFilters`in filtrelerin nasıl uygulandığını bilmemesi gibi.
    public var soundsEnabled: Bool
    /// Ekran görüntüsü klasörünü izleyip yeni ekran görüntülerini panodan
    /// kopyalanmış gibi geçmişe ekleme (bkz. `ScreenshotWatcher`). Varsayılan
    /// KAPALI: açılınca Masaüstü/Belgeler için bir TCC izin istemi tetikler
    /// (görev kuralı 8: "opt-in") — kullanıcı bunu istemeden karşılaşmamalı,
    /// `soundsEnabled`in aksine (o zararsız, bu izin isteyen bir klasör okuması).
    public var screenshotWatchEnabled: Bool
    /// Günde bir GitHub'a bakıp yeni sürüm olup olmadığını sorma. Varsayılan
    /// AÇIK — `screenshotWatchEnabled`in aksine: o, kullanıcının klasörlerini
    /// okuyan ve izin isteyen bir özellik; bu, hiçbir veri GÖNDERMEYEN tek
    /// yönlü bir sorgu. Kapalı olsaydı, güncellemenin varlığından haberi
    /// olmayan kullanıcı eski sürümde kalırdı — özelliğin tüm amacı buydu.
    /// Anahtar yine de duruyor: ağa hiç çıkmayan bir Stash isteyen biri
    /// kapatabilmeli.
    public var automaticUpdateChecks: Bool

    // Açılışta başlatma burada YOK: o durumun tek doğruluk kaynağı
    // `LoginItem` (yani `SMAppService.mainApp.status`) — macOS zaten kalıcı
    // tutuyor. Burada ikinci bir kopya tutmak, ikisi birbirinden sapabilen
    // (ör. kullanıcı Sistem Ayarları'ndan kapatırsa) iki doğruluk kaynağı
    // yaratırdı. Bkz. Sources/StashCore/LoginItem.swift.
    public init(combo: KeyCombo, activeFilters: [PasteFilter],
                blockedBundleIDs: Set<String>, soundsEnabled: Bool = true,
                screenshotWatchEnabled: Bool = false,
                automaticUpdateChecks: Bool = true) {
        self.combo = combo
        self.activeFilters = activeFilters
        self.blockedBundleIDs = blockedBundleIDs
        self.soundsEnabled = soundsEnabled
        self.screenshotWatchEnabled = screenshotWatchEnabled
        self.automaticUpdateChecks = automaticUpdateChecks
    }

    public static let defaults = Settings(
        combo: .defaultCombo,
        activeFilters: [.plainText],
        // Şifre yöneticileri panoya iş birliği tipi koymayı unutabiliyor;
        // kara liste ikinci savunma hattı.
        blockedBundleIDs: ["com.1password.1password", "com.apple.keychainaccess"],
        soundsEnabled: true,
        screenshotWatchEnabled: false,
        automaticUpdateChecks: true)

    private enum CodingKeys: String, CodingKey {
        case combo, activeFilters, blockedBundleIDs, soundsEnabled, screenshotWatchEnabled
        case automaticUpdateChecks
    }

    // Elle yazılmış `init(from:)`: `soundsEnabled`den ÖNCE kaydedilmiş bir
    // ayarlar blob'unda bu anahtar hiç yok. Sentezlenmiş decode bu satırda
    // tüm decode'u başarısızlığa düşürürdü (`load()` sonra sessizce
    // `.defaults`e düşer — sahibin kısayolu, filtreleri, kara listesi hiç
    // sebepsiz sıfırlanırdı). `decodeIfPresent` eksik anahtarı AÇIK'a
    // düşürüyor: sahip sesi zaten istedi, sessiz bir yükseltmenin onu
    // kapatması yanlış olurdu (görev kuralı 5).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combo = try container.decode(KeyCombo.self, forKey: .combo)
        activeFilters = try container.decode([PasteFilter].self, forKey: .activeFilters)
        blockedBundleIDs = try container.decode(Set<String>.self, forKey: .blockedBundleIDs)
        soundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        // `soundsEnabled`in aksine eksik anahtar burada AÇIK'a değil KAPALI'ya
        // düşüyor: bu özellik izin isteyen, gizlilik anlamı olan bir klasör
        // okuması başlatıyor (görev kuralı 8) — eski bir ayarlar blob'unu
        // sessizce yükseltip kullanıcıyı hiç istemediği bir TCC istemiyle
        // karşılaştırmak yanlış olurdu. `soundsEnabled` zararsız bir ses
        // anahtarı olduğu için oradaki "sessiz yükseltmenin kapatması yanlış
        // olur" gerekçesi burada tam tersine dönüyor.
        screenshotWatchEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .screenshotWatchEnabled) ?? false
        // Eksik anahtar AÇIK'a düşüyor (`soundsEnabled` gerekçesi): güncelleme
        // kontrolünden önce kaydedilmiş bir blob'u okuyan kullanıcı,
        // güncellemesi olduğunu HİÇ öğrenemeyen tek kullanıcı olmamalı —
        // özelliğin var oluş sebebi tam da bu (yorumdaki "silip yeniden
        // indirmek zorunda kalmak"). Kapatmak isteyen Ayarlar'dan kapatır.
        automaticUpdateChecks = try container.decodeIfPresent(
            Bool.self, forKey: .automaticUpdateChecks) ?? true
    }

    private static let key = "settings"

    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .defaults }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
