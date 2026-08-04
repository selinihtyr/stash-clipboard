import PasteEngine
import StashCore

/// Yalnızca gerçek bir teslimat "yapıştırıldı" sesini hak eder.
/// `.copiedOnlyNoAccessibilityPermission` ve `.copiedOnlyKeystrokeFailed`de
/// içerik panoya YAZILDI ama sentetik ⌘V hiç ulaşmadı — bu gerçekte bir
/// kopyalama, teslimat değil. "Yapıştırıldı" sesini çalmak kullanıcıya
/// olmayan bir şeyi söylerdi (görev kuralı 4: "paste sound must not lie").
///
/// Sessizlik yerine kopyalama sesini seçtik: kullanıcı hâlâ bir şeyin
/// olduğunu duyar (uygulamanın takılı kaldığını sanmaz), ama çalan ses
/// dürüstçe "kopyalandı" diyor, "yapıştırıldı" değil — zaten aynı iki
/// durumda ekrana çıkan `NSAlert` da tam olarak bunu söylüyor
/// (`AppDelegate.finishPaste`).
func soundForPasteOutcome(_ outcome: PasteOutcome) -> FeedbackSound? {
    switch outcome {
    case .pastedIntoFrontmostApp: return .pasted
    case .copiedOnlyNoAccessibilityPermission, .copiedOnlyKeystrokeFailed: return .captured
    }
}

/// Ayarlar penceresindeki "Kopyalama ve yapıştırmada ses çal" anahtarı ile
/// gerçek çalma çağrısı arasındaki tek nokta. `AppDelegate` hem yakalama
/// (`CaptureCoordinator.onCaptureSound`) hem yapıştırma tarafında aynı
/// "anahtar açık mı, hangi ses" mantığını tekrarlamak yerine burayı çağırır.
///
/// `settingsStore` bir referans tipi (bkz. `SettingsStore`teki gerekçe):
/// burada saklanan referans her çağrıda GÜNCEL anahtarı okur. Ayarlar
/// penceresi açıkken anahtar kapatılırsa, pencere kapanmadan bir sonraki
/// yakalama/yapıştırma bunu hemen görür — kurulduğu andaki bir kopyaya
/// takılı kalmaz. Bu yüzden `settings.soundsEnabled`i init'te bir kez okuyup
/// saklamak yerine her çağrıda yeniden okuyoruz.
@MainActor
final class SoundFeedbackController {
    private let settingsStore: SettingsStore
    private let player: SoundPlaying

    init(settingsStore: SettingsStore, player: SoundPlaying) {
        self.settingsStore = settingsStore
        self.player = player
    }

    /// `CaptureCoordinator.onCaptureSound`e bağlanır. Bu kanca zaten yalnızca
    /// açılıştan sonraki gerçek, atlanmamış bir yakalamada tetikleniyor
    /// (görev kuralları 1 ve 2, bkz. `CaptureCoordinator` ve `ClipCapture`
    /// gerekçeleri) — burada tekrar aynı kontrolleri yapmıyoruz, yalnızca
    /// anahtarı okuyoruz.
    func captured() {
        guard settingsStore.settings.soundsEnabled else { return }
        player.play(.captured)
    }

    /// `AppDelegate.finishPaste`den çağrılır; sonucu `soundForPasteOutcome`
    /// üzerinden dürüst sese çevirir.
    func pasted(_ outcome: PasteOutcome) {
        guard settingsStore.settings.soundsEnabled, let sound = soundForPasteOutcome(outcome) else { return }
        player.play(sound)
    }
}
