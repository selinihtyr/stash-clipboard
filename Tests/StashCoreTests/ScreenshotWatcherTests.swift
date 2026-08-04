import Testing
import Foundation
import Store
import PasteboardKit
@testable import StashCore

// `FakeCapturePasteboard`, `CaptureCoordinatorTests.swift`te tanımlı (`private`
// değil, aynı hedefte) — Test 5 (çift depolama önleme) burada da onu
// kullanıyor: gerçek panodan gelen bir yakalama ile ekran görüntüsü
// klasöründen gelen AYNI baytların tek satırda birleştiğini kanıtlamak için
// gerçek `CaptureCoordinator`ı da devreye sokuyor.

// `@MainActor` DEĞİL: `ScreenshotClassifying`in protokol gereksinimi
// `nonisolated` — testler zaten `@MainActor` içinde çağırıyor, `@unchecked
// Sendable` bunu güvenle üstleniyor (bkz. `FakeCapturePasteboard`teki aynı
// desen).
// Dosya adına (tam yola değil) göre anahtarlanıyor: `NSTemporaryDirectory()`
// `/var/folders/…` döndürüyor ama `FileManager.contentsOfDirectory` `/var`ın
// gerçek hedefi olan `/private/var/folders/…`i döndürüyor (elle doğrulandı —
// `URL.resolvingSymlinksInPath()` bu ikame sembolik bağlantıyı ÇÖZMÜYOR,
// `readdir` tabanlı dizin listelemesi çözüyor). Testte kurduğumuz `URL` ile
// izleyicinin gördüğü `URL` bu yüzden tam yol olarak asla eşleşmez; dosya adı
// bu tutarsızlıktan bağımsız, gerçek üretim kodunda da (izleyici her zaman
// KENDİ `contentsOfDirectory` sonucundaki URL'leri karşılaştırıyor, dışarıdan
// gelen bir kopyayla değil) bu sorun hiç oluşmuyor — yalnızca testin kendi
// bağımsız yol inşası için gerekli bir uyarlama.
private final class FakeScreenshotClassifier: ScreenshotClassifying, @unchecked Sendable {
    enum Verdict { case yes, no, unknown }
    var verdicts: [String: Verdict] = [:]
    private(set) var callCounts: [String: Int] = [:]

    func isScreenCapture(at url: URL) -> Bool? {
        let key = url.lastPathComponent
        callCounts[key, default: 0] += 1
        switch verdicts[key] ?? .no {
        case .yes: return true
        case .no: return false
        case .unknown: return nil
        }
    }
}

private struct SimulatedPermissionDenial: Error {}

private final class FailingScreenshotDirectoryReader: ScreenshotDirectoryReading, @unchecked Sendable {
    func contentsOfDirectory(at url: URL) throws -> [ScreenshotFileInfo] {
        throw SimulatedPermissionDenial()
    }
}

@MainActor
private func makeStore() throws -> ClipStore {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-screenshot-watcher-store-\(UUID().uuidString)")
    return try ClipStore(directory: dir)
}

private func makeFolder() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-screenshot-watcher-folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - Test kuralı: yeni, nitelikli bir dosya içe aktarılır

@MainActor @Test func newQualifyingFileIsIngestedOnceItStabilizes() throws {
    let store = try makeStore()
    let folderURL = try makeFolder()
    let classifier = FakeScreenshotClassifier()
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL }, classifier: classifier)
    watcher.start()
    #expect(watcher.status == .watching(folderURL))

    let fileURL = folderURL.appendingPathComponent("Screenshot 2026-08-04.png")
    try Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03]).write(to: fileURL)
    classifier.verdicts[fileURL.lastPathComponent] = .yes

    watcher.tick() // ilk gözlem: yalnızca boyut kaydediliyor, henüz sınıflandırılmıyor
    #expect(try store.recent(limit: 10).isEmpty)

    watcher.tick() // boyut bir öncekiyle aynı: "durulmuş" sayılıp sınıflandırılıyor
    let rows = try store.recent(limit: 10)
    #expect(rows.count == 1)
    #expect(rows.first?.kind == .image)
    // Görev kuralı 5: kaynak `loginwindow` değil, uygulamanın kendi sesi.
    #expect(rows.first?.sourceName == "Ekran görüntüsü")
    let imagePath = try #require(rows.first?.imagePath)
    #expect(FileManager.default.fileExists(atPath: imagePath))
}

// MARK: - Test kuralı: izlemeden önce var olan bir dosya asla içe aktarılmaz

@MainActor @Test func preExistingFileAtStartTimeIsNeverIngested() throws {
    let store = try makeStore()
    let folderURL = try makeFolder()
    let fileURL = folderURL.appendingPathComponent("old-shot.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

    let classifier = FakeScreenshotClassifier()
    // Kasıtlı olarak "evet, gerçek bir ekran görüntüsü" — yine de sonuç
    // değişmemeli, çünkü izleme başlamadan önce zaten oradaydı (görev
    // kuralı 3).
    classifier.verdicts[fileURL.lastPathComponent] = .yes
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL }, classifier: classifier)
    watcher.start()

    watcher.tick(); watcher.tick(); watcher.tick()

    #expect(try store.recent(limit: 10).isEmpty)
}

// MARK: - Test kuralı: gerçek bir ekran görüntüsü olmayan dosya içe aktarılmaz

