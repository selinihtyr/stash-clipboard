import Testing
import Foundation
@testable import Store

private func makeStore() throws -> ClipStore {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-shelf-\(UUID().uuidString)")
    return try ClipStore(directory: dir)
}

@Test func shelvesRoundTrip() throws {
    let store = try makeStore()
    let shelf = try store.createShelf(name: "İş")
    #expect(try store.shelves().map(\.name) == ["İş"])
    try store.renameShelf(shelf.id, to: "Kod")
    #expect(try store.shelves().map(\.name) == ["Kod"])
}

@Test func deletingAShelfReturnsItsCardsToTheMainList() throws {
    // Rafı silmek kartları silmemeli; kullanıcı klasörü kaldırıyor, içindekini
    // çöpe atmıyor.
    let store = try makeStore()
    let shelf = try store.createShelf(name: "İş")
    let clip = Clip(id: UUID(), createdAt: Date(), kind: .text, text: "a", imagePath: nil,
                    sourceBundleID: nil, sourceName: nil, pinned: false, shelfID: nil,
                    contentHash: "a", byteSize: 1)
    try store.insert(clip)
    try store.setShelf(shelf.id, id: clip.id)
    try store.deleteShelf(shelf.id)
    #expect(try store.recent(limit: 10).count == 1)
    #expect(try store.recent(limit: 10)[0].shelfID == nil)
}

@Test func shelfNamesAreTrimmedAndEmptyNamesRejected() throws {
    let store = try makeStore()
    #expect(try store.createShelf(name: "  İş  ").name == "İş")
    #expect(throws: StoreError.self) { _ = try store.createShelf(name: "   ") }
}

// Raf adı kullanıcı yazıyor; createShelf/renameShelf bağlı parametre
// kullanıyor çünkü bu projede elle tırnak-kaçışlı interpolasyon daha önce
// gerçek bir SQL-injection hatası olarak sevk edildi (bkz. upsert'in
// üstündeki yorum). Bu testler apostrof içeren bir isim geri gelmezse ya
// da çiftlenmiş/kaçmış haliyle gelirse kırılır — regresyonu naif
// interpolasyona yakalar.
@Test func shelfNameWithApostropheRoundTripsExactlyThroughCreate() throws {
    let store = try makeStore()
    _ = try store.createShelf(name: "Selin's")
    #expect(try store.shelves().map(\.name) == ["Selin's"])
}

@Test func shelfNameWithApostropheRoundTripsExactlyThroughRename() throws {
    let store = try makeStore()
    let shelf = try store.createShelf(name: "İş")
    try store.renameShelf(shelf.id, to: "Bob's İşler")
    #expect(try store.shelves().map(\.name) == ["Bob's İşler"])
}
