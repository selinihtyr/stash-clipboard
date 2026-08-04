import Testing
@testable import PasteboardKit

@Test func cardNumbersAreMaskedToTheLastFour() {
    #expect(SensitivePatterns.isSensitive("4242 4242 4242 4242"))
    #expect(SensitivePatterns.mask("4242 4242 4242 4242") == "•••• 4242")
}

@Test func cardNumbersWithoutSpacesAreCaughtToo() {
    #expect(SensitivePatterns.isSensitive("4242424242424242"))
}

@Test func longRandomLookingTokensAreMasked() {
    #expect(SensitivePatterns.isSensitive("ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"))
}

@Test func ordinarySentencesAreNotSensitive() {
    // Yanlış pozitif maskeleme, maskelemenin kendisinden daha can sıkıcı olur.
    #expect(!SensitivePatterns.isSensitive("bugün hava çok güzel ve biraz uzun bir cümle"))
    #expect(!SensitivePatterns.isSensitive("brew install --cask maccy"))
}

@Test func shortStringsAreNeverTokens() {
    #expect(!SensitivePatterns.isSensitive("abc123"))
}

@Test func maskedTokensShowNothingButTheirLength() {
    let masked = SensitivePatterns.mask("ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8")
    #expect(masked.hasPrefix("••••"))
    #expect(!masked.contains("ghp_"))
}

// Fix round 1, bulgu 2: isCardNumber Luhn kontrolü olmadan 13-19 haneli her
// diziyi (ISBN, takip numarası, fatura kimliği) kart sanıyordu.

@Test func luhnValidTestCardNumberIsMasked() {
    // Stripe'ın herkese açık test kartı — gerçek, Luhn geçerli bir numara.
    #expect(SensitivePatterns.isSensitive("4242 4242 4242 4242"))
    #expect(SensitivePatterns.mask("4242 4242 4242 4242") == "•••• 4242")
}

@Test func isbn13LooksLikeACardButFailsLuhnSoItIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("978-3-16-148410-0"))
}

@Test func luhnInvalidSixteenDigitNumberIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("1234567812345678"))
}

// I4: eski kural (24+ karakter, harf+rakam, 12+ ayrı karakter) sıradan
// geliştirici dizelerini de "yüksek entropili jeton" sanıyordu. Yol/URL/DSN
// ayraçları ("/", ":", "@", ".") artık bunu eliyor — gerçek jetonlar bu
// karakterleri kullanmıyor.

@Test func aFilesystemPathIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("/Users/selin/Downloads/IMG_20260804_113355.png"))
}

@Test func aGitBranchNameIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("feat/stash-v1-rebase-2026"))
}

@Test func aDatabaseDSNIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("postgres://user:pw@localhost:5432/db"))
}

@Test func anAPIKeyShapedStringIsStillMasked() {
    #expect(SensitivePatterns.isSensitive("sk-ant-api03-AbCdEf123456789xyz"))
}

@Test func aFortyCharacterHexGitSHAStillMasksAsAnAcceptedCost() {
    // Ayraç kuralı bunu elemez (yalnızca onaltılık karakterler, ayraç yok);
    // bu, fix round 1'de zaten onaylanmış bilinçli bir maliyet olarak duruyor.
    #expect(SensitivePatterns.isSensitive("36b4497aa1c3de9074f2b8c1e5a6d3f90b1c2e47"))
}

// I4, ikinci tur: yapılandırılmış-tanımlayıcı muafiyeti "/ : @ ." içeren HER
// dizeyi elediği için gerçek kimlik bilgilerinin yaklaşık yarısını (base64
// alfabesinde "/" olasılığı %47) sessizce görünür bırakıyordu. Aşağıdaki
// tablo incelemedeki her satırı, iki yönde de sınıyor: gerçek kimlik
// bilgileri maskelenmeli, dosya yolu/dal/DSN gibi yapılandırılmış
// tanımlayıcılar görünür kalmalı.

