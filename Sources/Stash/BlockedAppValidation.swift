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
func validateBlockedBundleID(_ input: String, existing: Set<String>) -> BlockedBundleIDValidation {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return .invalid(reason: "Paket kimliği boş olamaz.")
    }
    let pattern = #"^[A-Za-z0-9]+(\.[A-Za-z0-9-]+)+$"#
    guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
        return .invalid(reason: "Ters etki alanı biçiminde olmalı (ör. com.apple.Notes).")
    }
    guard !existing.contains(trimmed) else {
        return .invalid(reason: "Bu paket kimliği zaten listede.")
    }
    return .valid(trimmed)
}
