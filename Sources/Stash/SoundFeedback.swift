import AppKit

/// Sesin gerçekten çalınmasını arkasına alan ince bir arayüz: testler bunun
/// sahte bir uygulamasını kullanır, `swift test` hiç ses çıkarmaz (görev
/// isteği: "test ederken gerçekten ses çalma").
///
/// `@MainActor`: tek çağıranı (`SoundFeedbackController`) zaten `@MainActor`
/// — burayı da işaretlemek, sahte uygulamaların (testlerdeki `FakeSoundPlayer`
/// gibi) izolasyonu `nonisolated(unsafe)` ya da `@unchecked Sendable` gibi
/// bir kaçış kapısıyla susturmak zorunda kalmadan gerçek izolasyonla
/// derlenmesini sağlıyor (görev kısıtı: unchecked yerine gerçek izolasyon).
@MainActor
protocol SoundPlaying {
    func play(_ sound: FeedbackSound)
}

/// Uygulamanın çaldığı iki ayrı geri bildirim sesi. Aynı ses hem "panodan
/// kaydedildi" hem "öndeki uygulamaya yapıştırıldı" için çalarsa, gün boyu
/// açık kalan bir menü çubuğu uygulamasında kullanıcı ekrana bakmadan
/// ikisini ayırt edemez — sesin bütün amacı bu.
///
/// Sahibi macOS'un yerleşik seslerini (eski `SystemSoundPlayer`, "Tink"/
/// "Pop") sert bulup reddetti; kendi seçtiği iki kısa klip kullanılıyor
/// (bkz. `Resources/Sounds/CREDITS.txt` — kaynak, lisans CC-BY 3.0).
///   - `captured`: `copy.wav` — panodan yeni bir şeyin Stash'e girdiğini
///     (kaydedildiğini) işaretler.
///   - `pasted`: `paste.wav` — aynı kaydın perde kaydırılmış türevi; seçili
///     bir kartın öndeki uygulamaya GERÇEKTEN teslim edildiğini işaretler,
///     `copy.wav`den perde olarak yeterince farklı ki ikisi arka arkaya
///     duyulunca da karışmaz.
enum FeedbackSound: Equatable {
    case captured
    case pasted

    /// Paket kaynağındaki dosya adı (uzantısız) — `Resources/Sounds/`de
    /// hem repoda hem kurulu `.app`in `Contents/Resources/Sounds/`inde
    /// aynı adla duruyor (bkz. `scripts/bundle.sh`).
    var resourceFileName: String {
        switch self {
        case .captured: return "copy"
        case .pasted: return "paste"
        }
    }
}

/// Sahibinin seçtiği iki ses, paket kaynağından okunuyor — macOS sistem
/// seslerinden değil (bkz. `FeedbackSound` gerekçesi ve README'deki kredi
/// bölümü). Eksik ya da bozuk dosya = sessizlik: asla çökme, asla reddedilen
/// bir sistem sesine geri dönüş (görev kuralı 2).
///
/// Sesler `Bundle.main.resourceURL`den okunur, `Bundle.module`den değil:
/// bu uygulama gerçek bir Xcode/SwiftPM kaynak hedefi değil, `scripts/
/// bundle.sh`nin elle dikişlediği bir `.app` — tıpkı `AppIcon.icns`nin
/// Info.plist üzerinden `Contents/Resources`te aranması gibi, sesler de
/// aynı klasörde duruyor çünkü `bundle.sh` onları oraya kopyalıyor.
/// Paketlenmemiş bir `swift run` bu düzeni sağlamaz — `Bundle.main` o zaman
/// `.build` altını gösterir, dosyalar bulunamaz ve player sessiz kalır,
/// çökmez; bu durum test/geliştirme akışında zaten hedeflenen davranış.
///
/// İki ses de HER `play()` çağrısında değil, KURULUŞTA bir kez diskten
/// okunup `NSSound` olarak önbelleğe alınır (görev kuralı: "load once and
/// reuse... fires hundreds of times a day" — günde yüzlerce kez aynı dosyayı
/// yeniden okumak israf). Her çalışta önbellekteki örneği doğrudan çalmak
/// yerine `NSCopying` ile ucuz bir kopyasını çalıyoruz: `NSSound` aynı
/// örnek üzerinde üst üste `play()` çağrılırsa önceki çalmayı keser (bkz.
/// eski `SystemSoundPlayer` gerekçesi, hâlâ geçerli) — `copy()` altındaki
/// ses verisini yeniden okumadan bağımsız, kesilmeyen bir çalma başlatır.
@MainActor
final class BundledSoundPlayer: SoundPlaying {
    private let captured: NSSound?
    private let pasted: NSSound?

    // Testler gerçek `.play()`i hiç çağırmıyor (bkz. dosya başı gerekçe),
    // ama gerçek paket dosyalarının çökmeden yüklendiğini doğrulamak için
    // bu iki bayrağa bakıyor — bkz. `BundledSoundPlayerTests`.
    var isCapturedLoaded: Bool { captured != nil }
    var isPastedLoaded: Bool { pasted != nil }

    init(resourceDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true)) {
        captured = Self.load(.captured, in: resourceDirectory)
        pasted = Self.load(.pasted, in: resourceDirectory)
    }

    private static func load(_ sound: FeedbackSound, in directory: URL?) -> NSSound? {
        guard let directory else { return nil }
        let url = directory
            .appendingPathComponent(sound.resourceFileName)
            .appendingPathExtension("wav")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // `byReference: false`: veriyi burada, kuruluşta belleğe okur — asıl
        // "bir kez oku" adımı bu; sonraki her `play()` yalnızca `copy()`.
        return NSSound(contentsOf: url, byReference: false)
    }

    func play(_ sound: FeedbackSound) {
        let cached = sound == .captured ? captured : pasted
        (cached?.copy() as? NSSound)?.play()
    }
}
