import Testing
import Foundation
import Store
import Filters
import PasteEngine
@testable import StashCore

final class RecordingWriter: PasteWriting {
    var lastText: String?
    var lastImage: Data?
    var changeCount = 0
    func writeText(_ text: String, plainOnly: Bool) -> Int {
        lastText = text
        changeCount += 1
        return changeCount
    }
    func writeImage(_ data: Data) -> Int {
        lastImage = data
        changeCount += 1
        return changeCount
    }
}

final class TrustedKeys: KeystrokeSending {
    var isTrusted = true
    func sendCommandV() -> Bool { true }
}

/// Testlerin çoğu, gerçek odak geri vermeyle değil `pasteSelected`/`attemptPaste`in
/// davranışıyla ilgileniyor: bu, `proceed`i hemen çağırarak zinciri (yaz →
/// restoreFocus → deliver → completion) senkron bitiriyor, böylece aşağıdaki
/// #expect'ler çağrının hemen ardından güvenle okunabiliyor.
func immediateFocusRestoration(_ proceed: @escaping () -> Void) { proceed() }

@MainActor
private func makeModel(_ texts: [String]) throws -> (StripModel, ClipStore, RecordingWriter) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-core-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    for (i, text) in texts.enumerated() {
        try store.insert(Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                              kind: .text, text: text, imagePath: nil, sourceBundleID: nil,
                              sourceName: nil, pinned: false, shelfID: nil,
                              contentHash: text, byteSize: text.utf8.count))
    }
    let writer = RecordingWriter()
    let model = StripModel(store: store,
                           engine: PasteEngine(pasteboard: writer, keystrokes: TrustedKeys()),
                           settings: .defaults)
    try model.reload()
    return (model, store, writer)
}

@MainActor @Test func visibleStartsWithEverythingNewestFirst() throws {
    let (model, _, _) = try makeModel(["bir", "iki", "üç"])
    #expect(model.visible.map(\.text) == ["üç", "iki", "bir"])
}

@MainActor @Test func typingFiltersTheStrip() throws {
    let (model, _, _) = try makeModel(["docker compose", "brew install"])
    model.query = "brew"
    try model.reload()
    #expect(model.visible.map(\.text) == ["brew install"])
}

@MainActor @Test func selectionResetsToTheFirstCardWhenTheListChanges() throws {
    // Süzme sonrası eski indekste kalmak yanlış kartı yapıştırmaya yol açar.
    let (model, _, _) = try makeModel(["bir", "iki", "üç"])
    model.moveSelection(by: 2)
    #expect(model.selectedIndex == 2)
    model.query = "bir"
    try model.reload()
    #expect(model.selectedIndex == 0)
}

@MainActor @Test func selectionCannotRunPastTheEnds() throws {
    let (model, _, _) = try makeModel(["bir", "iki"])
    model.moveSelection(by: -5)
    #expect(model.selectedIndex == 0)
    model.moveSelection(by: 99)
    #expect(model.selectedIndex == 1)
}

@MainActor @Test func pastingSelectedSendsTheCardsText() throws {
    let (model, _, writer) = try makeModel(["bir", "iki"])
    var outcome: PasteOutcome?
    model.pasteSelected(applyingFilters: false, restoreFocus: immediateFocusRestoration) { outcome = $0 }
    #expect(writer.lastText == "iki")
    #expect(outcome == .pastedIntoFrontmostApp)
}

@MainActor @Test func pastingWithFiltersUsesTheSettingsFilterList() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-core-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    try store.insert(Clip(id: UUID(), createdAt: Date(), kind: .text, text: "  a   b  ",
                          imagePath: nil, sourceBundleID: nil, sourceName: nil, pinned: false,
                          shelfID: nil, contentHash: "x", byteSize: 8))
    var settings = Settings.defaults
    settings.activeFilters = [.collapseWhitespace]
    let writer = RecordingWriter()
    let model = StripModel(store: store,
                           engine: PasteEngine(pasteboard: writer, keystrokes: TrustedKeys()),
                           settings: settings)
    try model.reload()
    model.pasteSelected(applyingFilters: true, restoreFocus: immediateFocusRestoration) { _ in }
    #expect(writer.lastText == "a b")
}

@MainActor @Test func pinnedTabShowsOnlyPinnedCards() throws {
    let (model, store, _) = try makeModel(["bir", "iki"])
    try store.setPinned(true, id: model.visible[1].id)
    model.tab = .pinned
    try model.reload()
    #expect(model.visible.map(\.text) == ["bir"])
}

@MainActor @Test func shelfTabShowsOnlyItsOwnCards() throws {
    let (model, store, _) = try makeModel(["bir", "iki"])
    let shelf = try model.createShelf(name: "İş")
    try store.setShelf(shelf.id, id: model.visible[1].id)
    model.tab = .shelf(shelf.id)
    try model.reload()
    #expect(model.visible.map(\.text) == ["bir"])
}

