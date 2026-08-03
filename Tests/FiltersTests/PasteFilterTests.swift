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
    let result = apply([.straightenQuotes, .collapseWhitespace], to: "  “a”   “b”  ")
    #expect(result == "\"a\" \"b\"")
}

@Test func plainTextIsIdentityOnAStringItOnlyMattersAtThePasteboardLayer() {
    // .plainText metni değiştirmez; anlamı "RTF/HTML temsillerini yazma"dır
    // ve PasteEngine'de karşılığını bulur. Burada kimlik fonksiyonu olması
    // filtre listesinin tek tip kalmasını sağlıyor.
    #expect(apply([.plainText], to: "a b") == "a b")
}
