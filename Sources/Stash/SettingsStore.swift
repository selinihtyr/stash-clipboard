import Combine
import StashCore

/// Ayarlar penceresinin ve `AppDelegate`'in paylaştığı tek doğruluk kaynağı.
///
/// Önceki tasarımda `SettingsView` ayarları `@State` bir struct kopyası olarak
/// tutuyordu: pencere ilk açıldığında bir anlık görüntü alınıyor, sonrasında
/// `AppDelegate`'in yaptığı hiçbir değişiklik (özellikle reddedilen bir
/// kısayolun eskiye geri alınması) görüntüye yansımıyordu. Kullanıcı reddi
/// gösteren uyarıyı kapatıp bir saat sonra pencereye dönseydi, orada hâlâ
/// çalışmayan kombinasyonu görürdü — ayarlar penceresinin varlık sebebinin
/// tam tersi (fix round 2).
///
/// Çözüm: `settings`i bir referans tipinin `@Published` alanına taşımak.
/// `AppDelegate` ve `SettingsView` artık aynı nesneyi paylaşıyor; `AppDelegate`
/// bir kısayolu geri aldığında burayı günceller, SwiftUI de `@ObservedObject`
/// sayesinde otomatik olarak yeniden çiziyor — pencere görünür olsun ya da
/// olmasın, bir sonraki açılışta güncel değeri okur (`isReleasedWhenClosed`
/// ile pencere arka planda hayatta kalsa bile).
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: StashCore.Settings
    init(_ settings: StashCore.Settings) {
        self.settings = settings
    }
}
