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
func shouldMask(kind: ClipKind, text: String?) -> Bool {
    guard kind != .link, let text else { return false }
    return SensitivePatterns.isSensitive(text)
}
