import PasteboardKit
import Store

/// `SensitivePatterns` metni tek başına görüyor, klibin `kind`'ını değil —
/// bilerek: hem yeniden kullanılabilir kalsın hem de URL ayrıştırmasını
/// tekrarlamasın. Ama bu yüzden sorgu dizesi/fragment içeren sıradan bir
/// bağlantı "yüksek entropili jeton" gibi görünüp maskeleniyordu — bağlantılar
/// en sık kopyalanan şeylerden biri olduğu için şeridi işe yaramaz kılıyordu
/// (fix round 1, bulgu 1). ClipCapture zaten yakalama anında `.link`'i
/// sınıflandırıyor; bu, o sınıflandırmayı tekrar ayrıştırma yerine ona
/// güvenen tek karar noktası — ClipCardView burayı çağırır.
///
/// `.file` de aynı gerekçeyle muaf (I4): bir dosya yolu sır değildir, kartlar
/// arasında ayrım yapabilmek için kullanıcının onu okuyabilmesi gerekir —
/// Finder'dan sürüklenen bir ekran görüntüsü yolu, harf+rakam karışımı uzun
/// bir dosya adı yüzünden "yüksek entropili jeton" gibi görünüyordu.
func shouldMask(kind: ClipKind, text: String?) -> Bool {
    guard kind != .link, kind != .file, let text else { return false }
    return SensitivePatterns.isSensitive(text)
}
