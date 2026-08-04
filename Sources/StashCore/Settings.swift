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

    // Açılışta başlatma burada YOK: o durumun tek doğruluk kaynağı
    // `LoginItem` (yani `SMAppService.mainApp.status`) — macOS zaten kalıcı
    // tutuyor. Burada ikinci bir kopya tutmak, ikisi birbirinden sapabilen
    // (ör. kullanıcı Sistem Ayarları'ndan kapatırsa) iki doğruluk kaynağı
    // yaratırdı. Bkz. Sources/StashCore/LoginItem.swift.
    public init(combo: KeyCombo, activeFilters: [PasteFilter],
                blockedBundleIDs: Set<String>, soundsEnabled: Bool = true) {
        self.combo = combo
        self.activeFilters = activeFilters
        self.blockedBundleIDs = blockedBundleIDs
        self.soundsEnabled = soundsEnabled
    }

    public static let defaults = Settings(
        combo: .defaultCombo,
        activeFilters: [.plainText],
        // Şifre yöneticileri panoya iş birliği tipi koymayı unutabiliyor;
        // kara liste ikinci savunma hattı.
        blockedBundleIDs: ["com.1password.1password", "com.apple.keychainaccess"],
        soundsEnabled: true)

    private enum CodingKeys: String, CodingKey {
        case combo, activeFilters, blockedBundleIDs, soundsEnabled
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
