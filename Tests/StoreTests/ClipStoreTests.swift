import Testing
import Foundation
@testable import Store

/// Her test kendi geçici dizininde çalışır; testler birbirinin verisini görmez.
private func makeStore() throws -> (ClipStore, URL) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-test-\(UUID().uuidString)")
    return (try ClipStore(directory: dir), dir)
}

private func textClip(_ text: String, at seconds: TimeInterval = 0) -> Clip {
    Clip(id: UUID(), createdAt: Date(timeIntervalSince1970: seconds), kind: .text,
         text: text, imagePath: nil, sourceBundleID: "com.apple.Safari",
         sourceName: "Safari", pinned: false, shelfID: nil,
         contentHash: text, byteSize: text.utf8.count)
}

@Test func insertedClipComesBackOut() throws {
    let (store, _) = try makeStore()
    try store.insert(textClip("merhaba"))
    let all = try store.recent(limit: 10)
    #expect(all.count == 1)
    #expect(all[0].text == "merhaba")
    #expect(all[0].sourceName == "Safari")
}

@Test func recentIsNewestFirst() throws {
    let (store, _) = try makeStore()
    try store.insert(textClip("eski", at: 100))
    try store.insert(textClip("yeni", at: 200))
    #expect(try store.recent(limit: 10).map(\.text) == ["yeni", "eski"])
}

@Test func dataDirectoryIsPrivateToTheUser() throws {
    // Pano geçmişi diğer kullanıcı hesaplarına açık olmamalı; 0700 bunun
    // tek satırlık garantisi ve regresyonu sessizce olur, o yüzden test var.
    let (_, dir) = try makeStore()
    let perms = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber
    #expect(perms?.int16Value == 0o700)
}

@Test func reopeningTheSameDirectoryKeepsTheData() throws {
    let (store, dir) = try makeStore()
    try store.insert(textClip("kalıcı"))
    _ = store
    let reopened = try ClipStore(directory: dir)
    #expect(try reopened.recent(limit: 10).count == 1)
}
