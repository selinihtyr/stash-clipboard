import Testing
import Foundation
@testable import Store

@Test func aCorruptDatabaseIsMovedAsideAndTheAppStillOpens() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-corrupt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // SQLite başlığı olmayan bir dosya: açılır ama ilk sorguda patlar.
    try Data("bu bir veritabanı değil".utf8)
        .write(to: dir.appendingPathComponent("stash.sqlite"))

    let store = try ClipStore(directory: dir)
    #expect(store.recoveredFromCorruption != nil)
    #expect(try store.recent(limit: 10).isEmpty)

    // Yedek duruyor: veri kaybını sessizce yutmuyoruz.
    let backup = try #require(store.recoveredFromCorruption)
    #expect(FileManager.default.fileExists(atPath: backup.path))
}

@Test func ahealthyDatabaseIsNotTouched() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-healthy-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    #expect(store.recoveredFromCorruption == nil)
}
