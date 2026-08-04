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
