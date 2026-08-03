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

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
