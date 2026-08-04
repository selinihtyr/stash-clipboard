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

// I4, üçüncü tur, bulgu 3: `shouldMask` `.link`i eskiden `SensitivePatterns`e
// hiç sormadan koşulsuz muaf tutuyordu — ClipCapture.isLink her tek-jetonlu
// http(s) dizesini `.link` sayar, bu yüzden bir parola sıfırlama/magic-link
// bağlantısı hiçbir zaman `SensitivePatterns`e uğramazdı. `isSensitiveLink`,
// bağlantıyı yol/sorgu parçalarına ayırıp yalnızca jeton TAŞIYAN
// bağlantıları maskeler; çıplak bir bağlantı hâlâ okunabilir kalır.

@Test func aPasswordResetLinkCarryingATokenIsMasked() {
    let link = "https://app.example.com/reset-password?token=aZ3xK9mQ2wP7vN4tL6cJ8sB1dF5gH0yU"
    #expect(shouldMask(kind: .link, text: link))
}

@Test func aMagicSignInLinkCarryingAJWTIsMasked() {
    let link = "https://app.example.com/auth/magic?token=" +
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJzdWIiOiIxMjM0NTY3ODkwIn0." +
        "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    #expect(shouldMask(kind: .link, text: link))
}

@Test func aPresignedS3URLIsMasked() {
    let link = "https://mybucket.s3.amazonaws.com/private/report.pdf" +
        "?X-Amz-Algorithm=AWS4-HMAC-SHA256" +
        "&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260804%2Fus-east-1%2Fs3%2Faws4_request" +
        "&X-Amz-Date=20260804T113355Z&X-Amz-Expires=3600" +
        "&X-Amz-Signature=9f8e7d6c5b4a3928176e5d4c3b2a1908f7e6d5c4b3a29181716f5e4d3c2b1a0"
    #expect(shouldMask(kind: .link, text: link))
}

@Test func aBareLinkWithNoTokenIsStillNeverMasked() {
    let url = "https://github.com/selingoncu/stash-clipboard/pull/14/files#diff-abc123"
    #expect(!shouldMask(kind: .link, text: url))
}

@Test func anOrdinarySearchLinkIsStillNeverMasked() {
    #expect(!shouldMask(kind: .link, text: "https://www.google.com/search?q=swift+concurrency"))
}
