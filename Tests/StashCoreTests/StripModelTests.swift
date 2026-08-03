import Testing
import Foundation
import Store
import Filters
import PasteEngine
@testable import StashCore

final class RecordingWriter: PasteWriting {
    var lastText: String?
    var lastImage: Data?
    func writeText(_ text: String, plainOnly: Bool) { lastText = text }
    func writeImage(_ data: Data) { lastImage = data }
}

final class TrustedKeys: KeystrokeSending {
    var isTrusted = true
    func sendCommandV() -> Bool { true }
}

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
    let outcome = model.pasteSelected(applyingFilters: false)
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
    _ = model.pasteSelected(applyingFilters: true)
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

@MainActor @Test func defaultBlocklistCoversThePasswordManagers() {
    #expect(Settings.defaults.blockedBundleIDs.contains("com.1password.1password"))
    #expect(Settings.defaults.blockedBundleIDs.contains("com.apple.keychainaccess"))
}