@MainActor @Test func nonScreenshotFileIsNeverIngested() throws {
    let store = try makeStore()
    let folderURL = try makeFolder()
    let classifier = FakeScreenshotClassifier() // verdict kaydı yok -> .no
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL },
                                    classifier: classifier, maxClassificationAttempts: 2)
    watcher.start()

    let fileURL = folderURL.appendingPathComponent("random-desktop-file.png")
    try Data([0xFF, 0xD8, 0xFF]).write(to: fileURL)

    watcher.tick() // gözlem
    watcher.tick() // durulmuş, 1. sınıflandırma denemesi: hayır
    watcher.tick() // 2. deneme: hayır -> vazgeçildi (maxClassificationAttempts: 2)

    #expect(try store.recent(limit: 10).isEmpty)
    #expect(classifier.callCounts[fileURL.lastPathComponent] == 2)
}

// MARK: - Test kuralı: belirlenemeyen bir dosya içe aktarılmaz

@MainActor @Test func unclassifiableFileIsNeverIngestedIfItStaysUnclassifiableForever() throws {
    let store = try makeStore()
    let folderURL = try makeFolder()
    let classifier = FakeScreenshotClassifier()
    let fileURL = folderURL.appendingPathComponent("mystery.png")
    classifier.verdicts[fileURL.lastPathComponent] = .unknown // Spotlight öğesi hiç çözülemiyor
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL },
                                    classifier: classifier, maxClassificationAttempts: 2)
    watcher.start()
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

    watcher.tick(); watcher.tick(); watcher.tick()

    #expect(try store.recent(limit: 10).isEmpty)
}

// MARK: - Sınıflandırma yeniden denenir: geçici "belirlenemedi" bir ekran
// görüntüsünü sonsuza dek kaçırmaz (bkz. `ScreenshotWatcher.
// defaultMaxClassificationAttempts` üzerindeki gerekçe: xattr yazmak
// `MDItemCopyAttribute`in onu ANINDA görmesini garanti etmiyor).

@MainActor @Test func aFileThatBecomesClassifiableAfterARetryIsStillIngested() throws {
    let store = try makeStore()
    let folderURL = try makeFolder()
    let classifier = FakeScreenshotClassifier()
    let fileURL = folderURL.appendingPathComponent("indexing-delay.png")
    classifier.verdicts[fileURL.lastPathComponent] = .unknown
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL },
                                    classifier: classifier, maxClassificationAttempts: 10)
    watcher.start()
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

    watcher.tick() // gözlem
    watcher.tick() // durulmuş, deneme 1: belirlenemedi
    watcher.tick() // deneme 2: belirlenemedi
    #expect(try store.recent(limit: 10).isEmpty)

    // Spotlight sonunda dosyayı indeksledi.
    classifier.verdicts[fileURL.lastPathComponent] = .yes
    watcher.tick() // deneme 3: evet -> içe aktarılır

    #expect(try store.recent(limit: 10).count == 1)
}

// MARK: - Test kuralı: aynı görsel panodan da gelirse tek satır (dedup)

@MainActor @Test func sameImageArrivingViaClipboardAndScreenshotFolderYieldsOneRow() throws {
    let store = try makeStore()
    let pb = FakeCapturePasteboard()
    let capture = ClipCapture(pasteboard: pb, policy: CapturePolicy())
    let coordinator = CaptureCoordinator(store: store, capture: capture)
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    pb.putImage(png)
    coordinator.tick() // panodan bir satır

    let folderURL = try makeFolder()
    let classifier = FakeScreenshotClassifier()
    let fileURL = folderURL.appendingPathComponent("Screenshot dup.png")
    try png.write(to: fileURL) // BİREBİR aynı baytlar
    classifier.verdicts[fileURL.lastPathComponent] = .yes
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL }, classifier: classifier)
    watcher.start()
    watcher.tick(); watcher.tick()

    let rows = try store.recent(limit: 10)
    #expect(rows.count == 1) // ikinci bir satır AÇILMADI, mevcutla birleşti
}

// MARK: - Test kuralı: eksik ya da okunamayan klasör çökmez

@MainActor @Test func missingFolderDoesNotCrash() throws {
    let store = try makeStore()
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-screenshot-does-not-exist-\(UUID().uuidString)")
    let watcher = ScreenshotWatcher(store: store, folder: { missing })
    watcher.start()
    #expect(watcher.status == .folderMissing(missing))
    watcher.tick(); watcher.tick() // çökmemeli
    #expect(try store.recent(limit: 10).isEmpty)
}

@MainActor @Test func unreadableFolderReportsPermissionDeniedAndDoesNotCrash() throws {
    let store = try makeStore()
    let folderURL = try makeFolder() // klasör GERÇEKTEN var; sahte okuyucu reddediyor
    var observedStatuses: [ScreenshotWatchStatus] = []
    let watcher = ScreenshotWatcher(store: store, folder: { folderURL },
                                    reader: FailingScreenshotDirectoryReader())
    watcher.onStatusChange = { observedStatuses.append($0) }
    watcher.start()

    #expect(watcher.status == .permissionDenied)
    #expect(observedStatuses.contains(.permissionDenied))
    watcher.tick() // çökmemeli; izleyici zaten kendini durdurmuş olmalı
    #expect(try store.recent(limit: 10).isEmpty)
}

// MARK: - Gerçek Spotlight sınıflandırıcının duman testi (bkz. `mdls
// -name kMDItemIsScreenCapture` ile elle doğrulanan davranış)

@Test func spotlightClassifierDoesNotFlagAnOrdinaryFileAsAScreenshot() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-classifier-smoke-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("ordinary.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

    let result = SpotlightScreenshotClassifier().isScreenCapture(at: file)

    #expect(result != true)
}
