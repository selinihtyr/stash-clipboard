import Testing
import Foundation
@testable import Store

private func makeStore() throws -> ClipStore {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-test-\(UUID().uuidString)")
    return try ClipStore(directory: dir)
}

private func textClip(_ text: String, at seconds: TimeInterval = 0) -> Clip {
    Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: seconds), kind: .text,
         text: text, imagePath: nil, sourceBundleID: nil, sourceName: nil,
         pinned: false, shelfID: nil, contentHash: text, byteSize: text.utf8.count)
}

@Test func searchMatchesAnywhereInTheTextAndIgnoresCase() throws {
    let store = try makeStore()
    try store.insert(textClip("docker compose up", at: 1))
    try store.insert(textClip("brew install maccy", at: 2))
    #expect(try store.search("COMPOSE", limit: 10).map(\.text) == ["docker compose up"])
}

@Test func searchEscapesWildcardsSoTheyMatchLiterally() throws {
    // Kullanıcı arama alanına % yazdığında bütün geçmişi getirmemeli;
    // LIKE joker karakterleri kaçırılmazsa tam olarak bu olur.
    let store = try makeStore()
    try store.insert(textClip("indirim %50", at: 1))
    try store.insert(textClip("başka bir şey", at: 2))
    #expect(try store.search("%", limit: 10).map(\.text) == ["indirim %50"])
}

@Test func pinningSurvivesAReadBack() throws {
    let store = try makeStore()
    let clip = textClip("sabit")
    try store.insert(clip)
    try store.setPinned(true, id: clip.id)
    #expect(try store.recent(limit: 10)[0].pinned == true)
}

@Test func shelfAssignmentSticksAndCanBeCleared() throws {
    let store = try makeStore()
    let clip = textClip("rafa")
    let shelf = UUID()
    try store.insert(clip)
    try store.setShelf(shelf, id: clip.id)
    #expect(try store.recent(limit: 10)[0].shelfID == shelf)
    try store.setShelf(nil, id: clip.id)
    #expect(try store.recent(limit: 10)[0].shelfID == nil)
}

@Test func deleteCreatedAfterRemovesOnlyTheRecentOnes() throws {
    let store = try makeStore()
    try store.insert(textClip("dün", at: 1_000))
    try store.insert(textClip("az önce", at: 9_000))
    try store.deleteCreated(after: Date(timeIntervalSince1970: 5_000))
    #expect(try store.recent(limit: 10).map(\.text) == ["dün"])
}

@Test func deleteCreatedAfterKeepsPinnedClips() throws {
    // deleteAllKeepsPinnedClips zaten deleteAll() için bu garantiyi kanıtlıyor;
    // deleteCreated(after:) kendi kesim tarihinden SONRA oluşmuş sabit bir klip
    // olmadan aynı korumaya sahip görünebilir ama aslında sınanmamış olurdu.
    let store = try makeStore()
    let kept = textClip("sabit ama yeni", at: 9_000)
    try store.insert(kept)
    try store.insert(textClip("yeni ve gidici", at: 9_500))
    try store.setPinned(true, id: kept.id)
    try store.deleteCreated(after: Date(timeIntervalSince1970: 5_000))
    #expect(try store.recent(limit: 10).map(\.text) == ["sabit ama yeni"])
}

@Test func deleteAllKeepsPinnedClips() throws {
    // "Tümünü temizle" sabitlediklerini de silseydi raf fikri anlamsız olurdu;
    // kullanıcı onları bilerek ayırmış.
    let store = try makeStore()
    let kept = textClip("sabit", at: 1)
    try store.insert(kept)
    try store.insert(textClip("gidici", at: 2))
    try store.setPinned(true, id: kept.id)
    try store.deleteAll()
    #expect(try store.recent(limit: 10).map(\.text) == ["sabit"])
}
