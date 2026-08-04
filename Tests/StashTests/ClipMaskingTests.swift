import Testing
import Store
@testable import Stash

// Fix round 1, bulgu 1: SensitivePatterns kind'dan habersiz olduğu için
// sorgu dizesi/fragment içeren sıradan bağlantılar "yüksek entropili jeton"
// gibi görünüp maskeleniyordu. shouldMask, ClipCapture'ın zaten yaptığı
// .link sınıflandırmasına güvenerek bunu düzeltir — SensitivePatterns'ın
// kendisi kind'dan bağımsız kalmaya devam eder.

@Test func linkClipTextIsNeverMasked() {
    let url = "https://github.com/selingoncu/stash-clipboard/pull/14/files#diff-abc123"
    #expect(!shouldMask(kind: .link, text: url))
}

@Test func nonLinkHighEntropyTokenIsStillMasked() {
    #expect(shouldMask(kind: .text, text: "ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"))
}

// I4: `file` birinci sınıf bir klip türü ve `shouldMask` yalnızca `.link`i
// muaf tutuyordu; Finder'dan sürüklenen bir ekran görüntüsü yolu "yüksek
// entropili jeton" gibi görünüp maskeleniyordu — dosya yolu sır değil,
// kullanıcının kartlar arasında ayrım yapabilmesi için okuyabilmesi gerekir.
@Test func fileClipTextIsNeverMasked() {
    let path = "/Users/selin/Downloads/IMG_20260804_113355.png"
    #expect(!shouldMask(kind: .file, text: path))
}
