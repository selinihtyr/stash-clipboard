import Foundation

/// Kullanıcının "Kaydedilmeyecek uygulamalar" listesine eklemek istediği
/// paket kimliğinin geçerliliğini karar verir (C4). Kara listeyi SADECE
/// zayıflatabilen (Kaldır düğmesi) değil, güçlendiren taraf da var olmalı —
/// ve raf adında olduğu gibi (bkz. ClipStore.createShelf) boş/anlamsız bir
/// girdiyi sessizce yutmak yerine görünür bir hatayla reddetmeli.
///
/// `reconcileHotKeyChange`'deki gibi bu da SettingsView'dan koparılmış saf
/// karar mantığı: Carbon'a ya da bir NSAlert'e dokunmadan test edilebilsin.
enum BlockedBundleIDValidation: Equatable {
    case valid(String)
    case invalid(reason: String)
}

/// Gerçekten kurulu bir uygulama mı diye macOS'a sormuyoruz — bu, çalışan
/// uygulamalar arasından seçtiren bir picker gerektirirdi (bkz. rapor:
/// bilinçli olarak kapsam dışı bırakıldı). Ama boş bir girdiyi ya da bariz
/// saçmalığı (boşluk, tek kelime, yasak karakter) geçirmek de dürüst değil.
/// En az iki bileşenli ters etki alanı biçimi (ör. "com.apple.Notes")
/// makul bir asgari çubuk: gerçek bundle ID'lerin şeklini zorunlu kılar
/// ama var olduklarını iddia etmez.
///
/// C4, ikinci tur: "COM.APPLE.NOTES" ayrı, geçerli bir girdi olarak kabul
/// ediliyordu — ama `ClipCapture` çalışırken karşılaştırmayı `Set.contains`
/// ile yapıyor, o da tam eşleşme ister. Kullanıcı bir uygulamayı
/// "engellediğini" görüyor ama gerçek (küçük harfli) bundle ID hiç
/// eşleşmediği için hiçbir şey engellenmiyordu — sessiz, fark edilmesi
/// neredeyse imkansız bir başarısızlık. Kabul edilen değer burada küçük
/// harfe normalize ediliyor (depolama tarafı); karşılaştırma tarafı
/// (`ClipCapture.poll`) de aynı normalize edilmiş biçimle karşılaştırıyor —
/// tek bir kaçış noktası yerine iki ucu da tutarlı kılmak, gelecekte biri
/// unutulursa bile ikincisinin hâlâ doğru davranmasını sağlar.
func validateBlockedBundleID(_ input: String, existing: Set<String>) -> BlockedBundleIDValidation {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return .invalid(reason: "Paket kimliği boş olamaz.")
    }
    // Alt çizgi kurallı bir reverse-DNS bileşeni değildir ama gerçek
    // uygulamalar kullanır (ör. "com.my_company.app"); onu reddetmek
    // kullanıcının elindeki gerçek bir bundle ID'yi geçersiz sayardı.
    let pattern = #"^[A-Za-z0-9_]+(\.[A-Za-z0-9_-]+)+$"#
    guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
        return .invalid(reason: "Ters etki alanı biçiminde olmalı (ör. com.apple.Notes).")
    }
    let normalized = trimmed.lowercased()
    guard !existing.contains(where: { $0.lowercased() == normalized }) else {
        return .invalid(reason: "Bu paket kimliği zaten listede.")
    }
    return .valid(normalized)
}
