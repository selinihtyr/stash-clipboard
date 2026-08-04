import Filters
import Foundation
import HotKey

public struct Settings: Codable, Sendable, Equatable {
    public var combo: KeyCombo
    public var activeFilters: [PasteFilter]
    public var blockedBundleIDs: Set<String>

    // Açılışta başlatma burada YOK: o durumun tek doğruluk kaynağı
    // `LoginItem` (yani `SMAppService.mainApp.status`) — macOS zaten kalıcı
    // tutuyor. Burada ikinci bir kopya tutmak, ikisi birbirinden sapabilen
    // (ör. kullanıcı Sistem Ayarları'ndan kapatırsa) iki doğruluk kaynağı
    // yaratırdı. Bkz. Sources/StashCore/LoginItem.swift.
    public init(combo: KeyCombo, activeFilters: [PasteFilter],
                blockedBundleIDs: Set<String>) {
        self.combo = combo
        self.activeFilters = activeFilters
        self.blockedBundleIDs = blockedBundleIDs
    }

    public static let defaults = Settings(
        combo: .defaultCombo,
        activeFilters: [.plainText],
        // Şifre yöneticileri panoya iş birliği tipi koymayı unutabiliyor;
        // kara liste ikinci savunma hattı.
        blockedBundleIDs: ["com.1password.1password", "com.apple.keychainaccess"])

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
