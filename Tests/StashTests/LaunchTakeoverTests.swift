import Testing
@testable import Stash

// Açılışta eski kopyanın ölmesini beklerken sınırın olmaması, Stash'in hiç
// açılmaması demek. Bekleme döngüsü bu yüzden saf bir fonksiyon: gerçek bir
// süreç öldürmeden, gerçek zaman geçirmeden davranışı doğrulanabiliyor.

@Test func waitReturnsImmediatelyWhenThereIsNothingToWaitFor() {
    var ticks = 0
    #expect(waitUntil({ true }, ticks: 40, tick: { ticks += 1 }))
    #expect(ticks == 0)
}

@Test func waitStopsAsSoonAsTheConditionHolds() {
    var ticks = 0
    let done = waitUntil({ ticks >= 3 }, ticks: 40, tick: { ticks += 1 })
    #expect(done)
    #expect(ticks == 3)
}

@Test func waitGivesUpInsteadOfHangingTheLaunchForever() {
    // Takılmış bir eski kopya açılışı sonsuza kadar askıya almamalı:
    // kısayolsuz ama açık bir uygulama, hiç açılmayandan iyidir.
    var ticks = 0
    #expect(waitUntil({ false }, ticks: 5, tick: { ticks += 1 }) == false)
    #expect(ticks == 5)
}
