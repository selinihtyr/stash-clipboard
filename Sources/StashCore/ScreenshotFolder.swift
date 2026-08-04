import Foundation

/// macOS'un ekran görüntülerini kaydettiği klasörü çözer. Bu klasör her
/// zaman Masaüstü değildir: `defaults write com.apple.screencapture location
/// …` ile değiştirilebilir, ve kullanıcı bunu Stash çalışırken de yapabilir.
///
/// Bu yüzden `resolve` bir değeri BİR KEZ okuyup önbelleğe almıyor — her
/// çağrı, `screencapture`ın tercihini yazdığı gerçek `UserDefaults`
/// domain'ini ('~/Library/Preferences/com.apple.screencapture.plist')
/// yeniden okuyor. `ScreenshotWatcher.tick()` bunu her turda çağırıyor;
/// böylece klasör değişikliği uygulamayı yeniden başlatmadan da yakalanır
/// (görev kuralı 1).
public enum ScreenshotFolder {
    /// `defaults`: `com.apple.screencapture` — Stash'in KENDİ paket
    /// kimliğinden bağımsız bir süit. `screencapture` aracı tercihini kendi
    /// domain'ine yazıyor, Stash'inkine değil; `UserDefaults(suiteName:)`
    /// doğrudan o plist dosyasını okur/yazar, alt süreç çalıştırmaya
    /// (`defaults read …`) gerek kalmaz.
    public static func resolve(
        defaults: UserDefaults = UserDefaults(suiteName: "com.apple.screencapture") ?? .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        // Anahtar hiç ayarlanmamışsa (çoğu kullanıcı) ya da boş bir dizeyse
        // (elle silinmiş bir tercih) varsayılan Masaüstü'ne düşüyoruz —
        // `screencapture`ın kendi varsayılan davranışıyla aynı (görev kuralı
        // 1: "handle it being unset").
        guard let raw = defaults.string(forKey: "location"), !raw.isEmpty else {
            return home.appendingPathComponent("Desktop")
        }
        // `screencapture` tercihi hem mutlak yollar ("/Users/x/Shots") hem
        // tilde'li kısayollar ("~/Shots", Terminal'den `defaults write` ile
        // elle girilirse) kabul eder; `expandingTildeInPath` ikisini de
        // doğru çözer, tilde yoksa hiçbir şeyi değiştirmez.
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}
