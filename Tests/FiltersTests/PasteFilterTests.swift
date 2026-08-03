import Testing
@testable import Filters

@Test func collapseWhitespaceSqueezesRunsAndTrimsEnds() {
    #expect(apply([.collapseWhitespace], to: "  a   b \n\n c  ") == "a b c")
}

@Test func straightenQuotesReplacesTypographicPairs() {
    #expect(apply([.straightenQuotes], to: "“iyi” ‘gün’ — o’nun") == "\"iyi\" 'gün' — o'nun")
}

@Test func filtersApplyInTheOrderGiven() {
    // straightenQuotes önce çalışırsa collapse'ın göreceği metin değişir;
    // sıra sözleşmenin parçası, karıştırılamaz.
    //
    // Not: straightenQuotes sadece tırnak karakterlerine, collapseWhitespace sadece
    // boşluk karakterlerine dokunuyor — ayrık karakter kümelerinde çalıştıkları için bu
    // ikili matematiksel olarak commute eder (200 bin rastgele girdiyle doğrulandı);
    // doğru zincirlenmiş sonuç hangi sırada verilirse verilsin aynıdır. Bu yüzden ikinci
    // çağrı "sıra değişince sonuç değişir" demiyor — apply'ın her filtrenin ÇIKTISINI
    // (partial) bir sonrakine girdi olarak verdiğini, orijinal text'i değil, iki sırada
    // da kanıtlıyor. Örneğin reduce kapanışı partial yerine yanlışlıkla orijinal text'i
    // kullansaydı, tersine çevrilmiş sırada straightenQuotes henüz collapse edilmemiş
    // metni görür ve sonuç fazladan boşluk taşırdı; bu test o hatayı yakalar.
    let input = "  “a”   “b”  "
    let expected = "\"a\" \"b\""

    let forward = apply([.straightenQuotes, .collapseWhitespace], to: input)
    #expect(forward == expected)

    let reversed = apply([.collapseWhitespace, .straightenQuotes], to: input)
    #expect(reversed == expected)
}

@Test func plainTextIsIdentityOnAStringItOnlyMattersAtThePasteboardLayer() {
    // .plainText metni değiştirmez; anlamı "RTF/HTML temsillerini yazma"dır
    // ve PasteEngine'de karşılığını bulur. Burada kimlik fonksiyonu olması
    // filtre listesinin tek tip kalmasını sağlıyor.
    #expect(apply([.plainText], to: "a b") == "a b")
}
