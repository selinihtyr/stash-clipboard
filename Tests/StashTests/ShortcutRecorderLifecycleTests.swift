import AppKit
import Testing
import Foundation
import HotKey
import Store
import StashCore
@testable import Stash

// I1: `ShortcutRecorder`in yerel `NSEvent` izleyicisi eskiden yalnızca
// SwiftUI'nin `.onDisappear`i tarafından kapatılıyordu. Ama Ayarlar penceresi
// `isReleasedWhenClosed = false` ile açılıyor ve AppDelegate kontrolcüyü
// tutuyor — bu yapılandırmada pencere kapanınca `.onDisappear` HİÇ
// tetiklenmiyor (reviewer'ın repro'su). Sonuç: kayıt sonsuza dek sürüyor,
// izleyici sıradaki her değiştiricisiz tuşu yutuyor, ilk değiştiricili tuş
// (ör. ⌘Q) sessizce yeni genel kısayol olarak kaydediliyor.
//
// Gerçek bir ekran olmadan reviewer'ın senaryosunu olabildiğince yakın
// tekrar ediyoruz: gerçek bir `SettingsWindowController` kuruyoruz (arkasında
// gerçek bir `ClipStore`), kaydı `controller.recorder` üzerinden gerçek
// "Değiştir" akışıyla aynı şekilde başlatıyoruz, sonra pencereyi
// close()/orderOut(_:) ile kapatıp izleyicinin GERÇEKTEN kaldırıldığını
// (`isMonitoring`) doğruluyoruz — sadece `isRecording` bayrağını değil.

@MainActor
private func makeController() throws -> (SettingsWindowController, ClipStore) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-settings-window-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    let settingsStore = SettingsStore(.defaults)
    let controller = SettingsWindowController(settingsStore: settingsStore, store: store) { _ in }
    return (controller, store)
}

@MainActor
@Test func closingTheWindowEndsRecordingAndRemovesTheMonitor() throws {
    let (controller, _) = try makeController()
    controller.recorder.start { _ in }
    #expect(controller.recorder.isRecording)
    #expect(controller.recorder.isMonitoring)

    // Kırmızı düğme ve ⌘W'nin ikisi de nihayetinde NSWindow.close()'a çıkar.
    controller.window?.close()

    #expect(!controller.recorder.isRecording)
    #expect(!controller.recorder.isMonitoring)
}

@MainActor
@Test func orderingOutTheWindowWithoutClosingAlsoEndsRecording() throws {
    // "Kapatma" tek yok-olma yolu değil; kayıt sadece close()'a bağlı
    // kalırsa pencere başka bir yolla (ör. ileride eklenecek bir gizleme
    // eylemi) ekrandan kalksa bile izleyici sızmaya devam eder.
    let (controller, _) = try makeController()
    controller.recorder.start { _ in }
    #expect(controller.recorder.isMonitoring)

    controller.window?.orderOut(nil)

    #expect(!controller.recorder.isRecording)
    #expect(!controller.recorder.isMonitoring)
}

@MainActor
@Test func reopeningSettingsAfterAnUnclosedRecordingStartsClean() throws {
    // Kullanıcı "Değiştir"e basıp vazgeçtiğinde pencere hiç kapanmayabilir
    // (ör. Ayarlar'ı menüden tekrar tetiklemek); present() yine de temiz,
    // kayıt-dışı bir durumla başlamalı.
    let (controller, _) = try makeController()
    controller.recorder.start { _ in }
    #expect(controller.recorder.isRecording)

    controller.present()

    #expect(!controller.recorder.isRecording)
    #expect(!controller.recorder.isMonitoring)
}
