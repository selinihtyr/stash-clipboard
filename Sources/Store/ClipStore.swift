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

    /// Açılışta bozuk bir veritabanı bulunup kenara alındıysa yedeğin yolu.
    /// nil ise veritabanı sağlıklı açıldı, hiçbir şeye dokunulmadı.
    public private(set) var recoveredFromCorruption: URL?

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
        do {
            try exec("PRAGMA journal_mode=WAL;")
            // Şema okunabilir olsa bile veri sayfaları bozuk olabilir (çökme,
            // elektrik kesintisi ortasında yarım kalmış bir yazma) — bu,
            // "dosya hiç açılmıyor" değil, gerçek dünyadaki yaygın senaryo.
            // quick_check sayfaları tarar; integrity_check'in tam indeks
            // doğrulaması olmadan, birkaç bin satırlık bir geçmişte
            // milisaniyeler sürer.
            try checkIntegrity()
            try createSchema()
        } catch {
            // Bozuk dosyayı silmiyoruz: kullanıcının verisi olabilir ve
            // kurtarma denemesi bize değil ona ait.
            sqlite3_close(db); db = nil
            let corrupt = directory.appendingPathComponent("stash.sqlite")
            // Adı şansa değil inşaya bırakıyoruz: aynı saniyede ikinci bir
            // kurtarma (ör. art arda başarısız başlatmalar) zaman damgasını
            // çakıştırırdı; moveItem hedefin üstüne yazmayı reddeder, dosya
            // yerinde kalır ve altındaki PRAGMA/createSchema aynı hatayla
            // tekrar patlayıp init'i anlaşılmaz bir şekilde düşürürdü. Hedefi
            // önceden boş olduğunu doğrulayarak seçmek bu çakışmayı bütünüyle
            // ortadan kaldırıyor.
            let backup = Self.freeBackupURL(in: directory,
                timestamp: Int(Date().timeIntervalSince1970), fm: fm)
            do {
                try fm.moveItem(at: corrupt, to: backup)
            } catch let moveError {
                // Taşıma gerçekten başarısız olduysa (izin, salt-okunur disk…)
                // aynı yoldan tekrar açmayı denemek bozuk dosyayı geri
                // okuyup PRAGMA'nın ilgisiz görünen bir hatayla patlamasına
                // yol açardı. Burada dürüst ve özel bir hatayla duruyoruz;
                // AppDelegate bunu presentFatal ile gösterip sonlandırır —
                // sessiz bir "boş açıldı" yalanından iyisi budur.
                throw StoreError.openFailed(
                    "Couldn't move aside the corrupt database (\(error)): \(moveError)")
            }
            // WAL modu veritabanını üç dosyaya böler (.sqlite, -wal, -shm).
            // Ana dosyayı taşıyıp bunları yerinde bırakırsak taze açılan
            // veritabanı onları kendi write-ahead log'u sanıp bozuk içeriği
            // geri oynatmaya çalışabilir; aynı kaygıyla siliyor değil,
            // onları da yedeğin yanına taşıyoruz.
            for suffix in ["-wal", "-shm"] {
                let sidecar = directory.appendingPathComponent("stash.sqlite\(suffix)")
                guard fm.fileExists(atPath: sidecar.path) else { continue }
                try? fm.moveItem(at: sidecar,
                    to: directory.appendingPathComponent("\(backup.lastPathComponent)\(suffix)"))
            }
            recoveredFromCorruption = backup
            guard sqlite3_open(path, &db) == SQLITE_OK else {
                throw StoreError.openFailed(String(cString: sqlite3_errmsg(db)))
            }
            try exec("PRAGMA journal_mode=WAL;")
            try createSchema()
        }
    }

    deinit { sqlite3_close(db) }

    /// Zaman damgalı ad okunurluk için (klasöre bakan biri "bu benim eski,
    /// bozuk geçmişim" desin diye); ama tekliği ada değil, hedefin boş
    /// olduğunun önceden doğrulanmasına dayandırıyoruz — aynı saniyede iki
    /// kurtarma olsa da moveItem asla bir öncekinin üstüne yazmaz.
    private static func freeBackupURL(in directory: URL, timestamp: Int, fm: FileManager) -> URL {
        var candidate = directory.appendingPathComponent("stash-corrupt-\(timestamp).sqlite")
        var attempt = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("stash-corrupt-\(timestamp)-\(attempt).sqlite")
            attempt += 1
        }
        return candidate
    }

    /// PRAGMA quick_check bir tablo değil, "ok" ya da hata satırları
    /// döndürür. exec (sqlite3_exec) sonucu bize vermiyor, bu yüzden
    /// prepare/step kullanıyoruz.
    private func checkIntegrity() throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check;", -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, column(stmt, 0) == "ok" else {
            throw StoreError.queryFailed("quick_check reported an integrity problem")
        }
    }

    private func createSchema() throws {
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
        // IF NOT EXISTS mevcut veritabanlarını değiştirmez ama yeni bir tablo
        // eklemek güvenli: eski dosyalar shelves olmadan açılabilir, ilk
        // createShelf çağrısında tablo zaten hazır olur.
        try exec("""
            CREATE TABLE IF NOT EXISTS shelves (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              createdAt REAL NOT NULL
            );
            """)
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown error"
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

    /// Bir sekmenin (Tümü/Sabitlenen/Görseller/Raf) hangi satırlara
    /// baktığını tanımlar. `StripModel.reload()` eskiden `recent(limit: 300)`
    /// çekip tab'a göre BELLEKTE süzüyordu — bu, sabitlenmiş/rafa konmuş/
    /// görsel bir klip 300 satırdan eskiyince ilgili sekmede görünmez
    /// oluyordu (C2). Süzgeç artık SQL'in WHERE'ine taşındı, limit süzgeçten
    /// SONRA uygulanıyor; her sekme kendi 300'ünü görür, birbirine karışmaz.
    public enum ClipScope: Sendable, Equatable {
        case all
        case pinned
        case kind(ClipKind)
        case shelf(UUID)
    }

    /// `scope` ve isteğe bağlı arama terimini SQL'de birleştirir. Raf id'si
    /// (kullanıcı girdisi değil ama) ve arama terimi (kesinlikle kullanıcı
    /// girdisi) bağlı parametreyle geçiyor — `upsert`in üstündeki yorumun
    /// anlattığı el yapımı kaçış hatasını burada yeniden üretmemek için.
    public func clips(in scope: ClipScope, matching term: String? = nil, limit: Int) throws -> [Clip] {
        var whereClauses: [String] = []
        var params: [String] = []
        switch scope {
        case .all:
            break
        case .pinned:
            whereClauses.append("pinned = 1")
        case .kind(let kind):
            // ClipKind.rawValue programda sabit bir küme (text/image/link/file),
            // kullanıcı girdisi değil; yine de tutarlılık için bağlı parametre.
            whereClauses.append("kind = ?")
            params.append(kind.rawValue)
        case .shelf(let id):
            whereClauses.append("shelfID = ?")
            params.append(id.uuidString)
        }
        if let term, !term.isEmpty {
            let escaped = term
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            whereClauses.append("text LIKE ? ESCAPE '\\'")
            params.append("%\(escaped)%")
        }
        let whereSQL = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        let sql = "SELECT * FROM clips \(whereSQL) ORDER BY createdAt DESC LIMIT \(limit)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (index, param) in params.enumerated() {
            bindText(stmt, Int32(index + 1), param)
        }
        var out: [Clip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(rowToClip(stmt))
        }
        return out
    }

    func query(_ sql: String) throws -> [Clip] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var out: [Clip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(rowToClip(stmt))
        }
        return out
    }

    private func rowToClip(_ stmt: OpaquePointer?) -> Clip {
        Clip(
            id: UUID(uuidString: column(stmt, 0) ?? "") ?? UUID(),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
            kind: ClipKind(rawValue: column(stmt, 2) ?? "text") ?? .text,
            text: column(stmt, 3), imagePath: column(stmt, 4),
            sourceBundleID: column(stmt, 5), sourceName: column(stmt, 6),
            pinned: sqlite3_column_int(stmt, 7) == 1,
            shelfID: column(stmt, 8).flatMap(UUID.init(uuidString:)),
            contentHash: column(stmt, 9) ?? "",
            byteSize: Int(sqlite3_column_int64(stmt, 10)))
    }

    /// Verilen contentHash için satırı arar (varsa). CaptureCoordinator bunu
    /// bir görsel dosyası diske yazmadan ÖNCE çağırır: içerik zaten
    /// depolanıyorsa ve dosyası hâlâ diskteyse yeni dosya hiç yazılmamalı —
    /// yazıp sonra silmek yerine baştan atlamak, hiçbir satırın işaret
    /// etmediği dosya bırakmaz. (`upsert`in imagePath'i artık COALESCE ile
    /// güncellediğini, yalnızca NULL verildiğinde eski değeri koruduğunu
    /// unutma — bkz. `upsert` üzerindeki I3 gerekçesi: budanmış bir satır
    /// yeniden yakalandığında bu arama sayesinde dosya baştan doğru ID'yle
    /// yeniden yazılır, upsert de yeni yolu satıra taşır.)
    public func find(contentHash: String) throws -> Clip? {
        let sql = "SELECT * FROM clips WHERE contentHash = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, contentHash)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToClip(stmt)
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

    /// Silinen üç yoldan (delete/deleteCreated/deleteAll) HER BİRİ satırların
    /// sahip olduğu görsel ve küçük resim dosyalarını da kaldırmalı (C3):
    /// sadece SQL çalıştırıp dosyaları yerinde bırakmak, kullanıcı geçmişini
    /// temizlediğinde her kopyaladığı ekran görüntüsünün diskte kalması
    /// demek — gizlilik önceliğini iddia eden bir uygulama için en kötü bulgu.
    /// Satırlar silinmeden ÖNCE hangi dosyalara sahip olduklarını okuyoruz;
    /// SQL'in kendisi dosya yollarını bilmiyor.
    public func delete(id: UUID) throws {
        let affected = try query("SELECT * FROM clips WHERE id = '\(id.uuidString)'")
        try exec("DELETE FROM clips WHERE id = '\(id.uuidString)';")
        removeFiles(for: affected)
    }

    public func deleteCreated(after date: Date) throws {
        let condition = "createdAt > \(date.timeIntervalSince1970) AND pinned = 0"
        let affected = try query("SELECT * FROM clips WHERE \(condition)")
        try exec("DELETE FROM clips WHERE \(condition);")
        removeFiles(for: affected)
    }

    public func deleteAll() throws {
        let affected = try query("SELECT * FROM clips WHERE pinned = 0")
        try exec("DELETE FROM clips WHERE pinned = 0;")
        removeFiles(for: affected)
        // `removeFiles` yalnızca SİLDİĞİMİZ satırların sahip olduğu dosyaları
        // kaldırır — hiçbir satırın hiç işaret etmediği öksüz dosyalar (ör.
        // daha önce budanmış, ama satırı da silinmiş; ya da yarım kalmış bir
        // yakalama) burada dokunulmadan kalırdı. "Tümünü temizle" kullanıcıya
        // sıfırlanmış bir disk figürü vaat ediyor; öksüzleri de süpürmeden bu
        // vaat tutulmaz (bkz. sweepOrphanFiles üstündeki gerekçe — eskiden bu
        // yalnızca pruneImages'ın 2 GB eşiğini aştığı anda çağrılıyordu,
        // dolayısıyla bir öksüz o eşiğe kadar asla geri kazanılamıyordu).
        sweepOrphanFiles()
    }

    /// `clips`in sahip olduğu orijinal görsel ve (varsa) küçük resim
    /// dosyalarını diskten siler. Metin/bağlantı/dosya klipleri zaten
    /// `imagePath == nil`, bu yüzden onlar için hiçbir şey yapılmaz.
    /// `try?`: bir dosya zaten yoksa (ör. daha önce pruneImages tarafından
    /// budanmış) silme başarısızlığı satır silme işlemini geçersiz kılmamalı.
    private func removeFiles(for clips: [Clip]) {
        let fm = FileManager.default
        for clip in clips {
            if let path = clip.imagePath { try? fm.removeItem(atPath: path) }
            try? fm.removeItem(at: thumbsDirectory.appendingPathComponent("\(clip.id.uuidString).jpg"))
        }
    }

    /// Raf adı kullanıcı tarafından yazılıyor; `upsert`in üstündeki yorumun
    /// anlattığı hatayı burada da tekrarlamamak için tırnak kaçışlı
    /// interpolasyon yerine bağlı parametre kullanılıyor.
    public func createShelf(name: String) throws -> Shelf {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.queryFailed("shelf name can't be empty") }
        let shelf = Shelf(id: UUID(), name: trimmed)
        let sql = "INSERT INTO shelves (id, name, createdAt) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, shelf.id.uuidString)
        bindText(stmt, 2, trimmed)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        return shelf
    }

    public func shelves() throws -> [Shelf] {
        let sql = "SELECT id, name FROM shelves ORDER BY createdAt ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var out: [Shelf] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = column(stmt, 0).flatMap(UUID.init(uuidString:)),
                  let name = column(stmt, 1) else { continue }
            out.append(Shelf(id: id, name: name))
        }
        return out
    }

    public func renameShelf(_ id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.queryFailed("shelf name can't be empty") }
        let sql = "UPDATE shelves SET name = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, trimmed)
        bindText(stmt, 2, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Rafı siler ama kartlarını silmez: kullanıcı klasörü kaldırıyor,
    /// içindekini çöpe atmıyor — kartlar sadece rafsız kalıp Tümü'ne düşer.
    public func deleteShelf(_ id: UUID) throws {
        try exec("UPDATE clips SET shelfID = NULL WHERE shelfID = '\(id.uuidString)';")
        try exec("DELETE FROM shelves WHERE id = '\(id.uuidString)';")
    }

    /// Aynı içerik tekrar kopyalandığında yeni satır açmaz; mevcut satırın
    /// tarihini günceller, böylece kart listenin başına döner ve geçmiş
    /// aynı şeyin kopyalarıyla dolmaz.
    ///
    /// `imagePath = COALESCE(?, imagePath)`: verilen değer NULL ise mevcut
    /// değeri olduğu gibi bırakır. Metin/bağlantı/dosya klipleri için
    /// `clip.imagePath` zaten hep nil, bu yüzden onlarda davranış değişmedi.
    /// Görseller için bu, budanmış (imagePath NULL'a düşmüş) bir satırın
    /// aynı içerik yeniden kopyalandığında GERÇEKTEN geri yüklenebilmesini
    /// sağlıyor (I3): `CaptureCoordinator.tick()` artık dosyayı yeniden
    /// yazdığında yeni yolu buraya taşıyor, eskiden bu UPDATE imagePath'e
    /// hiç dokunmadığı için o yeni yol satıra asla ulaşmıyordu.
    public func upsert(_ clip: Clip) throws {
        // El yapımı tırnak kaçışı "Bob's Editor" gibi isimlerde sözdizimini
        // kırıyordu (NSRunningApplication.localizedName bunu besliyor); bound
        // parametreler bu hata sınıfını tamamen ortadan kaldırır.
        let sql = """
            UPDATE clips SET createdAt = ?, sourceBundleID = ?, sourceName = ?,
                             imagePath = COALESCE(?, imagePath)
            WHERE contentHash = ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, clip.createdAt.timeIntervalSince1970)
        bindText(stmt, 2, clip.sourceBundleID)
        bindText(stmt, 3, clip.sourceName)
        bindText(stmt, 4, clip.imagePath)
        bindText(stmt, 5, clip.contentHash)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        if sqlite3_changes(db) == 0 { try insert(clip) }
    }

    /// `images/` VE `thumbs/` toplamı: Ayarlar'daki "Görsel ve
    /// önizlemelerin kapladığı alan" etiketi doğrudan bu sayıyı gösteriyor,
    /// gerçek disk kullanımıyla uyuşması gerekiyor (bulgu 5: etiket eskiden
    /// yalnızca "Görsellerin" diyordu, sayı thumbs/'u içerdiği için ikisi
    /// uyuşmuyordu). Yalnızca `images/`i saymak, `thumbs/`taki öksüz bir
    /// küçük resmin `highWater` guard'ını hiç tetikleyememesi anlamına da
    /// geliyordu — süpürmeyi hak eden bir dosya "görünmez" kalıyordu.
    public func imagesByteSize() throws -> Int {
        directoryByteSize(imagesDirectory) + directoryByteSize(thumbsDirectory)
    }

    private func directoryByteSize(_ directory: URL) -> Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory,
                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Bir dosyanın diske yazılışı ile onu işaret eden satırın eklenmesi
    /// arasında bir pencere var: `CaptureCoordinator.tick()` görseli ÖNCE
    /// yazar, satırı SONRA ekler (yazma başarısız olursa hiç var olmayan bir
    /// dosyaya işaret eden satır oluşmasın diye — bkz. o dosyadaki gerekçe).
    /// Bugünkü tek çağrı yolunda bu iki adım aynı @MainActor tick() içinde,
    /// art arda ve senkron çalışıyor; süpürme de satır eklendikten SONRA
    /// çağrılıyor, dolayısıyla PRATİKTE süpürmenin gördüğü her dosyanın
    /// satırı zaten vardır. Yine de bu fonksiyon genel bir API: gelecekte
    /// başka bir çağıran (ör. bir "şimdi temizle" düğmesi) bir yakalamayla
    /// çakışabilir. Bu yüzden süpürme, değişiklik zamanı yakın geçmişteki
    /// (aşağıdaki `orphanGracePeriod`) dosyalara dokunmuyor — o pencerede
    /// yazılmış ama satırı henüz eklenmemiş taze bir dosyayı yanlışlıkla
    /// silmemek için.
    private static let orphanGracePeriod: TimeInterval = 5

    /// `highWater` aşıldığında en eski görselleri `lowWater`'ın altına inene
    /// kadar siler. Satırlar kalır: kart "görsel artık saklanmıyor" diyebilsin.
    /// Sabitlenmiş kartların görselleri hiç budanmaz.
    ///
    /// Satır-tabanlı budamadan ÖNCE hiçbir satırın işaret etmediği dosyaları
    /// süpürür (C3): `delete`/`deleteAll` bu sürümden önce dosya silmiyordu,
    /// bu da diskte hiçbir satırın büyütmediği ama `imagesByteSize()`e
    /// katkıda bulunan "öksüz" dosyalar bırakabiliyordu. Öksüzler tek başına
    /// `highWater`'ı aşınca, satır-tabanlı döngü (adaylarını `imagePath IS
    /// NOT NULL` satırlarından seçtiği için) onları asla göremez ve budama
    /// sonsuza dek yakınsayamazdı — `CaptureCoordinator.tick()` bunu HER
    /// yakalamada çağırdığından bu, kalıcı ve boşa giden bir tam dizin
    /// taramasına dönüşürdü.
    @discardableResult
    public func pruneImages(highWater: Int, lowWater: Int) throws -> Int {
        // Süpürme artık `highWater` kontrolünün İÇİNDE değil ÖNÜNDE: eskiden
        // yalnızca toplam boyut 2 GB'ı (üretim eşiği) aşınca çalışıyordu, bu
        // da 2 GB'ın altında kalan bir öksüzün sonsuza dek görünmez kalması
        // demekti — hiçbir satır ona işaret etmediği için satır-tabanlı
        // döngü de onu asla adaylar arasında görmezdi. Her yakalamada ucuz
        // bir dizin taraması, sonsuza dek büyüyebilen öksüz dosyalardan daha
        // ucuz bir maliyet.
        sweepOrphanFiles()
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
            let thumbPath = thumbsDirectory.appendingPathComponent("\(clip.id.uuidString).jpg")
            // Boyutları dosyalar silinmeden ÖNCE oku: silindikten sonra okumak
            // hep 0 döner ve döngü hiçbir zaman lowWater'a yakınsamaz.
            let imageBytes = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            // `imagesByteSize()` artık thumbs/'u da sayıyor; küçük resmin
            // boyutunu düşmeyi unutursak `size` gerçek kalan boyuttan büyük
            // kalır ve döngü hiç yakınsamadan gerekenden fazla kart siler.
            let thumbBytes = (try? fm.attributesOfItem(atPath: thumbPath.path)[.size] as? Int) ?? 0
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(at: thumbPath)
            try exec("UPDATE clips SET imagePath = NULL WHERE id = '\(clip.id.uuidString)';")
            size -= (imageBytes + thumbBytes)
            removed += 1
        }
        return removed
    }

    /// `images/` ve `thumbs/` dizinlerini diskteki gerçek dosyalarla, hangi
    /// dosyaların hâlâ bir satır tarafından referans verildiğiyle
    /// karşılaştırıp hiçbirinin işaret etmediğini siler. `orphanGracePeriod`
    /// içinde değiştirilmiş dosyalara dokunmaz — bkz. `pruneImages`
    /// üzerindeki gerekçe (yazma/satır-ekleme sırası).
    private func sweepOrphanFiles() {
        let fm = FileManager.default
        let referenced = (try? query("SELECT * FROM clips WHERE imagePath IS NOT NULL")) ?? []
        let referencedImageNames = Set(referenced.compactMap {
            $0.imagePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        })
        let referencedThumbNames = Set(referenced.map { "\($0.id.uuidString).jpg" })
        let cutoff = Date().addingTimeInterval(-Self.orphanGracePeriod)

        func sweep(_ directory: URL, keeping referenced: Set<String>) {
            guard let files = try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            for file in files where !referenced.contains(file.lastPathComponent) {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? nil
                // Yaşı okunamıyorsa ya da yakın geçmişteyse dokunma: emin
                // olamadığımız ya da taze olabilecek (satır eklemesi hâlâ
                // uçuşta olabilecek) bir dosyayı silmemeyi tercih ediyoruz.
                guard let mtime, mtime <= cutoff else { continue }
                try? fm.removeItem(at: file)
            }
        }
        sweep(imagesDirectory, keeping: referencedImageNames)
        sweep(thumbsDirectory, keeping: referencedThumbNames)
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
