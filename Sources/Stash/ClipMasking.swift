import PasteboardKit
import Store

/// `SensitivePatterns` metni tek başına görüyor, klibin `kind`'ını değil —
/// bilerek: hem yeniden kullanılabilir kalsın hem de URL ayrıştırmasını
/// tekrarlamasın. ClipCapture zaten yakalama anında `.link`'i
/// sınıflandırıyor; bu, o sınıflandırmayı tekrar ayrıştırma yerine ona
/// güvenen tek karar noktası — ClipCardView burayı çağırır.
///
/// `.link` `isSensitive`e DEĞİL `isSensitiveLink`e gider (I4, üçüncü tur):
/// bir bağlantının tamamını genel yüksek-entropi kuralına sokmak sorgu
/// dizesi/parça içeren sıradan bir bağlantıyı bile "jeton gibi" gösterip
/// maskeliyordu — bağlantılar en sık kopyalanan şeylerden biri olduğu için
/// şeridi işe yaramaz kılıyordu (fix round 1, bulgu 1). Ama tam tersi yönde
/// bir hataya düşmemek için `.link`i TAMAMEN muaf tutmuyoruz artık: çıplak
/// bir bağlantı (`/pull/14/files#diff-abc123`) görünür kalırken, yolu ya da
/// sorgusu bir jeton TAŞIYAN bir bağlantı (parola sıfırlama, magic-link,
/// presigned URL) maskelenir — omuz üstünden okumaya karşı bu özelliğin var
/// olma sebebi tam olarak bu senaryo, "bağlantı" olması onu bağışık kılmaz.
///
/// `.file` hâlâ tamamen muaf (I4, ikinci tur): bir dosya yolu sır değildir,
/// kartlar arasında ayrım yapabilmek için kullanıcının onu okuyabilmesi
/// gerekir — Finder'dan sürüklenen bir ekran görüntüsü yolu, harf+rakam
/// karışımı uzun bir dosya adı yüzünden "yüksek entropili jeton" gibi
/// görünüyordu.
func shouldMask(kind: ClipKind, text: String?) -> Bool {
    guard let text else { return false }
    if kind == .link { return SensitivePatterns.isSensitiveLink(text) }
    guard kind != .file else { return false }
    return SensitivePatterns.isSensitive(text)
}
