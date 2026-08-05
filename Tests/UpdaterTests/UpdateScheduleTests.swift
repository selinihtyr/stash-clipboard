import Foundation
import Testing
@testable import Updater

private let launch = Date(timeIntervalSince1970: 1_000_000)

@Test func theSwitchOffMeansNoNetworkAtAll() {
    // Kapalıysa hiçbir koşulda kontrol edilmez — "hemen hemen hiç" yeterli
    // değil: ağa çıkmayan bir Stash isteyen kullanıcıya verilen söz bu.
    #expect(UpdateSchedule.shouldCheck(enabled: false, lastCheck: nil,
                                       launchedAt: launch,
                                       now: launch.addingTimeInterval(10 * 86_400)) == false)
}

@Test func theFirstCheckWaitsInsteadOfFiringDuringLaunch() {
    // Açılış zaten izin istemleriyle dolu; oraya bir de ağ isteği sıkıştırmak
    // kötü bir ilk izlenim olurdu.
    #expect(UpdateSchedule.shouldCheck(enabled: true, lastCheck: nil,
                                       launchedAt: launch, now: launch) == false)
    #expect(UpdateSchedule.shouldCheck(enabled: true, lastCheck: nil, launchedAt: launch,
                                       now: launch.addingTimeInterval(UpdateSchedule.firstCheckDelay)))
}

@Test func afterACheckItWaitsADayNotEveryPoll() {
    let checked = launch.addingTimeInterval(600)
    #expect(UpdateSchedule.shouldCheck(enabled: true, lastCheck: checked, launchedAt: launch,
                                       now: checked.addingTimeInterval(3600)) == false)
    #expect(UpdateSchedule.shouldCheck(enabled: true, lastCheck: checked, launchedAt: launch,
                                       now: checked.addingTimeInterval(UpdateSchedule.interval)))
}

@Test func aClockMovedBackwardsDoesNotFreezeCheckingForever() {
    // Kullanıcı saati geri aldığında "son kontrol gelecekte" olur; farkı
    // işaretli okusaydık kontrol bir daha hiç çalışmazdı.
    let futureCheck = launch.addingTimeInterval(30 * 86_400)
    #expect(UpdateSchedule.shouldCheck(enabled: true, lastCheck: futureCheck,
                                       launchedAt: launch, now: launch))
}
