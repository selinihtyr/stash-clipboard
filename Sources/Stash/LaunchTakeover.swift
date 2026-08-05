import AppKit

/// `isDone` sağlanana kadar `tick`i en fazla `ticks` kez çalıştırır ve sonunda
/// durumu döner.
///
/// Sınırın varlığı asıl mesele: açılışta beklediğimiz şey (eski kopyanın
/// ölmesi) hiç gerçekleşmeyebilir — takılmış bir süreç yüzünden Stash sonsuza
/// kadar açılmadan durmamalı. Kısayolsuz ama açık bir uygulama, hiç açılmayan
/// bir uygulamadan iyidir.
func waitUntil(_ isDone: () -> Bool, ticks: Int, tick: () -> Void) -> Bool {
    for _ in 0..<ticks {
        if isDone() { return true }
        tick()
    }
    return isDone()
}

/// Aynı uygulamanın çalışan başka kopyalarını kapatıp gerçekten çıkmalarını
/// bekler; başka kopya bulunduysa `true` döner.
///
/// İki sebeple, ikisi de bu gece yaşandı:
///
/// 1. **Kısayol sessizce ölüyor.** İki kopya aynı kombinasyonu kaydettiğinde
///    sistemdeki yuvanın sahibi tek oluyor; ölmekte olan eski kopya kaydı
///    bıraktığında yuva boşta kalıyor. Yeni kopyanın `RegisterEventHotKey`i
///    `noErr` döndüğü için hiçbir hata görünmüyor, ama tuşa basınca hiçbir şey
///    olmuyor — kullanıcı için "uygulama bozuldu"dan ayırt edilemez.
/// 2. **Aynı SQLite dosyasına iki yazar.** Geçmiş tek bir dosyada; iki kopyanın
///    aynı anda yazması için hiçbir sebep yok.
///
/// Kapatılan kopya bizden ESKİ olabilir de olmayabilir de; her hâlükârda
/// devralan biziz, çünkü kullanıcının en son açtığı kopya biziz.
@MainActor
func takeOverFromOtherInstances(
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
    selfPID: Int32 = ProcessInfo.processInfo.processIdentifier
) -> Bool {
    func others() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != selfPID && !$0.isTerminated }
    }
    let existing = others()
    guard !existing.isEmpty else { return false }
    for instance in existing { instance.terminate() }
    // 0,05 sn × 40 = en fazla 2 sn. `RunLoop.run(until:)` ile bekliyoruz,
    // `sleep` ile değil: açılışın geri kalanı ana iş parçacığında ve
    // pencereleri kapanan eski kopyanın da olaylara ihtiyacı var.
    _ = waitUntil({ others().isEmpty }, ticks: 40) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return true
}
