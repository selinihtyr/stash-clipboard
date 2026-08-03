import Foundation
import SQLite3

/// sqlite3_bind_text'e verilen tampon çağrı bittiğinde geçersiz olur; SQLITE_TRANSIENT
/// SQLite'a "kendi kopyanı al" der. Swift'te sabiti elle üretmek gerekiyor.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum StoreError: Error, Equatable {
    case openFailed(String)
    case queryFailed(String)
}

public final class ClipStore {
    private var db: OpaquePointer?
    public let directory: URL
    public var imagesDirectory: URL { directory.appendingPathComponent("images") }
    public var thumbsDirectory: URL { directory.appendingPathComponent("thumbs") }

    public init(directory: URL) throws {
        self.directory = directory
        let fm = FileManager.default
        for dir in [directory, directory.appendingPathComponent("images"),
                    directory.appendingPathComponent("thumbs")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        // createDirectory izinleri sadece yeni oluşturulan dizine uygular;
        // dizin zaten varsa (güncelleme, elle kopyalama) izni ayrıca dayatıyoruz.
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let path = directory.appendingPathComponent("stash.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS clips (
              id TEXT PRIMARY KEY,
              createdAt REAL NOT NULL,
              kind TEXT NOT NULL,
              text TEXT,
              imagePath TEXT,
              sourceBundleID TEXT,
              sourceName TEXT,
              pinned INTEGER NOT NULL DEFAULT 0,
              shelfID TEXT,
              contentHash TEXT NOT NULL,
              byteSize INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS clips_createdAt ON clips(createdAt DESC);
            CREATE UNIQUE INDEX IF NOT EXISTS clips_hash ON clips(contentHash);
            """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "bilinmeyen hata"
            sqlite3_free(err)
            throw StoreError.queryFailed(message)
        }
    }

    public func insert(_ clip: Clip) throws {
        let sql = """
            INSERT INTO clips (id, createdAt, kind, text, imagePath, sourceBundleID,
                               sourceName, pinned, shelfID, contentHash, byteSize)
            VALUES (?,?,?,?,?,?,?,?,?,?,?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, clip.id.uuidString)
        sqlite3_bind_double(stmt, 2, clip.createdAt.timeIntervalSince1970)
        bindText(stmt, 3, clip.kind.rawValue)
        bindText(stmt, 4, clip.text)
        bindText(stmt, 5, clip.imagePath)
        bindText(stmt, 6, clip.sourceBundleID)
        bindText(stmt, 7, clip.sourceName)
        sqlite3_bind_int(stmt, 8, clip.pinned ? 1 : 0)
        bindText(stmt, 9, clip.shelfID?.uuidString)
        bindText(stmt, 10, clip.contentHash)
        sqlite3_bind_int64(stmt, 11, Int64(clip.byteSize))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func recent(limit: Int) throws -> [Clip] {
        try query("SELECT * FROM clips ORDER BY createdAt DESC LIMIT \(limit)")
    }

    func query(_ sql: String) throws -> [Clip] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var out: [Clip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Clip(
                id: UUID(uuidString: column(stmt, 0) ?? "") ?? UUID(),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                kind: ClipKind(rawValue: column(stmt, 2) ?? "text") ?? .text,
                text: column(stmt, 3), imagePath: column(stmt, 4),
                sourceBundleID: column(stmt, 5), sourceName: column(stmt, 6),
                pinned: sqlite3_column_int(stmt, 7) == 1,
                shelfID: column(stmt, 8).flatMap(UUID.init(uuidString:)),
                contentHash: column(stmt, 9) ?? "",
                byteSize: Int(sqlite3_column_int64(stmt, 10))))
        }
        return out
    }

    /// LIKE joker karakterlerini kaçırır. Bunu yapmazsak kullanıcının yazdığı
    /// % veya _ bütün geçmişi eşleştirir ve arama bozuk görünür.
    public func search(_ term: String, limit: Int) throws -> [Clip] {
        let escaped = term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "'", with: "''")
        return try query("""
            SELECT * FROM clips
            WHERE text LIKE '%\(escaped)%' ESCAPE '\\'
            ORDER BY createdAt DESC LIMIT \(limit)
            """)
    }

    public func setPinned(_ pinned: Bool, id: UUID) throws {
        try exec("UPDATE clips SET pinned = \(pinned ? 1 : 0) WHERE id = '\(id.uuidString)';")
    }

    public func setShelf(_ shelfID: UUID?, id: UUID) throws {
        let value = shelfID.map { "'\($0.uuidString)'" } ?? "NULL"
        try exec("UPDATE clips SET shelfID = \(value) WHERE id = '\(id.uuidString)';")
    }

    public func delete(id: UUID) throws {
        try exec("DELETE FROM clips WHERE id = '\(id.uuidString)';")
    }

    public func deleteCreated(after date: Date) throws {
        try exec("DELETE FROM clips WHERE createdAt > \(date.timeIntervalSince1970) AND pinned = 0;")
    }

    public func deleteAll() throws {
        try exec("DELETE FROM clips WHERE pinned = 0;")
    }

    /// Aynı içerik tekrar kopyalandığında yeni satır açmaz; mevcut satırın
    /// tarihini günceller, böylece kart listenin başına döner ve geçmiş
    /// aynı şeyin kopyalarıyla dolmaz.
    public func upsert(_ clip: Clip) throws {
        let sql = """
            UPDATE clips SET createdAt = \(clip.createdAt.timeIntervalSince1970),
                             sourceBundleID = \(clip.sourceBundleID.map { "'\($0)'" } ?? "NULL"),
                             sourceName = \(clip.sourceName.map { "'\($0)'" } ?? "NULL")
            WHERE contentHash = '\(clip.contentHash.replacingOccurrences(of: "'", with: "''"))';
            """
        try exec(sql)
        if sqlite3_changes(db) == 0 { try insert(clip) }
    }

    public func imagesByteSize() throws -> Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: imagesDirectory,
                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// `highWater` aşıldığında en eski görselleri `lowWater`'ın altına inene
    /// kadar siler. Satırlar kalır: kart "görsel artık saklanmıyor" diyebilsin.
    /// Sabitlenmiş kartların görselleri hiç budanmaz.
    @discardableResult
    public func pruneImages(highWater: Int, lowWater: Int) throws -> Int {
        var size = try imagesByteSize()
        guard size > highWater else { return 0 }
        let candidates = try query("""
            SELECT * FROM clips
            WHERE imagePath IS NOT NULL AND pinned = 0
            ORDER BY createdAt ASC
            """)
        var removed = 0
        let fm = FileManager.default
        for clip in candidates {
            guard size > lowWater, let path = clip.imagePath else { break }
            // Boyutu dosya silinmeden ÖNCE oku: silindikten sonra okumak
            // hep 0 döner ve döngü hiçbir zaman lowWater'a yakınsamaz.
            let bytes = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(at: thumbsDirectory.appendingPathComponent("\(clip.id.uuidString).jpg"))
            try exec("UPDATE clips SET imagePath = NULL WHERE id = '\(clip.id.uuidString)';")
            size -= bytes
            removed += 1
        }
        return removed
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