@Test func aRealJWTIsMaskedDespiteContainingDots() {
    // jwt.io'nun herkese açık örneği: üç nokta-ayrılmış base64url parçası.
    // Eski kural "." içerdiği için bunu bir "yapılandırılmış tanımlayıcı"
    // sanıp görünür bırakıyordu.
    let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0." +
        "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    #expect(SensitivePatterns.isSensitive(jwt))
}

@Test func anAWSSecretAccessKeyIsMaskedDespiteContainingSlashes() {
    // AWS dokümantasyonunun herkese açık örnek anahtarı: tam 40 karakter,
    // içinde iki "/" var — eski kural bunu bu yüzden görünür bırakıyordu.
    #expect(SensitivePatterns.isSensitive("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"))
}

@Test func anAWSAccessKeyIdIsMasked() {
    // 20 karakter — genel 24+ eşiğinin altında kaldığı için ne eski ne de
    // önceki yeni kural bunu hiç yakalamıyordu; kendi biçim tespitçisi gerekir.
    #expect(SensitivePatterns.isSensitive("AKIAIOSFODNN7EXAMPLE"))
}

@Test func aJWTHiddenInsideAFilePathIsStillMasked() {
    // Bir kimlik bilgisini bir yolun İÇİNE gizlemek onu görünür kılmamalı:
    // "/tmp/" yapısal görünse de içindeki parça tek başına jeton biçiminde.
    let hidden = "/tmp/" +
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0." +
        "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" + "/abc"
    #expect(SensitivePatterns.isSensitive(hidden))
}

@Test func aGitHubPersonalAccessTokenIsMasked() {
    #expect(SensitivePatterns.isSensitive("ghp_16C7e42F292c6912E7710c838347Ae178B4a"))
}

@Test func aSlackBotTokenIsMasked() {
    #expect(SensitivePatterns.isSensitive("xoxb-123456789012-123456789012-abcdefghijklmnopqrstuvwx"))
}

@Test func aStripeLiveKeyIsMasked() {
    #expect(SensitivePatterns.isSensitive("sk_live_4eC39HqLyjWDarjtT1zdp7dcXYZ123"))
}

@Test func aSixtyFourCharacterHexDigestIsMasked() {
    #expect(SensitivePatterns.isSensitive(
        "a3f5c9e1b2d4f6a8c0e2b4d6f8a0c2e4b6d8f0a2c4e6b8d0f2a4c6e8b0d2f4a6"))
}

@Test func aFilesystemPathIsStillVisibleAfterTheFix() {
    #expect(!SensitivePatterns.isSensitive("/Users/selin/Downloads/IMG_20260804_113355.png"))
}

@Test func aGitBranchNameIsStillVisibleAfterTheFix() {
    #expect(!SensitivePatterns.isSensitive("feat/stash-v1-rebase-2026"))
}

@Test func aDatabaseDSNIsStillVisibleAfterTheFix() {
    #expect(!SensitivePatterns.isSensitive("postgres://user:pw@localhost:5432/db"))
}

// Bulgu 1 (BLOCKING): isTokenShapedSegment'in genel 24 karakter eşiğini
// yeniden kullanması, 40 karakterlik bir sırrın ortasına tek bir "/"
// koymanın her iki yarıyı da "jeton gibi değil" hale getirmesi anlamına
// geliyordu — `refish` yapısal muafiyeti sonra bu sahte "yol"u geçiriyordu.
// İncelemenin doğruladığı düzeltme: segment başına, 40'a EŞİT OLMA
// koşulu olmadan, büyük/küçük harf + rakam karışımı sinyaline dayanan
// ikinci bir 14 karakterlik kol.

@Test func aSlashBearingSecretJustOverTheOldFourteenCharSplitStillMasks() {
    // Ortadan "/" ile bölünmüş, her iki yarısı da büyük/küçük harf+rakam
    // karışımı taşıyan 32 karakterlik bir sır — eski kural (24+ tek
    // parça) bunu kaçırırdı, yeni 14 karakterlik kol yakalar.
    #expect(SensitivePatterns.isSensitive("aZ3xK9mQ2wP7v/N4tL6cJ8sB1dF5gH0y"))
}

