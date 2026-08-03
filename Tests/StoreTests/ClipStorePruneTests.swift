import Testing
import Foundation
@testable import Store

private func makeStore() throws -> ClipStore {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-test-\(UUID().uuidString)")
    return try ClipStore(directory: dir)
}

private func imageClip(_ store: ClipStore, bytes: Int, at seconds: TimeInterval,
                       pinned: Bool = false) throws -> Clip {
    let id = UUID()
    let path = store.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
    try Data(repeating: 0xAB, count: bytes).write(to: path)
    let clip = Clip(id: id, createdAt: Date(timeIntervalSince1970: seconds), kind: .image,
                    text: nil, imagePath: path.path, sourceBundleID: nil, sourceName: nil,
                    pinned: pinned, shelfID: nil, contentHash: id.uuidString, byteSize: bytes)
    try store.insert(clip)
    if pinned { try store.setPinned(true, id: id) }
    return clip
}

@Test func copyingTheSameTextTwiceMovesItToTheFrontInsteadOfDuplicating() throws {
    let store = try makeStore()
    let first = Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), kind: .text,
                     text: "aynı", imagePath: nil, sourceBundleID: nil, sourceName: nil,
                     pinned: false, shelfID: nil, contentHash: "aynı", byteSize: 4)
    try store.upsert(first)
    try store.upsert(Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 500), kind: .text,
                          text: "aynı", imagePath: nil, sourceBundleID: nil, sourceName: nil,
                          pinned: false, shelfID: nil, contentHash: "aynı", byteSize: 4))
    let all = try store.recent(limit: 10)
    #expect(all.count == 1)
    #expect(all[0].createdAt == Date(timeIntervalSince1970: 500))
}

@Test func imagesByteSizeCountsWhatIsOnDisk() throws {
    let store = try makeStore()
    _ = try imageClip(store, bytes: 1_000, at: 1)
    _ = try imageClip(store, bytes: 2_500, at: 2)
    #expect(try store.imagesByteSize() == 3_500)
}

@Test func pruneStopsAtTheLowWaterMarkNotTheHighOne() throws {
    // Yüksek eşiğin hemen altında durulsaydı her yeni görsel budamayı
    // yeniden tetiklerdi; histerezis bunun için var.
    let store = try makeStore()
    for i in 1...5 { _ = try imageClip(store, bytes: 1_000, at: TimeInterval(i)) }
    let removed = try store.pruneImages(highWater: 4_000, lowWater: 2_000)
    #expect(removed == 3)
    #expect(try store.imagesByteSize() == 2_000)
}

@Test func pruneNeverTouchesPinnedImages() throws {
    let store = try makeStore()
    _ = try imageClip(store, bytes: 1_000, at: 1, pinned: true)
    for i in 2...4 { _ = try imageClip(store, bytes: 1_000, at: TimeInterval(i)) }
    _ = try store.pruneImages(highWater: 2_000, lowWater: 1_000)
    let survivors = try store.recent(limit: 10).filter { $0.imagePath != nil }
    #expect(survivors.contains { $0.pinned })
}

@Test func prunedClipKeepsItsRowSoTheCardCanSayTheImageIsGone() throws {
    let store = try makeStore()
    for i in 1...3 { _ = try imageClip(store, bytes: 1_000, at: TimeInterval(i)) }
    _ = try store.pruneImages(highWater: 2_000, lowWater: 1_000)
    #expect(try store.recent(limit: 10).count == 3)
    #expect(try store.recent(limit: 10).filter { $0.imagePath == nil }.count >= 1)
}

@Test func pruneDoesNothingBelowTheHighWaterMark() throws {
    let store = try makeStore()
    _ = try imageClip(store, bytes: 500, at: 1)
    #expect(try store.pruneImages(highWater: 10_000, lowWater: 5_000) == 0)
}

@Test func upsertInsertRoundTripsAnApostropheInSourceNameExactly() throws {
    // NSRunningApplication.localizedName besler bunu (Task 8); "Bob's Editor"
    // gibi bir isim el yapımı SQL kaçışında sözdizimini kırıyordu.
    let store = try makeStore()
    let clip = Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), kind: .text,
                    text: "merhaba", imagePath: nil, sourceBundleID: "com.bob's.app",
                    sourceName: "Bob's Editor", pinned: false, shelfID: nil,
                    contentHash: "hash-1", byteSize: 4)
    try store.upsert(clip)
    let all = try store.recent(limit: 10)
    #expect(all.count == 1)
    #expect(all[0].sourceName == "Bob's Editor")
    #expect(all[0].sourceBundleID == "com.bob's.app")
}

@Test func upsertUpdateRoundTripsAnApostropheInSourceNameExactly() throws {
    let store = try makeStore()
    let first = Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), kind: .text,
                     text: "aynı", imagePath: nil, sourceBundleID: nil, sourceName: nil,
                     pinned: false, shelfID: nil, contentHash: "hash-2", byteSize: 4)
    try store.upsert(first)
    try store.upsert(Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: 500), kind: .text,
                          text: "aynı", imagePath: nil, sourceBundleID: "com.bob's.app",
                          sourceName: "Bob's Editor", pinned: false, shelfID: nil,
                          contentHash: "hash-2", byteSize: 4))
    let all = try store.recent(limit: 10)
    #expect(all.count == 1)
    #expect(all[0].createdAt == Date(timeIntervalSince1970: 500))
    #expect(all[0].sourceName == "Bob's Editor")
}
