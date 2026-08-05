import HotKey

/// Ayarlar penceresinden gelen bir kısayol değişikliğinin sonucu.
enum HotKeyChangeOutcome: Equatable {
    /// Kombinasyon değişmedi (yeniden kayıt hiç denenmedi) ya da yeni
    /// kombinasyon başarıyla kaydoldu.
    case applied(KeyCombo)
    /// Yeni kombinasyon kaydolmadı; önceki kombinasyon geri kaydedildi.
    /// Kullanıcının hâlâ çalışan bir kısayolu var, ama istediği değişiklik
    /// olmadı.
    case reverted(to: KeyCombo, failureReason: HotKeyError)
    /// Ne yeni ne de önceki kombinasyon kaydolabildi: kullanıcının şu anda
    /// çalışan hiçbir kısayolu yok. Sessizce geçilebilecek bir durum değil.
    case revertFailed(attempted: KeyCombo, previous: KeyCombo, failureReason: HotKeyError)
}

/// Yeni bir kombinasyonu uygulamaya çalışır; başarısız olursa kullanıcıyı
/// kısayolsuz bırakmamak için öncekini geri kaydeder. `register` gerçek
/// Carbon çağrısını sarar — bu ayrım sayesinde "önce yeniyi dene, olmazsa
/// eskiye dön" mantığı Carbon'a ya da bir NSAlert'e dokunmadan test
/// edilebiliyor.
///
/// Kombinasyon değişmediyse `register` hiç çağrılmaz: aksi halde filtre
/// açıp kapatmak, kara listeyi düzenlemek ya da raf oluşturmak gibi
/// kısayolla ilgisi olmayan her ayar değişikliği gereksiz bir
/// unregister/register döngüsü tetikler — bu round'da düzeltilen ikinci bulgu.
func reconcileHotKeyChange(
    from previous: KeyCombo,
    to proposed: KeyCombo,
    register: (KeyCombo) -> Result<Void, HotKeyError>
) -> HotKeyChangeOutcome {
    guard proposed != previous else { return .applied(previous) }
    switch register(proposed) {
    case .success:
        return .applied(proposed)
    case .failure(let error):
        switch register(previous) {
        case .success:
            return .reverted(to: previous, failureReason: error)
        case .failure(let restoreError):
            return .revertFailed(attempted: proposed, previous: previous, failureReason: restoreError)
        }
    }
}

/// Şu an Carbon'a gerçekten kayıtlı olan kombinasyonun sahibi.
///
/// Bu tipin var olma sebebi bir hata: "önceki kombinasyon" `settingsStore`dan
/// OKUNAMAZ. Ayarlar penceresi paylaşılan `settingsStore.settings`i önce
/// güncelleyip sonra `onChange`i çağırıyor (SettingsView'daki `settings.combo =
/// combo; onChange(settings)`), dolayısıyla geri çağırım çalıştığında mağazadaki
/// değer zaten YENİ kombinasyon. `reconcileHotKeyChange(from: mağaza, to: yeni)`
/// bu yüzden "kombinasyon değişmedi" görüp `register`ı hiç çağırmıyor,
/// eski kısayol kayıtlı kalıyordu: kullanıcı Ayarlar'da yeni kısayolu görüyor,
/// diske de o yazılıyor, ama şerit yeniden başlatana kadar hâlâ eskisiyle
/// açılıyordu (v0.1 kullanıcı raporu).
///
/// Kayıtlı kombinasyon artık ayarlardan bağımsız burada tutuluyor: mağazayı kim
/// ne zaman güncellerse güncellesin, karşılaştırma gerçekten kayıtlı olan
/// değere karşı yapılıyor.
@MainActor
final class HotKeyCoordinator {
    /// Son başarılı kaydın kombinasyonu. Kayıt başarısız olup geri dönüldüyse
    /// geri dönülen kombinasyon; hiçbiri tutmadıysa (açılışta da başarısız)
    /// yine de son istenen "çalışması beklenen" değer kalır — bir sonraki
    /// değişiklikte geri dönülecek aday olarak doğru olan bu.
    private(set) var currentCombo: KeyCombo
    private let register: (KeyCombo) -> Result<Void, HotKeyError>

    init(currentCombo: KeyCombo, register: @escaping (KeyCombo) -> Result<Void, HotKeyError>) {
        self.currentCombo = currentCombo
        self.register = register
    }

    /// Açılış kaydı: geri dönülecek "önceki çalışan kombinasyon" yok, o yüzden
    /// `apply` değil bu kullanılıyor — `apply` aynı kombinasyonu görüp kaydı
    /// hiç denemezdi.
    func registerCurrent() -> Result<Void, HotKeyError> {
        register(currentCombo)
    }

    /// Yeni kombinasyonu uygulamayı dener ve `currentCombo`yu sonuca göre
    /// ilerletir. Dönen sonucu çağıran taraf (AppDelegate) kullanıcıya uyarı
    /// göstermek ve diske yazmak için yorumluyor.
    func apply(_ proposed: KeyCombo) -> HotKeyChangeOutcome {
        let outcome = reconcileHotKeyChange(from: currentCombo, to: proposed, register: register)
        switch outcome {
        case .applied(let combo):
            currentCombo = combo
        case .reverted(let combo, _):
            currentCombo = combo
        case .revertFailed(_, let previous, _):
            currentCombo = previous
        }
        return outcome
    }
}
