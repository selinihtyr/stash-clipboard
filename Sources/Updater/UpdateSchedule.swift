import Foundation

/// Otomatik kontrolün ne zaman yapılacağı. Saf ve enjekte edilebilir bir
/// `now` ile: "bir gün sonra tekrar kontrol ediyor mu" sorusunu gerçekten bir
/// gün bekleyerek test etmek zorunda kalmayalım.
public enum UpdateSchedule {
    /// Günde bir. Daha sık kontrol etmek ne kullanıcıya bir şey kazandırır ne
    /// de GitHub'a; daha seyreki güvenlik düzeltmesini geciktirir.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Açılışta ve sonrasında periyodik olarak sorulur.
    ///
    /// `lastCheck == nil` (ilk açılış) ANINDA kontrol demek DEĞİL: uygulamanın
    /// ilk açılışı zaten izin istemleriyle dolu, oraya bir de ağ isteği
    /// sıkıştırmak "hiçbir şey ağa gitmez" beklentisiyle kuran birine kötü bir
    /// sürpriz olur. `firstCheckDelay` kadar sonra bakılıyor.
    public static let firstCheckDelay: TimeInterval = 10 * 60

    public static func shouldCheck(
        enabled: Bool, lastCheck: Date?, launchedAt: Date, now: Date
    ) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else {
            return now.timeIntervalSince(launchedAt) >= firstCheckDelay
        }
        // Gelecekteki bir `lastCheck` (kullanıcı saati geri aldı) kontrolü
        // sonsuza kadar erteleyebilirdi; mutlak farka bakıyoruz.
        return abs(now.timeIntervalSince(lastCheck)) >= interval
    }
}