@MainActor @Test func reloadPicksUpShelvesCreatedThroughTheStore() throws {
    // reload() her çağrıldığında raf listesini de tazeler; sekme çubuğu
    // model.shelves'i doğrudan gözlemlediği için bu, yeni bir rafın hemen
    // görünmesini sağlıyor.
    let (model, store, _) = try makeModel(["bir"])
    #expect(model.shelves.isEmpty)
    _ = try store.createShelf(name: "İş")
    try model.reload()
    #expect(model.shelves.map(\.name) == ["İş"])
}

@MainActor @Test func deletingTheActiveShelfFallsBackToAllOnReload() throws {
    // Task 13 rafları silmek için bir UI ekleyecek; o an geldiğinde aktif
    // tab silinen rafa işaret ediyor olabilir. reload() kendini düzeltip
    // .all'a dönmeli, yoksa kullanıcı boş bir şeritte hiçbir sekmenin
    // seçili görünmediği bir çıkmaza düşer.
    let (model, store, _) = try makeModel(["bir", "iki"])
    let shelf = try model.createShelf(name: "İş")
    model.tab = .shelf(shelf.id)
    try model.reload()
    try store.deleteShelf(shelf.id)
    try model.reload()
    #expect(model.tab == .all)
    #expect(model.visible.map(\.text) == ["iki", "bir"])
}

@MainActor @Test func pinnedShelfAndImageTabsStillFindTheirCardsPastThePageSize() throws {
    // C2: reload() eskiden `recent(limit: 300)` çekip tab'a göre bellekte
    // süzüyordu. 300'den FAZLA daha yeni ilgisiz klip eklendiğinde sabit/
    // rafa konmuş/görsel klip artık en yeni 300'ün dışında kalıyor ve ilgili
    // sekme sonsuza dek boş görünüyordu — kullanıcı bir şeyi sabitler,
    // günler sonra Sabitlenen sekmesi boştur.
    let (model, store, _) = try makeModel(["bir", "iki"])
    let pinnedID = try #require(model.visible.first { $0.text == "bir" }?.id)
    try store.setPinned(true, id: pinnedID)
    let shelf = try model.createShelf(name: "İş")
    let shelvedID = try #require(model.visible.first { $0.text == "iki" }?.id)
    try store.setShelf(shelf.id, id: shelvedID)
    let imageClip = Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 5), kind: .image,
                         text: nil, imagePath: nil, sourceBundleID: nil, sourceName: nil,
                         pinned: false, shelfID: nil, contentHash: "img-1", byteSize: 10)
    try store.insert(imageClip)

    // Sayfa boyutunu (300) rahatça aşan sayıda, hepsi daha yeni, ilgisiz klip.
    for i in 0..<400 {
        try store.insert(Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000 + Double(i)),
                              kind: .text, text: "junk-\(i)", imagePath: nil, sourceBundleID: nil,
                              sourceName: nil, pinned: false, shelfID: nil,
                              contentHash: "junk-\(i)", byteSize: 4))
    }

    model.tab = .pinned
    try model.reload()
    #expect(model.visible.map(\.id) == [pinnedID])

    model.tab = .images
    try model.reload()
    #expect(model.visible.map(\.id) == [imageClip.id])

    model.tab = .shelf(shelf.id)
    try model.reload()
    #expect(model.visible.map(\.id) == [shelvedID])
}

@MainActor @Test func attemptPasteReportsNothingSelectedForAnEmptyStrip() throws {
    let (model, _, _) = try makeModel([])
    var attempt: StripModel.PasteAttempt?
    model.attemptPaste(applyingFilters: false, restoreFocus: immediateFocusRestoration) { attempt = $0 }
    #expect(attempt == .nothingSelected)
}

@MainActor @Test func attemptPasteReportsNothingToPasteForAPrunedImageCard() throws {
    // I3: bir görsel budandığında satır kalır ama imagePath nil'e düşer —
    // kart görünür ve seçili olabilir, ama yapıştıracak içeriği yok. Eskiden
    // bu, hiçbir kart seçili olmamasıyla aynı `nil`e düşüyordu; ↵'e basmak
    // görünür bir geri bildirim olmadan hiçbir şey yapmıyordu.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-core-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    try store.insert(Clip(id: UUID(), createdAt: Date(), kind: .image, text: nil,
                          imagePath: nil, sourceBundleID: nil, sourceName: nil,
                          pinned: false, shelfID: nil, contentHash: "pruned-img", byteSize: 0))
    let model = StripModel(store: store,
                           engine: PasteEngine(pasteboard: RecordingWriter(), keystrokes: TrustedKeys()),
                           settings: .defaults)
    try model.reload()
    var attempt: StripModel.PasteAttempt?
    model.attemptPaste(applyingFilters: false, restoreFocus: immediateFocusRestoration) { attempt = $0 }
    #expect(attempt == .nothingToPaste)
}