@Test func aThirtyNineCharacterAWSSecretShapeIsStillMasked() {
    // Tam 40 karakter tespitçisinin bir eksiği kaçırdığı durum — segment
    // başına 14 karakterlik yeni kol bunu bağımsız olarak yakalıyor.
    #expect(SensitivePatterns.isSensitive("OhbVrpoiVgRV5IfLBcb/fnoGMbJmTPSIAoCLrZ3"))
}

@Test func aFortyOneCharacterAWSSecretShapeIsStillMasked() {
    #expect(SensitivePatterns.isSensitive("aWZkSBvrjn9Wvgfygw2w/MqZcUDIh7yfJs1ON43xK"))
}

// I4, üçüncü tur, bulgu 2: `looksStructural` yol/URL/dal-BAŞLANGICI
// biçimine daraltılınca ":" ya da "." ile ayrılmış (ama "/" ile
// BAŞLAMAYAN ya da hiç "/" TAŞIMAYAN) yapılandırılmış tanımlayıcılar bu
// muafiyetin dışında kaldı — maven koordinatı, docker imaj referansı,
// derleyici konumu, ISO zaman damgası, e-posta hepsi maskelenmeye
// başladı. Ayrıca tek bir segment içinde tarih+kelime karışımı olan bir
// dosya adı (24+ karakter, harf+rakam) tüm yol muafiyetini bozuyordu.

@Test func aMavenCoordinateIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("com.google.guava:guava:33.0.0-jre"))
}

@Test func aDockerImageReferenceIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("ghcr.io/selinihtyr/gathr-api:sha-3f2a1b9"))
}

@Test func aCompilerLocationIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("Sources/Store/ClipStore.swift:518:16"))
}

@Test func anISO8601TimestampIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("2026-08-04T11:33:55+03:00"))
}

@Test func anEmailWithADigitIsNotMasked() {
    #expect(!SensitivePatterns.isSensitive("selin.goncu+stash2026@example.com"))
}

@Test func aDateStampedScreenshotPathIsNotMasked() {
    // Tek bir >=24 karakterlik segment ("Screenshot_2026-08-04_at_11")
    // eskiden tüm yol muafiyetini bozuyordu — "_" ve "-" artık ayraç
    // sayıldığı için bu segment tarih/kelime parçalarına ayrılıyor.
    #expect(!SensitivePatterns.isSensitive(
        "/Users/selin/Downloads/Screenshot_2026-08-04_at_11.33.55.png"))
}

// Bu daraltmanın gerçek kimlik bilgilerini ele vermediğini doğrulayan
// karşı-testler: yukarıdaki hem gate (identifierish) hem de "_"/"-" ayraç
// genişlemesi hiçbirini gevşetmemeli.

@Test func aRealJWTIsStillMaskedAfterTheStructuralWidening() {
    let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0." +
        "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    #expect(SensitivePatterns.isSensitive(jwt))
}

@Test func aFortyHexGitSHAIsStillMaskedAfterTheStructuralWidening() {
    #expect(SensitivePatterns.isSensitive("36b4497aa1c3de9074f2b8c1e5a6d3f90b1c2e47"))
}

@Test func aSixtyFourHexDigestIsStillMaskedAfterTheStructuralWidening() {
    #expect(SensitivePatterns.isSensitive(
        "a3f5c9e1b2d4f6a8c0e2b4d6f8a0c2e4b6d8f0a2c4e6b8d0f2a4c6e8b0d2f4a6"))
}

@Test func aGitHubPATIsStillMaskedAfterTheStructuralWidening() {
    #expect(SensitivePatterns.isSensitive("ghp_16C7e42F292c6912E7710c838347Ae178B4a"))
}

@Test func anSKAntAPIKeyIsStillMaskedAfterTheStructuralWidening() {
    #expect(SensitivePatterns.isSensitive("sk-ant-api03-AbCdEf123456789xyz"))
}

@Test func aPEMPrivateKeyHeaderIsStillMasked() {
    #expect(SensitivePatterns.isSensitive("-----BEGIN RSA PRIVATE KEY-----MIIEowIBAAKCAQ"))
}
