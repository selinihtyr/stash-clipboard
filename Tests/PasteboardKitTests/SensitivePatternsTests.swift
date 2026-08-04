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
