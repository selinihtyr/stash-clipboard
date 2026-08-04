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
/// Seçim: macOS'un yerleşik seslerinin en kısaları arasından, birbirinden
/// tonca ayrışan ama ikisi de günde yüzlerce kez çalınca yorucu olmayan iki
/// tanesi. Glass/Hero/Sosumi/Submarine gibi daha uzun ya da "bildirim"
/// hissi veren sesler bilerek elendi — bir kopyalama/yapıştırma bir olay
/// değil, arka plan geri bildirimi.
///   - `captured`: "Tink" — kısa, tiz, metalik bir tık. Panodan yeni bir
///     şeyin Stash'e girdiğini (kaydedildiğini) işaretler.
///   - `pasted`: "Pop" — kısa, yumuşak, alçak bir pat. Seçili bir kartın
///     öndeki uygulamaya GERÇEKTEN teslim edildiğini işaretler; `Tink`ten
///     hem perde hem doku olarak yeterince farklı ki ikisi arka arkaya
///     duyulunca da karışmaz.
enum FeedbackSound: Equatable {
    case captured
    case pasted

    var systemSoundName: NSSound.Name {
        switch self {
        case .captured: return "Tink"
        case .pasted: return "Pop"
        }
    }
}

/// `NSSound(named:).play()` sistemin ses sunucusuna kısa bir mesaj yollayıp
/// hemen döner — senkron beklemiyor, bu yüzden ne 0,5 saniyelik yoklama
/// döngüsünü ne de sentetik ⌘V yolunu bloklar (görev kuralı 6).
///
/// Her çalışta YENİ bir `NSSound` örneği oluşturuyoruz: tek bir örneği
/// paylaşıp üst üste tetiklemek, hızlı art arda kopyalarda (`NSSound`
/// aynı örnek üzerinde yeni bir `play()` önceki çalmayı kesiyor) sesin
/// yarıda kesilmesine yol açar — kullanıcıya "bir şey ters gitti" hissi
/// verir, oysa sadece hızlı kopyalamıştır.
struct SystemSoundPlayer: SoundPlaying {
    func play(_ sound: FeedbackSound) {
        NSSound(named: sound.systemSoundName)?.play()
    }
}
