import Testing
import HotKey
@testable import Stash

// reconcileHotKeyChange, AppDelegate'in gerçek Carbon kaydını ve NSAlert'i
// çevreleyen ince bir kabuk etrafında saf karar mantığını izole eder — bu
// dosyadaki testler ne gerçek bir global kısayol kaydediyor ne de bir
// pencere açıyor; sadece "register" closure'ının döndürdüğü sonuçlara göre
// hangi kombinasyonun kazandığını doğruluyor.

private let comboA = KeyCombo(keyCode: KeyCombo.keyCodeV, modifiers: KeyCombo.command | KeyCombo.option)
private let comboB = KeyCombo(keyCode: KeyCombo.keyCodeV, modifiers: KeyCombo.command | KeyCombo.control)

@Test func unchangedComboNeverCallsRegisterAndCountsAsApplied() {
    // Filtre/kara liste/raf değişiklikleri de aynı onChange yolundan geçiyor;
    // kombinasyon değişmediyse gereksiz bir unregister/register döngüsüne
    // girmemeliyiz (fix round 1, bulgu 1'in üçüncü parçası).
    var callCount = 0
    let outcome = reconcileHotKeyChange(from: comboA, to: comboA) { _ in
        callCount += 1
        return .success(())
    }
    #expect(outcome == .applied(comboA))
    #expect(callCount == 0)
}

@Test func successfulNewComboIsApplied() {
    let outcome = reconcileHotKeyChange(from: comboA, to: comboB) { combo in
        #expect(combo == comboB)
        return .success(())
    }
    #expect(outcome == .applied(comboB))
}

@Test func failedNewComboRevertsToThePreviousWorkingCombo() {
    // Kritik bulgu: yeni kombinasyon reddedilirse kullanıcı kısayolsuz
    // kalmamalı — önceki kaydediliyor. Sadece dönüş değerine bakmak
    // yetmiyor: geri yüklemenin gerçekten önceki kombinasyonla denendiğini
    // (sadece .reverted döndürüp hiçbir şey kaydetmeyen sahte bir uygulamayı
    // yakalamak için) çağrı geçmişini de kaydediyoruz.
    var attempts: [KeyCombo] = []
    let outcome = reconcileHotKeyChange(from: comboA, to: comboB) { combo in
        attempts.append(combo)
        return combo == comboB ? .failure(.alreadyTaken) : .success(())
    }
    #expect(outcome == .reverted(to: comboA, failureReason: .alreadyTaken))
    #expect(attempts == [comboB, comboA])
}

@Test func failedNewComboAndFailedRestoreReportsRevertFailed() {
    // Hem yeni hem eski kombinasyon kaydolamazsa (nadir ama olası) durum
    // örtbas edilmemeli — çağıran taraf bunu ayrı bir uyarıyla göstermeli.
    let outcome = reconcileHotKeyChange(from: comboA, to: comboB) { _ in .failure(.alreadyTaken) }
    #expect(outcome == .revertFailed(attempted: comboB, previous: comboA, failureReason: .alreadyTaken))
}

// MARK: - HotKeyCoordinator
//
// v0.1'de bildirilen hata burada yaşıyordu: "önceki kombinasyon" paylaşılan
// ayarlar mağazasından okunuyordu, ama ayarlar penceresi mağazayı onChange'i
// çağırmadan ÖNCE güncelliyor — yani karşılaştırma yeniyi yeniyle
// karşılaştırıyor, register hiç çağrılmıyor, eski kısayol kayıtlı kalıyordu.

@Test @MainActor func coordinatorRegistersEvenWhenTheStoreWasUpdatedFirst() {
    // Kullanıcının bildirdiği senaryonun birebir canlandırması: ayarlar
    // penceresi combo'yu paylaşılan mağazaya yazdıktan SONRA apply çağrılıyor.
    // Koordinatör kayıtlı kombinasyonu kendi tuttuğu için değişikliği yine de
    // görmeli ve gerçekten kaydetmeli.
    var settingsStoreCombo = comboA               // paylaşılan mağaza
    var attempts: [KeyCombo] = []
    let coordinator = HotKeyCoordinator(currentCombo: settingsStoreCombo) { combo in
        attempts.append(combo)
        return .success(())
    }
    settingsStoreCombo = comboB                   // pencere önce mağazayı günceller
    let outcome = coordinator.apply(settingsStoreCombo)
    #expect(attempts == [comboB])                 // hata varken burası boş kalıyordu
    #expect(outcome == .applied(comboB))
    #expect(coordinator.currentCombo == comboB)
}

@Test @MainActor func coordinatorSkipsRegistrationWhenTheComboIsUnchanged() {
    // Kısayolla ilgisi olmayan ayar değişiklikleri (filtre, kara liste, ses)
    // aynı yoldan geçiyor; bunlar gereksiz bir unregister/register döngüsü
    // tetiklememeli.
    var callCount = 0
    let coordinator = HotKeyCoordinator(currentCombo: comboA) { _ in
        callCount += 1
        return .success(())
    }
    #expect(coordinator.apply(comboA) == .applied(comboA))
    #expect(callCount == 0)
}

@Test @MainActor func coordinatorKeepsThePreviousComboAfterAFailedChange() {
    // Reddedilen kombinasyondan sonra "kayıtlı olan" hâlâ eski kombinasyon:
    // bir sonraki değişiklikte geri dönülecek aday da o olmalı, yoksa
    // koordinatör hiç kaydolmamış bir kombinasyona dönmeye çalışırdı.
    let coordinator = HotKeyCoordinator(currentCombo: comboA) { combo in
        combo == comboB ? .failure(.alreadyTaken) : .success(())
    }
    #expect(coordinator.apply(comboB) == .reverted(to: comboA, failureReason: .alreadyTaken))
    #expect(coordinator.currentCombo == comboA)
}

@Test @MainActor func coordinatorRegisterCurrentAlwaysAttemptsTheLaunchCombo() {
    // Açılış yolu: apply(currentCombo) "değişmedi" deyip kaydı atlardı —
    // uygulama hiç kısayolsuz açılırdı.
    var attempts: [KeyCombo] = []
    let coordinator = HotKeyCoordinator(currentCombo: comboA) { combo in
        attempts.append(combo)
        return .success(())
    }
    if case .failure(let error) = coordinator.registerCurrent() {
        Issue.record("açılış kaydı başarısız oldu: \(error)")
    }
    #expect(attempts == [comboA])
}