@MainActor @Test func attemptPasteReportsTheOutcomeForAPasteableCard() throws {
    let (model, _, _) = try makeModel(["bir", "iki"])
    var attempt: StripModel.PasteAttempt?
    model.attemptPaste(applyingFilters: false, restoreFocus: immediateFocusRestoration) { attempt = $0 }
    #expect(attempt == .outcome(.pastedIntoFrontmostApp))
}

// MARK: - Odak geri verme sırası (bkz. PasteEngine.FocusRestoration gerekçesi)

@MainActor @Test func attemptPasteDoesNotDeliverUntilRestoreFocusProceeds() throws {
    // AppDelegate'in gerçek `restoreFocus` implementasyonu paneli kapatıp
    // `proceed`i BİR SONRAKİ run loop turuna erteliyor — bu test, StripModel
    // katmanının bunu zorlamadığını (ama bozmadığını da) doğruluyor: engine'e
    // kadar hiçbir ara katman `proceed`i erkenden çağırmıyor.
    let (model, _, writer) = try makeModel(["bir", "iki"])
    var storedProceed: (() -> Void)?
    var attempt: StripModel.PasteAttempt?
    model.attemptPaste(applyingFilters: false, restoreFocus: { proceed in storedProceed = proceed }) {
        attempt = $0
    }
    #expect(writer.lastText == "iki", "pano yazımı restoreFocus çağrılmadan önce olmuş olmalı")
    #expect(attempt == nil, "restoreFocus proceed'i henüz çağırmadıysa sonuç gelmemeli")
    storedProceed?()
    #expect(attempt == .outcome(.pastedIntoFrontmostApp))
}

// MARK: - Kart-başına eylemler (hover yolu, seçili karttan bağımsız)

@MainActor @Test func pinningAClipThatIsNotSelectedDoesNotMoveTheSelection() throws {
    let (model, _, _) = try makeModel(["bir", "iki", "üç"])
    model.select(index: 2) // "bir"
    let selectedID = model.visible[2].id
    let otherID = model.visible[0].id // "üç", not selected
    try model.togglePin(id: otherID)
    #expect(model.selectedIndex == model.visible.firstIndex(where: { $0.id == selectedID }))
    #expect(model.visible[model.selectedIndex].id == selectedID)
}

@MainActor @Test func deletingANonSelectedClipLeavesTheSelectionOnTheSameClip() throws {
    let (model, _, _) = try makeModel(["bir", "iki", "üç"])
    model.select(index: 2) // "bir", last in list
    let selectedID = model.visible[2].id
    let victimID = model.visible[0].id // "üç", not selected
    try model.delete(id: victimID)
    #expect(model.visible[model.selectedIndex].id == selectedID)
}

@MainActor @Test func deletingTheSelectedClipLeavesAValidSelection() throws {
    let (model, _, _) = try makeModel(["bir", "iki", "üç"])
    model.select(index: 1) // "iki", the middle card
    let selectedID = model.visible[1].id
    try model.delete(id: selectedID)
    #expect(model.visible.indices.contains(model.selectedIndex))
    #expect(!model.visible.contains { $0.id == selectedID })
}

@MainActor @Test func deletingTheLastCardLeavesAnEmptyNonCrashingState() throws {
    let (model, _, _) = try makeModel(["tek"])
    let onlyID = model.visible[0].id
    try model.delete(id: onlyID)
    #expect(model.visible.isEmpty)
    #expect(!model.visible.indices.contains(model.selectedIndex))
}

@MainActor @Test func movingAClipToAShelfWorksOnTheGivenClipNotTheSelection() throws {
    let (model, _, _) = try makeModel(["bir", "iki"])
    let shelf = try model.createShelf(name: "İş")
    model.select(index: 0) // "iki"
    let selectedID = model.visible[0].id
    let movedID = model.visible[1].id // "bir", not selected
    try model.moveToShelf(id: movedID, shelfID: shelf.id)
    #expect(model.visible[model.selectedIndex].id == selectedID)
    model.tab = .shelf(shelf.id)
    try model.reload()
    #expect(model.visible.map(\.id) == [movedID])
}

@MainActor @Test func defaultBlocklistCoversThePasswordManagers() {
    #expect(Settings.defaults.blockedBundleIDs.contains("com.1password.1password"))
    #expect(Settings.defaults.blockedBundleIDs.contains("com.apple.keychainaccess"))
}
