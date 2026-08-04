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

/// Fix round 1, bulgu 1: yedek adı yalnızca saniye çözünürlüğündeyse aynı
/// saniyede ikinci bir kurtarma (ör. art arda başarısız başlatmalar) önceki
/// yedeğin üstüne yazmaya çalışır, moveItem reddeder, bozuk dosya yerinde
/// kalır ve altındaki PRAGMA çağrısı init'i anlaşılmaz bir hatayla düşürür.
/// Burada aynı saniyede iki kurtarmayı zorluyoruz: ikisi de başarıyla
/// açılmalı, ikisinin de ayrı, hâlâ diskte duran bir yedeği olmalı.
@Test func twoRecoveriesInTheSameSecondDoNotCollide() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-double-corrupt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("bu bir veritabanı değil".utf8)
        .write(to: dir.appendingPathComponent("stash.sqlite"))

    let firstBackup: URL
    do {
        let first = try ClipStore(directory: dir)
        firstBackup = try #require(first.recoveredFromCorruption)
        // `first` burada scope dışına çıkar: deinit sqlite3_close çağırır,
        // WAL temiz kapanışta checkpoint edilip -wal/-shm silinir. Bunu
        // beklemeden aşağıda dosyayı elle bozarsak ikinci kurtarmanın
        // -wal/-shm taşıma adımı birinci store'un hâlâ açık sidecar
        // dosyalarını çalar — testin kanıtlamak istediği şeyle ilgisiz bir
        // kırılganlık olurdu.
    }

    // İlk kurtarmadan sonra yerinde duran taze veritabanını da bozuyoruz ki
    // ikinci bir kurtarma aynı saniyede tetiklensin.
    try Data("hâlâ bir veritabanı değil".utf8)
        .write(to: dir.appendingPathComponent("stash.sqlite"))
    let second = try ClipStore(directory: dir)
    let secondBackup = try #require(second.recoveredFromCorruption)

    #expect(firstBackup != secondBackup)
    #expect(FileManager.default.fileExists(atPath: firstBackup.path))
    #expect(FileManager.default.fileExists(atPath: secondBackup.path))
    #expect(try second.recent(limit: 10).isEmpty)
}

/// Fix round 1, bulgu 2: başlık geçerliyken veri sayfaları bozuksa (çökme,
/// elektrik kesintisi ortasında yarım kalmış bir yazma — gerçek dünyada
/// "dosya hiç açılmıyor"dan çok daha yaygın senaryo) createSchema hiç
/// tetiklenmez (sqlite_master zaten var) ve eski davranışta bu hiç
/// yakalanmazdı; ilk SELECT'e kadar sıradan bir StoreError olarak yüzeye
/// çıkardı. quick_check bunu açılışta yakalamalı.
@Test func aStructurallyValidButPageDamagedDatabaseRoutesThroughRecoveryToo() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stash-pagedamage-\(UUID().uuidString)")
    do {
        let store = try ClipStore(directory: dir)
        for i in 0..<20 {
            try store.insert(Clip(
                id: UUID(), createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                kind: .text, text: String(repeating: "x", count: 500), imagePath: nil,
                sourceBundleID: nil, sourceName: nil, pinned: false, shelfID: nil,
                contentHash: "hash-\(i)", byteSize: 500))
        }
        // store burada scope dışına çıkar; deinit sqlite3_close çağırır ve
        // WAL içeriğini ana dosyaya checkpoint eder.
    }
    let dbPath = dir.appendingPathComponent("stash.sqlite")
    // Kapanıştan sonra kalmış olabilecek -wal/-shm, bozduğumuz veriyi
    // maskeleyip taze açılışın gerçek durumu hiç görmesini engelleyebilir.
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("stash.sqlite-wal"))
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("stash.sqlite-shm"))

    var bytes = try Data(contentsOf: dbPath)
    // SQLite dosya başlığının 16-17. baytları sayfa boyutunu (big-endian)
    // taşır; 1 değeri 65536 anlamına gelir. Sayfa 1 başlığı VE şemayı
    // (sqlite_master) barındırır — onu bozmadan yalnızca ondan sonraki
    // sayfaları (asıl satır verisi) XOR'luyoruz. Böylece createSchema hâlâ
    // başarılı olur (tablo zaten var, sqlite_master sağlam) ama satırlar
    // okunamaz hale gelir.
    let rawPageSize = (Int(bytes[bytes.startIndex + 16]) << 8) | Int(bytes[bytes.startIndex + 17])
    let pageSize = rawPageSize == 1 ? 65536 : rawPageSize
    #expect(bytes.count > pageSize) // en az iki sayfa yoksa test hiçbir şey kanıtlamaz
    for i in stride(from: bytes.startIndex + pageSize, to: bytes.endIndex, by: 1) {
        bytes[i] ^= 0xFF
    }
    try bytes.write(to: dbPath)

    let store = try ClipStore(directory: dir)
    #expect(store.recoveredFromCorruption != nil)
}
