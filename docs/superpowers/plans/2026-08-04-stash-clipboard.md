# Stash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS'ta kopyalama geçmişini ekranın altına yapışık bir kart şeridinde gösteren, doğrudan yapıştırma yapabilen, yerel-önce çalışan pano yöneticisi.

**Architecture:** SwiftPM çok modüllü paket. `PasteboardKit` panoyu yoklar ve saf `Clip` değerleri üretir; `Store` SQLite + diskte saklar; `HotKey` global kısayolu kaydeder; `PasteEngine` panoya geri yazıp sentetik ⌘V üretir; `Filters` saf metin dönüşümleridir. `StashCore` bunları bağlar, `Stash` çalıştırılabilir hedefi menü çubuğu öğesini ve `NSPanel` şeridini barındırır. Alt katmanlar birbirini tanımaz — `PasteboardKit` diski, `Store` panoyu bilmez.

**Tech Stack:** Swift 6.3, SwiftPM (Xcode projesi yok), SwiftUI + AppKit (`NSPanel`), libsqlite3 (sistem), Carbon `RegisterEventHotKey`, Swift Testing (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-08-04-stash-clipboard-design.md`

## Global Constraints

- **Üçüncü taraf bağımlılık yok.** Sadece sistem çerçeveleri ve libsqlite3.
- **Ağ kodu yok.** Hiçbir modül `URLSession`, `Network` veya soket API'si kullanmaz. Bu, README'deki gizlilik iddiasının dayanağıdır.
- `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`.
- Test çerçevesi **Swift Testing** (`import Testing`, `@Test`) — XCTest değil. `still-running` reposundaki kalıp.
- Bundle identifier: `social.selin.stash`. Uygulama adı `Stash`, çalıştırılabilir adı `Stash`, repo adı `stash-clipboard`.
- `LSUIElement = true` — Dock'ta görünmez, sadece menü çubuğu.
- Veri dizini: `~/Library/Application Support/Stash/`, izinler `0700`.
- Varsayılan kısayol ⌥⌘V.
- Kod yorumları **neden**i anlatır, neyi değil. `still-running/scripts/bundle.sh` bu tarzın örneği.
- Her task kendi testleriyle biter ve commit'lenir. Commit mesajları Türkçe, emir kipi.

---

### Task 1: Paket iskeleti ve Filters modülü

Saf fonksiyonlarla başlıyoruz: dış dünyaya bağımlılığı olmayan tek modül bu, dolayısıyla iskeleti kurmanın en ucuz yeri.

**Files:**
- Create: `Package.swift`
- Create: `Sources/Filters/PasteFilter.swift`
- Test: `Tests/FiltersTests/PasteFilterTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum PasteFilter: String, CaseIterable, Sendable { case plainText, collapseWhitespace, straightenQuotes }`
  - `func apply(_ filters: [PasteFilter], to text: String) -> String`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/FiltersTests/PasteFilterTests.swift
import Testing
@testable import Filters

@Test func collapseWhitespaceSqueezesRunsAndTrimsEnds() {
    #expect(apply([.collapseWhitespace], to: "  a   b \n\n c  ") == "a b c")
}

@Test func straightenQuotesReplacesTypographicPairs() {
    #expect(apply([.straightenQuotes], to: "“iyi” ‘gün’ — o’nun") == "\"iyi\" 'gün' — o'nun")
}

@Test func filtersApplyInTheOrderGiven() {
    // straightenQuotes önce çalışırsa collapse'ın göreceği metin değişir;
    // sıra sözleşmenin parçası, karıştırılamaz.
    let result = apply([.straightenQuotes, .collapseWhitespace], to: "  “a”   “b”  ")
    #expect(result == "\"a\" \"b\"")
}

@Test func plainTextIsIdentityOnAStringItOnlyMattersAtThePasteboardLayer() {
    // .plainText metni değiştirmez; anlamı "RTF/HTML temsillerini yazma"dır
    // ve PasteEngine'de karşılığını bulur. Burada kimlik fonksiyonu olması
    // filtre listesinin tek tip kalmasını sağlıyor.
    #expect(apply([.plainText], to: "a b") == "a b")
}
```

- [ ] **Step 2: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Stash", targets: ["Stash"])
    ],
    targets: [
        .target(name: "Filters"),
        .testTarget(name: "FiltersTests", dependencies: ["Filters"]),
    ]
)
```

`Stash` ürünü henüz mevcut olmayan bir hedefe işaret ettiği için bu haliyle çözümlenmez — ürün satırını Task 9'da hedefi eklerken açacağız. Şimdilik `products` dizisini boş bırak:

```swift
    products: [],
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter FiltersTests`
Expected: FAIL — `cannot find 'apply' in scope`

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/Filters/PasteFilter.swift
import Foundation

public enum PasteFilter: String, CaseIterable, Sendable {
    case plainText
    case collapseWhitespace
    case straightenQuotes
}

/// Filtreleri verilen sırayla uygular. Sıra anlamlıdır: bir filtrenin çıktısı
/// bir sonrakinin girdisidir ve kullanıcı ayarlarda sırayı değiştirebilir.
public func apply(_ filters: [PasteFilter], to text: String) -> String {
    filters.reduce(text) { partial, filter in
        switch filter {
        case .plainText:
            return partial
        case .collapseWhitespace:
            return partial
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .straightenQuotes:
            var out = partial
            for (curly, straight) in [("\u{201C}", "\""), ("\u{201D}", "\""),
                                      ("\u{2018}", "'"), ("\u{2019}", "'")] {
                out = out.replacingOccurrences(of: curly, with: straight)
            }
            return out
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FiltersTests`
Expected: PASS — 4 test

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/Filters Tests/FiltersTests
git commit -m "Filters modülünü ve paket iskeletini ekle"
```

---

### Task 2: Clip modeli ve Store'un yazma/okuma yolu

**Files:**
- Create: `Sources/Store/Clip.swift`
- Create: `Sources/Store/ClipStore.swift`
- Modify: `Package.swift`
- Test: `Tests/StoreTests/ClipStoreTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum ClipKind: String, Sendable { case text, image, link, file }`
  - `struct Clip: Identifiable, Sendable` — alanlar: `id: UUID`, `createdAt: Date`, `kind: ClipKind`, `text: String?`, `imagePath: String?`, `sourceBundleID: String?`, `sourceName: String?`, `pinned: Bool`, `shelfID: UUID?`, `contentHash: String`, `byteSize: Int`
  - `final class ClipStore` — `init(directory: URL) throws`, `func insert(_ clip: Clip) throws`, `func recent(limit: Int) throws -> [Clip]`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StoreTests/ClipStoreTests.swift
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
```

- [ ] **Step 2: Add the Store target to Package.swift**

```swift
        .target(name: "Store", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter StoreTests`
Expected: FAIL — `cannot find 'ClipStore' in scope`

- [ ] **Step 4: Write Clip**

```swift
// Sources/Store/Clip.swift
import Foundation

public enum ClipKind: String, Sendable, CaseIterable {
    case text, image, link, file
}

public struct Clip: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let kind: ClipKind
    /// Metin içeriği. `kind == .file` ise dosyanın URL'i burada durur.
    public let text: String?
    public let imagePath: String?
    public let sourceBundleID: String?
    public let sourceName: String?
    public var pinned: Bool
    public var shelfID: UUID?
    /// Aynı içeriğin tekrar kopyalanmasını tanımak için; yeni satır açmak
    /// yerine mevcut satırın tarihi öne alınır.
    public let contentHash: String
    public let byteSize: Int

    public init(id: UUID, createdAt: Date, kind: ClipKind, text: String?,
                imagePath: String?, sourceBundleID: String?, sourceName: String?,
                pinned: Bool, shelfID: UUID?, contentHash: String, byteSize: Int) {
        self.id = id; self.createdAt = createdAt; self.kind = kind
        self.text = text; self.imagePath = imagePath
        self.sourceBundleID = sourceBundleID; self.sourceName = sourceName
        self.pinned = pinned; self.shelfID = shelfID
        self.contentHash = contentHash; self.byteSize = byteSize
    }
}
```

- [ ] **Step 5: Write ClipStore**

```swift
// Sources/Store/ClipStore.swift
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter StoreTests`
Expected: PASS — 4 test

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/Store Tests/StoreTests
git commit -m "Clip modelini ve Store'un yazma/okuma yolunu ekle"
```

---

### Task 3: Store — arama, sabitleme, raf ataması, silme

**Files:**
- Modify: `Sources/Store/ClipStore.swift`
- Test: `Tests/StoreTests/ClipStoreQueryTests.swift`

**Interfaces:**
- Consumes: Task 2'nin `ClipStore`, `Clip`
- Produces: `func search(_ term: String, limit: Int) throws -> [Clip]`, `func setPinned(_ pinned: Bool, id: UUID) throws`, `func setShelf(_ shelfID: UUID?, id: UUID) throws`, `func delete(id: UUID) throws`, `func deleteCreated(after: Date) throws`, `func deleteAll() throws`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StoreTests/ClipStoreQueryTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StoreTests`
Expected: FAIL — `value of type 'ClipStore' has no member 'search'`

- [ ] **Step 3: Implement the query and mutation methods**

```swift
// Sources/Store/ClipStore.swift — sınıfın içine ekle

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreTests`
Expected: PASS — 10 test (Task 2'nin 4'ü + bu 6)

- [ ] **Step 5: Commit**

```bash
git add Sources/Store Tests/StoreTests
git commit -m "Store'a arama, sabitleme, raf ataması ve silme ekle"
```

---

### Task 4: Store — tekrar kopyalama ve disk supabı

**Files:**
- Modify: `Sources/Store/ClipStore.swift`
- Test: `Tests/StoreTests/ClipStorePruneTests.swift`

**Interfaces:**
- Consumes: Task 2-3
- Produces: `func upsert(_ clip: Clip) throws` (aynı `contentHash` varsa tarihi öne alır, yeni satır açmaz), `func imagesByteSize() throws -> Int`, `func pruneImages(highWater: Int, lowWater: Int) throws -> Int` (silinen dosya sayısını döner)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StoreTests/ClipStorePruneTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipStorePruneTests`
Expected: FAIL — `value of type 'ClipStore' has no member 'upsert'`

- [ ] **Step 3: Implement upsert, size accounting and pruning**

```swift
// Sources/Store/ClipStore.swift — sınıfın içine ekle

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
            let bytes = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(at: thumbsDirectory.appendingPathComponent("\(clip.id.uuidString).jpg"))
            try exec("UPDATE clips SET imagePath = NULL WHERE id = '\(clip.id.uuidString)';")
            size -= (bytes ?? 0)
            removed += 1
        }
        return removed
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreTests`
Expected: PASS — 16 test

- [ ] **Step 5: Commit**

```bash
git add Sources/Store Tests/StoreTests
git commit -m "Store'a tekrar kopyalama birleştirmesi ve görsel budaması ekle"
```

---

### Task 5: PasteboardKit — yoklama, tip çözümleme, hassas içerik elemesi

**Files:**
- Create: `Sources/PasteboardKit/PasteboardReading.swift`
- Create: `Sources/PasteboardKit/ClipCapture.swift`
- Modify: `Package.swift`
- Test: `Tests/PasteboardKitTests/ClipCaptureTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `protocol PasteboardReading: Sendable` — `var changeCount: Int { get }`, `var types: [String] { get }`, `func string() -> String?`, `func imageData() -> Data?`, `func fileURLStrings() -> [String]?`
  - `struct CapturedClip: Sendable, Equatable` — `kind: CapturedKind`, `text: String?`, `imageData: Data?`, `contentHash: String`
  - `enum CapturedKind: String, Sendable { case text, image, link, file }`
  - `struct CapturePolicy: Sendable` — `blockedBundleIDs: Set<String>`
  - `final class ClipCapture` — `init(pasteboard: PasteboardReading, policy: CapturePolicy)`, `func poll(frontmostBundleID: String?) -> CapturedClip?`

Kaydetme kararının tamamı burada; `NSPasteboard` bir protokolün arkasında olduğu için testler gerçek pano olmadan çalışır.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PasteboardKitTests/ClipCaptureTests.swift
import Testing
import Foundation
@testable import PasteboardKit

final class FakePasteboard: PasteboardReading, @unchecked Sendable {
    var changeCount = 0
    var types: [String] = []
    var text: String?
    var image: Data?
    var files: [String]?
    func string() -> String? { text }
    func imageData() -> Data? { image }
    func fileURLStrings() -> [String]? { files }

    func put(text: String, types: [String] = ["public.utf8-plain-text"]) {
        self.text = text; self.image = nil; self.files = nil
        self.types = types; changeCount += 1
    }
}

private func capture(_ pb: FakePasteboard, blocked: Set<String> = []) -> ClipCapture {
    ClipCapture(pasteboard: pb, policy: CapturePolicy(blockedBundleIDs: blocked))
}

@Test func firstPollAfterACopyReturnsTheClip() {
    let pb = FakePasteboard(); pb.put(text: "merhaba")
    #expect(capture(pb).poll(frontmostBundleID: nil)?.text == "merhaba")
}

@Test func pollingWithoutAChangeReturnsNothing() {
    // Yoklama saniyede iki kez çalışıyor; değişmeyen panoyu tekrar tekrar
    // kaydetmek geçmişi çöple doldururdu.
    let pb = FakePasteboard(); pb.put(text: "merhaba")
    let c = capture(pb)
    _ = c.poll(frontmostBundleID: nil)
    #expect(c.poll(frontmostBundleID: nil) == nil)
}

@Test func concealedContentIsNeverCaptured() {
    // Şifre yöneticileri panoya bu tipi koyar. Kaydetmek gizlilik ihlali olur.
    let pb = FakePasteboard()
    pb.put(text: "hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
    #expect(capture(pb).poll(frontmostBundleID: nil) == nil)
}

@Test func transientAndAutoGeneratedContentIsSkippedToo() {
    let pb = FakePasteboard()
    pb.put(text: "geçici", types: ["public.utf8-plain-text", "org.nspasteboard.TransientType"])
    #expect(capture(pb).poll(frontmostBundleID: nil) == nil)
    pb.put(text: "üretilmiş", types: ["public.utf8-plain-text", "org.nspasteboard.AutoGeneratedType"])
    #expect(capture(pb).poll(frontmostBundleID: nil) == nil)
}

@Test func copiesFromBlockedAppsAreDropped() {
    let pb = FakePasteboard(); pb.put(text: "parola")
    #expect(capture(pb, blocked: ["com.1password.1password"])
        .poll(frontmostBundleID: "com.1password.1password") == nil)
}

@Test func urlsAreRecognisedAsLinks() {
    let pb = FakePasteboard(); pb.put(text: "https://girltalk.social")
    #expect(capture(pb).poll(frontmostBundleID: nil)?.kind == .link)
}

@Test func plainWordsAreNotLinks() {
    let pb = FakePasteboard(); pb.put(text: "girltalk sosyal")
    #expect(capture(pb).poll(frontmostBundleID: nil)?.kind == .text)
}

@Test func imageDataBecomesAnImageClip() {
    let pb = FakePasteboard()
    pb.image = Data([0x89, 0x50, 0x4E, 0x47]); pb.text = nil
    pb.types = ["public.png"]; pb.changeCount += 1
    let clip = capture(pb).poll(frontmostBundleID: nil)
    #expect(clip?.kind == .image)
    #expect(clip?.imageData != nil)
}

@Test func emptyOrWhitespaceOnlyTextIsIgnored() {
    let pb = FakePasteboard(); pb.put(text: "   \n  ")
    #expect(capture(pb).poll(frontmostBundleID: nil) == nil)
}

@Test func identicalContentHashesTheSameSoTheStoreCanMerge() {
    let pb = FakePasteboard()
    pb.put(text: "aynı")
    let first = capture(pb).poll(frontmostBundleID: nil)
    pb.put(text: "aynı")
    let second = capture(pb).poll(frontmostBundleID: nil)
    #expect(first?.contentHash == second?.contentHash)
}
```

- [ ] **Step 2: Add the PasteboardKit target to Package.swift**

```swift
        .target(name: "PasteboardKit"),
        .testTarget(name: "PasteboardKitTests", dependencies: ["PasteboardKit"]),
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter PasteboardKitTests`
Expected: FAIL — `cannot find type 'PasteboardReading' in scope`

- [ ] **Step 4: Write the protocol and the system pasteboard adapter**

```swift
// Sources/PasteboardKit/PasteboardReading.swift
import AppKit
import Foundation

/// Panoyu protokolün arkasına alıyoruz: yakalama kararlarının tamamı saf kodla
/// test edilebilsin, testler gerçek panoyu kirletmesin.
public protocol PasteboardReading: Sendable {
    var changeCount: Int { get }
    var types: [String] { get }
    func string() -> String?
    func imageData() -> Data?
    func fileURLStrings() -> [String]?
}

public struct SystemPasteboard: PasteboardReading, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    public init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public var changeCount: Int { pasteboard.changeCount }
    public var types: [String] { (pasteboard.types ?? []).map(\.rawValue) }
    public func string() -> String? { pasteboard.string(forType: .string) }
    public func imageData() -> Data? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return data }
        }
        return nil
    }
    public func fileURLStrings() -> [String]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return nil }
        return urls.map(\.path)
    }
}
```

- [ ] **Step 5: Write ClipCapture**

```swift
// Sources/PasteboardKit/ClipCapture.swift
import Foundation
import CryptoKit

public enum CapturedKind: String, Sendable { case text, image, link, file }

public struct CapturedClip: Sendable, Equatable {
    public let kind: CapturedKind
    public let text: String?
    public let imageData: Data?
    public let contentHash: String
}

public struct CapturePolicy: Sendable {
    public var blockedBundleIDs: Set<String>
    public init(blockedBundleIDs: Set<String> = []) {
        self.blockedBundleIDs = blockedBundleIDs
    }
}

public final class ClipCapture {
    /// Diğer uygulamaların "bunu kaydetme" demek için kullandığı iş birliği
    /// tipleri. nspasteboard.org'daki gayriresmî ama yaygın sözleşme.
    static let skipTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    private let pasteboard: PasteboardReading
    private let policy: CapturePolicy
    private var lastChangeCount: Int?

    public init(pasteboard: PasteboardReading, policy: CapturePolicy) {
        self.pasteboard = pasteboard
        self.policy = policy
    }

    public func poll(frontmostBundleID: String?) -> CapturedClip? {
        let count = pasteboard.changeCount
        defer { lastChangeCount = count }
        guard count != lastChangeCount else { return nil }
        guard Set(pasteboard.types).isDisjoint(with: Self.skipTypes) else { return nil }
        if let id = frontmostBundleID, policy.blockedBundleIDs.contains(id) { return nil }

        if let data = pasteboard.imageData(), !data.isEmpty {
            return CapturedClip(kind: .image, text: nil, imageData: data,
                                contentHash: Self.hash(data))
        }
        if let paths = pasteboard.fileURLStrings(), !paths.isEmpty {
            let joined = paths.joined(separator: "\n")
            return CapturedClip(kind: .file, text: joined, imageData: nil,
                                contentHash: Self.hash(Data(joined.utf8)))
        }
        guard let text = pasteboard.string(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return CapturedClip(kind: Self.isLink(text) ? .link : .text, text: text,
                            imageData: nil, contentHash: Self.hash(Data(text.utf8)))
    }

    static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter PasteboardKitTests`
Expected: PASS — 10 test

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/PasteboardKit Tests/PasteboardKitTests
git commit -m "PasteboardKit: yoklama, tip çözümleme ve hassas içerik elemesi"
```

---

### Task 6: HotKey — global kısayol kaydı

**Files:**
- Create: `Sources/HotKey/KeyCombo.swift`
- Create: `Sources/HotKey/HotKeyCenter.swift`
- Modify: `Package.swift`
- Test: `Tests/HotKeyTests/KeyComboTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `struct KeyCombo: Codable, Equatable, Sendable` — `keyCode: UInt32`, `modifiers: UInt32`, `static let defaultCombo` (⌥⌘V), `var displayString: String`
  - `final class HotKeyCenter` — `func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws`, `func unregister()`
  - `enum HotKeyError: Error { case alreadyTaken }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HotKeyTests/KeyComboTests.swift
import Testing
@testable import HotKey

@Test func defaultComboIsOptionCommandV() {
    #expect(KeyCombo.defaultCombo.displayString == "⌥⌘V")
}

@Test func displayStringOrdersModifiersTheWayMacOSDoes() {
    // macOS her yerde ⌃⌥⇧⌘ sırasını kullanır; kendi sıramızı uydurursak
    // ayarlar penceresi sistemin geri kalanından farklı görünür.
    let combo = KeyCombo(keyCode: KeyCombo.keyCodeV,
                         modifiers: KeyCombo.control | KeyCombo.option
                                  | KeyCombo.shift | KeyCombo.command)
    #expect(combo.displayString == "⌃⌥⇧⌘V")
}

@Test func combosRoundTripThroughCodableSoSettingsCanStoreThem() throws {
    let data = try JSONEncoder().encode(KeyCombo.defaultCombo)
    #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == KeyCombo.defaultCombo)
}

@Test func registeringTheSameComboTwiceReportsItIsTaken() throws {
    // Kısayol kapılıysa sessizce ölü bir kısayol bırakmak yerine hata veriyoruz;
    // ayarlar bunu kırmızı uyarıya çevirecek.
    let first = HotKeyCenter()
    try first.register(.defaultCombo) {}
    defer { first.unregister() }
    let second = HotKeyCenter()
    #expect(throws: HotKeyError.alreadyTaken) {
        try second.register(.defaultCombo) {}
    }
}
```

- [ ] **Step 2: Add the HotKey target to Package.swift**

```swift
        .target(name: "HotKey"),
        .testTarget(name: "HotKeyTests", dependencies: ["HotKey"]),
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter HotKeyTests`
Expected: FAIL — `cannot find 'KeyCombo' in scope`

- [ ] **Step 4: Write KeyCombo**

```swift
// Sources/HotKey/KeyCombo.swift
import Carbon.HIToolbox
import Foundation

public struct KeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command = UInt32(cmdKey)
    public static let option = UInt32(optionKey)
    public static let control = UInt32(controlKey)
    public static let shift = UInt32(shiftKey)
    public static let keyCodeV = UInt32(kVK_ANSI_V)

    /// ⌘⇧V değil: global kısayol olarak kaydedilirse her uygulamadaki
    /// "biçimlendirmeyi eşleyerek yapıştır"ı gölgeler.
    public static let defaultCombo = KeyCombo(keyCode: keyCodeV,
                                              modifiers: option | command)

    public var displayString: String {
        var out = ""
        if modifiers & Self.control != 0 { out += "⌃" }
        if modifiers & Self.option != 0 { out += "⌥" }
        if modifiers & Self.shift != 0 { out += "⇧" }
        if modifiers & Self.command != 0 { out += "⌘" }
        out += Self.characterName(for: keyCode)
        return out
    }

    static func characterName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_C: return "C"
        case kVK_Space: return "Space"
        default: return "#\(keyCode)"
        }
    }
}
```

- [ ] **Step 5: Write HotKeyCenter**

```swift
// Sources/HotKey/HotKeyCenter.swift
import Carbon.HIToolbox
import Foundation

public enum HotKeyError: Error, Equatable { case alreadyTaken }

/// RegisterEventHotKey kullanıyoruz, CGEventTap değil: bu API Erişilebilirlik
/// izni istemiyor, dolayısıyla uygulama izin verilmeden de açılabiliyor.
public final class HotKeyCenter {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?
    private static var nextID: UInt32 = 1

    public init() {}

    public func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            let fire = center.handler
            DispatchQueue.main.async { MainActor.assumeIsolated { fire?() } }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        var id = EventHotKeyID(signature: OSType(0x53545348 /* "STSH" */), id: Self.nextID)
        Self.nextID += 1
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            unregister()
            throw HotKeyError.alreadyTaken
        }
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        handler = nil
    }

    deinit { unregister() }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter HotKeyTests`
Expected: PASS — 4 test

Not: `registeringTheSameComboTwiceReportsItIsTaken` gerçek sistem API'sini çağırır. Testi çalıştıran makinede ⌥⌘V başka bir uygulamada kayıtlıysa ilk kayıt da düşer ve test kırmızıya döner — bu durumda test makinesinde o kısayolu tutan uygulamayı kapat.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/HotKey Tests/HotKeyTests
git commit -m "HotKey: global kısayol kaydı ve çakışma raporlama"
```

---

### Task 7: PasteEngine — panoya geri yazma ve sentetik ⌘V

**Files:**
- Create: `Sources/PasteEngine/PasteWriting.swift`
- Create: `Sources/PasteEngine/PasteEngine.swift`
- Modify: `Package.swift`
- Test: `Tests/PasteEngineTests/PasteEngineTests.swift`

**Interfaces:**
- Consumes: `Filters.PasteFilter`, `Filters.apply(_:to:)`
- Produces:
  - `protocol PasteWriting: AnyObject` — `func writeText(_ text: String, plainOnly: Bool)`, `func writeImage(_ data: Data)`
  - `protocol KeystrokeSending: AnyObject` — `var isTrusted: Bool { get }`, `func sendCommandV()`
  - `enum PasteOutcome: Equatable { case pastedIntoFrontmostApp, copiedOnlyNoAccessibilityPermission }`
  - `final class PasteEngine` — `init(pasteboard: PasteWriting, keystrokes: KeystrokeSending)`, `func paste(text: String, filters: [PasteFilter]) -> PasteOutcome`, `func paste(imageData: Data) -> PasteOutcome`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PasteEngineTests/PasteEngineTests.swift
import Testing
import Foundation
import Filters
@testable import PasteEngine

final class FakePasteboardWriter: PasteWriting {
    var lastText: String?
    var lastPlainOnly = false
    var lastImage: Data?
    func writeText(_ text: String, plainOnly: Bool) { lastText = text; lastPlainOnly = plainOnly }
    func writeImage(_ data: Data) { lastImage = data }
}

final class FakeKeystrokes: KeystrokeSending {
    var isTrusted = true
    var sentCount = 0
    func sendCommandV() { sentCount += 1 }
}

@Test func pastingWritesToThePasteboardThenSendsCommandV() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(text: "merhaba", filters: [])
    #expect(pb.lastText == "merhaba")
    #expect(keys.sentCount == 1)
    #expect(outcome == .pastedIntoFrontmostApp)
}

@Test func withoutAccessibilityPermissionItCopiesAndSaysSo() {
    // İzin yoksa uygulama çalışmaya devam etmeli; sessizce hiçbir şey
    // yapmamak en kötü davranış olurdu.
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(text: "merhaba", filters: [])
    #expect(pb.lastText == "merhaba")
    #expect(keys.sentCount == 0)
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}

@Test func filtersRunBeforeTheTextReachesThePasteboard() {
    let pb = FakePasteboardWriter()
    _ = PasteEngine(pasteboard: pb, keystrokes: FakeKeystrokes())
        .paste(text: "  a   b  ", filters: [.collapseWhitespace])
    #expect(pb.lastText == "a b")
}

@Test func plainTextFilterAsksThePasteboardForPlainOnly() {
    // .plainText metni değiştirmez; anlamı zengin temsilleri yazmamaktır,
    // ve bu karar pano katmanında verilir.
    let pb = FakePasteboardWriter()
    _ = PasteEngine(pasteboard: pb, keystrokes: FakeKeystrokes())
        .paste(text: "kalın metin", filters: [.plainText])
    #expect(pb.lastPlainOnly == true)
}

@Test func imagesGoThroughTheSamePermissionLogic() {
    let pb = FakePasteboardWriter(); let keys = FakeKeystrokes()
    keys.isTrusted = false
    let outcome = PasteEngine(pasteboard: pb, keystrokes: keys).paste(imageData: Data([1, 2, 3]))
    #expect(pb.lastImage == Data([1, 2, 3]))
    #expect(outcome == .copiedOnlyNoAccessibilityPermission)
}
```

- [ ] **Step 2: Add the PasteEngine target to Package.swift**

```swift
        .target(name: "PasteEngine", dependencies: ["Filters"]),
        .testTarget(name: "PasteEngineTests", dependencies: ["PasteEngine", "Filters"]),
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter PasteEngineTests`
Expected: FAIL — `cannot find type 'PasteWriting' in scope`

- [ ] **Step 4: Write the protocols and their system implementations**

```swift
// Sources/PasteEngine/PasteWriting.swift
import AppKit
import ApplicationServices
import Foundation

public protocol PasteWriting: AnyObject {
    func writeText(_ text: String, plainOnly: Bool)
    func writeImage(_ data: Data)
}

public protocol KeystrokeSending: AnyObject {
    var isTrusted: Bool { get }
    func sendCommandV()
}

public final class SystemPasteboardWriter: PasteWriting {
    public init() {}
    public func writeText(_ text: String, plainOnly: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
    public func writeImage(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }
}

public final class SystemKeystrokeSender: KeystrokeSending {
    public init() {}

    /// Her yapıştırmadan önce bakıyoruz: kullanıcı izni Sistem Ayarları'ndan
    /// sonradan geri alabilir ve uygulama bunu başka türlü öğrenemez.
    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 5: Write PasteEngine**

```swift
// Sources/PasteEngine/PasteEngine.swift
import Filters
import Foundation

public enum PasteOutcome: Equatable {
    case pastedIntoFrontmostApp
    case copiedOnlyNoAccessibilityPermission
}

public final class PasteEngine {
    private let pasteboard: PasteWriting
    private let keystrokes: KeystrokeSending

    public init(pasteboard: PasteWriting, keystrokes: KeystrokeSending) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    public func paste(text: String, filters: [PasteFilter]) -> PasteOutcome {
        pasteboard.writeText(apply(filters, to: text),
                             plainOnly: filters.contains(.plainText))
        return deliver()
    }

    public func paste(imageData: Data) -> PasteOutcome {
        pasteboard.writeImage(imageData)
        return deliver()
    }

    private func deliver() -> PasteOutcome {
        guard keystrokes.isTrusted else { return .copiedOnlyNoAccessibilityPermission }
        keystrokes.sendCommandV()
        return .pastedIntoFrontmostApp
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter PasteEngineTests`
Expected: PASS — 5 test

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/PasteEngine Tests/PasteEngineTests
git commit -m "PasteEngine: panoya geri yazma, sentetik ⌘V ve izinsiz düşüş"
```

---

### Task 8: StashCore — ayarlar, koordinasyon ve şerit görünüm modeli

**Files:**
- Create: `Sources/StashCore/Settings.swift`
- Create: `Sources/StashCore/StripModel.swift`
- Create: `Sources/StashCore/CaptureCoordinator.swift`
- Modify: `Package.swift`
- Test: `Tests/StashCoreTests/StripModelTests.swift`

**Interfaces:**
- Consumes: `Store`, `PasteboardKit`, `PasteEngine`, `Filters`, `HotKey`
- Produces:
  - `struct Settings: Codable, Sendable` — `combo: KeyCombo`, `activeFilters: [PasteFilter]`, `blockedBundleIDs: Set<String>`, `launchAtLogin: Bool`; `static let defaults` (kara liste varsayılanı: `com.1password.1password`, `com.apple.keychainaccess`)
  - `enum StripTab: Equatable, Sendable { case all, pinned, images, shelf(UUID) }`
  - `@MainActor final class StripModel` — `init(store: ClipStore, engine: PasteEngine, settings: Settings)`, `var query: String`, `var tab: StripTab`, `var visible: [Clip]`, `var selectedIndex: Int`, `func reload() throws`, `func moveSelection(by: Int)`, `func pasteSelected(applyingFilters: Bool) -> PasteOutcome?`, `func togglePinSelected() throws`, `func deleteSelected() throws`
  - `@MainActor final class CaptureCoordinator` — `init(store: ClipStore, capture: ClipCapture, interval: TimeInterval)`, `func start()`, `func stop()`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StashCoreTests/StripModelTests.swift
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
    func sendCommandV() {}
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

@MainActor @Test func defaultBlocklistCoversThePasswordManagers() {
    #expect(Settings.defaults.blockedBundleIDs.contains("com.1password.1password"))
    #expect(Settings.defaults.blockedBundleIDs.contains("com.apple.keychainaccess"))
}
```

- [ ] **Step 2: Add the StashCore target to Package.swift**

```swift
        .target(name: "StashCore",
                dependencies: ["Store", "PasteboardKit", "PasteEngine", "Filters", "HotKey"]),
        .testTarget(name: "StashCoreTests",
                    dependencies: ["StashCore", "Store", "PasteEngine", "Filters"]),
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter StashCoreTests`
Expected: FAIL — `cannot find 'StripModel' in scope`

- [ ] **Step 4: Write Settings**

```swift
// Sources/StashCore/Settings.swift
import Filters
import Foundation
import HotKey

public struct Settings: Codable, Sendable, Equatable {
    public var combo: KeyCombo
    public var activeFilters: [PasteFilter]
    public var blockedBundleIDs: Set<String>
    public var launchAtLogin: Bool

    public static let defaults = Settings(
        combo: .defaultCombo,
        activeFilters: [.plainText],
        // Şifre yöneticileri panoya iş birliği tipi koymayı unutabiliyor;
        // kara liste ikinci savunma hattı.
        blockedBundleIDs: ["com.1password.1password", "com.apple.keychainaccess"],
        launchAtLogin: false)

    private static let key = "settings"

    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .defaults }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 5: Write StripModel**

```swift
// Sources/StashCore/StripModel.swift
import Filters
import Foundation
import PasteEngine
import Store

public enum StripTab: Equatable, Sendable {
    case all, pinned, images
    case shelf(UUID)
}

@MainActor
public final class StripModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var tab: StripTab = .all
    @Published public private(set) var visible: [Clip] = []
    @Published public private(set) var selectedIndex: Int = 0
    public var settings: Settings

    private let store: ClipStore
    private let engine: PasteEngine
    private static let pageSize = 300

    public init(store: ClipStore, engine: PasteEngine, settings: Settings) {
        self.store = store
        self.engine = engine
        self.settings = settings
    }

    public func reload() throws {
        let base = query.isEmpty
            ? try store.recent(limit: Self.pageSize)
            : try store.search(query, limit: Self.pageSize)
        visible = base.filter { clip in
            switch tab {
            case .all: return true
            case .pinned: return clip.pinned
            case .images: return clip.kind == .image
            case .shelf(let id): return clip.shelfID == id
            }
        }
        // Liste değiştiğinde eski indekste kalmak yanlış kartı yapıştırır.
        selectedIndex = 0
    }

    public func moveSelection(by delta: Int) {
        guard !visible.isEmpty else { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex + delta, 0), visible.count - 1)
    }

    public func select(index: Int) {
        guard visible.indices.contains(index) else { return }
        selectedIndex = index
    }

    public func pasteSelected(applyingFilters: Bool) -> PasteOutcome? {
        guard visible.indices.contains(selectedIndex) else { return nil }
        let clip = visible[selectedIndex]
        let filters = applyingFilters ? settings.activeFilters : []
        if clip.kind == .image, let path = clip.imagePath,
           let data = FileManager.default.contents(atPath: path) {
            return engine.paste(imageData: data)
        }
        guard let text = clip.text else { return nil }
        return engine.paste(text: text, filters: filters)
    }

    public func togglePinSelected() throws {
        guard visible.indices.contains(selectedIndex) else { return }
        let clip = visible[selectedIndex]
        try store.setPinned(!clip.pinned, id: clip.id)
        try reload()
    }

    public func moveSelectedToShelf(_ shelfID: UUID?) throws {
        guard visible.indices.contains(selectedIndex) else { return }
        try store.setShelf(shelfID, id: visible[selectedIndex].id)
        try reload()
    }

    public func deleteSelected() throws {
        guard visible.indices.contains(selectedIndex) else { return }
        try store.delete(id: visible[selectedIndex].id)
        try reload()
    }
}
```

- [ ] **Step 6: Write CaptureCoordinator**

```swift
// Sources/StashCore/CaptureCoordinator.swift
import AppKit
import Foundation
import PasteboardKit
import Store

/// Panoyu yoklayıp yakalananı diske yazar. macOS pano değişimini bildirmediği
/// için zamanlayıcı tek yol; 0,5 saniye kullanıcıya anlık hissettiriyor ve
/// boşta ölçülebilir CPU yakmıyor.
@MainActor
public final class CaptureCoordinator {
    private let store: ClipStore
    private let capture: ClipCapture
    private let interval: TimeInterval
    private var timer: Timer?
    public var onError: ((Error) -> Void)?
    public var onCapture: (() -> Void)?

    public init(store: ClipStore, capture: ClipCapture, interval: TimeInterval = 0.5) {
        self.store = store
        self.capture = capture
        self.interval = interval
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    func tick() {
        let front = NSWorkspace.shared.frontmostApplication
        guard let captured = capture.poll(frontmostBundleID: front?.bundleIdentifier) else { return }
        do {
            let id = UUID()
            var imagePath: String?
            if let data = captured.imageData {
                let url = store.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
                try data.write(to: url)
                imagePath = url.path
            }
            try store.upsert(Clip(
                id: id, createdAt: Date(),
                kind: ClipKind(rawValue: captured.kind.rawValue) ?? .text,
                text: captured.text, imagePath: imagePath,
                sourceBundleID: front?.bundleIdentifier,
                sourceName: front?.localizedName,
                pinned: false, shelfID: nil,
                contentHash: captured.contentHash,
                byteSize: captured.imageData?.count ?? (captured.text?.utf8.count ?? 0)))
            try store.pruneImages(highWater: 2_000_000_000, lowWater: 1_500_000_000)
            onCapture?()
        } catch {
            // Disk hatası uygulamayı düşürmemeli: o kopya kaybolur, menü
            // çubuğu uyarır, yoklama devam eder.
            onError?(error)
        }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter StashCoreTests`
Expected: PASS — 8 test

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/StashCore Tests/StashCoreTests
git commit -m "StashCore: ayarlar, şerit görünüm modeli ve yakalama koordinatörü"
```

---

### Task 9: Uygulama kabuğu — menü çubuğu ve şerit penceresi

Bu taskın sonunda uygulama gerçekten açılıyor: ⌥⌘V şeridi getirip götürüyor, içi henüz boş.

**Files:**
- Create: `Sources/Stash/main.swift`
- Create: `Sources/Stash/AppDelegate.swift`
- Create: `Sources/Stash/StripPanel.swift`
- Create: `Sources/Stash/Info.plist`
- Create: `scripts/bundle.sh`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `StashCore`, `HotKey`
- Produces: `final class StripPanel: NSPanel` — `init(contentView: NSView)`, `func show(on screen: NSScreen)`, `func dismiss()`; `var onDismiss: (() -> Void)?`

- [ ] **Step 1: Add the executable target and product to Package.swift**

```swift
    products: [
        .executable(name: "Stash", targets: ["Stash"])
    ],
```

```swift
        .executableTarget(name: "Stash", dependencies: ["StashCore", "HotKey"],
                          exclude: ["Info.plist"]),
```

- [ ] **Step 2: Write Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Stash</string>
  <key>CFBundleDisplayName</key><string>Stash</string>
  <key>CFBundleIdentifier</key><string>social.selin.stash</string>
  <key>CFBundleExecutable</key><string>Stash</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licensed</string>
</dict>
</plist>
```

- [ ] **Step 3: Write StripPanel**

```swift
// Sources/Stash/StripPanel.swift
import AppKit

/// Şerit penceresi. Üç ayar bu sınıfın tamamının varlık sebebi:
/// - .nonactivatingPanel: panel açılınca öndeki uygulama önde kalır, yoksa
///   geri yapıştıracağımız uygulama arkaya düşer ve ⌘V yanlış yere gider.
/// - .canJoinAllSpaces: Space değiştirince pencere kendi Space'ine zıplamaz.
/// - .fullScreenAuxiliary: tam ekran uygulamaların üstünde de görünür.
final class StripPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var monitor: Any?

    static let height: CGFloat = 300

    init(contentView view: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: Self.height),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        self.contentView = view
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    func show(on screen: NSScreen) {
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                           width: screen.frame.width, height: Self.height)
        // Aşağıdan yukarı kayma: önce ekranın altına gizle, sonra yerine sür.
        setFrame(frame.offsetBy(dx: 0, dy: -Self.height), display: false)
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
        }
        installDismissMonitor()
    }

    func dismiss() {
        removeDismissMonitor()
        orderOut(nil)
        onDismiss?()
    }

    /// Dışarı tıklamayı yakalar. Panel key olduğu için resignKey tek başına
    /// yetmiyor: kullanıcı başka uygulamaya tıkladığında da kapanmalı.
    private func installDismissMonitor() {
        removeDismissMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeDismissMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
}
```

- [ ] **Step 4: Write AppDelegate and main**

```swift
// Sources/Stash/AppDelegate.swift
import AppKit
import HotKey
import PasteboardKit
import PasteEngine
import StashCore
import Store
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: StripPanel?
    private var hotKey = HotKeyCenter()
    private var coordinator: CaptureCoordinator?
    private var model: StripModel?
    private var settings = Settings.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.on.square.dashed",
                                     accessibilityDescription: "Stash")
        item.menu = buildMenu()
        statusItem = item

        do {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
                .appendingPathComponent("Stash")
            let store = try ClipStore(directory: dir)
            let engine = PasteEngine(pasteboard: SystemPasteboardWriter(),
                                     keystrokes: SystemKeystrokeSender())
            let model = StripModel(store: store, engine: engine, settings: settings)
            self.model = model

            let capture = ClipCapture(pasteboard: SystemPasteboard(),
                                      policy: CapturePolicy(blockedBundleIDs: settings.blockedBundleIDs))
            let coordinator = CaptureCoordinator(store: store, capture: capture)
            coordinator.onCapture = { [weak self] in try? self?.model?.reload() }
            coordinator.onError = { [weak self] _ in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle",
                    accessibilityDescription: "Stash: disk hatası")
            }
            coordinator.start()
            self.coordinator = coordinator
        } catch {
            presentFatal(error)
            return
        }

        registerHotKey()
    }

    private func registerHotKey() {
        do {
            try hotKey.register(settings.combo) { [weak self] in self?.toggleStrip() }
        } catch {
            // Sessiz ölü kısayol en kötü sonuç: kullanıcı tuşa basar, hiçbir
            // şey olmaz ve sebebini öğrenemez.
            let alert = NSAlert()
            alert.messageText = "Kısayol kaydedilemedi"
            alert.informativeText = """
                \(settings.combo.displayString) başka bir uygulama tarafından kullanılıyor. \
                Ayarlar'dan farklı bir kombinasyon seç.
                """
            alert.runModal()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Stash'i aç", action: #selector(toggleStrip), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc func toggleStrip() {
        if let panel, panel.isVisible { panel.dismiss(); return }
        guard let model else { return }
        try? model.reload()
        let host = NSHostingView(rootView: Text("Şerit buraya gelecek")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.9)))
        let panel = self.panel ?? StripPanel(contentView: host)
        panel.contentView = host
        self.panel = panel
        panel.show(on: Self.screenWithMouse())
    }

    /// Şerit farenin bulunduğu ekranda açılır; iki ekranlı kurulumda "yanlış
    /// ekranda açıldı" en sık şikayet edilen davranış.
    static func screenWithMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main!
    }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Stash başlatılamadı"
        alert.informativeText = "\(error)"
        alert.runModal()
        NSApp.terminate(nil)
    }
}
```

```swift
// Sources/Stash/main.swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 5: Write scripts/bundle.sh**

```bash
#!/usr/bin/env bash
# Builds "Stash.app" from the SwiftPM executable.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Stash.app"

swift build -c "$CONFIG" --package-path "$ROOT"
BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

# Çalışan kopyanın bundle'ını silmek kendi çalıştırılabilirini altından çeker:
# macOS binary'yi tembel sayfalar, ihtiyaç duyduğu bir sonraki sayfa yok olur
# ve süreç bus error alır. Önce kapatıyoruz.
if pgrep -x Stash >/dev/null 2>&1; then
    osascript -e 'quit app id "social.selin.stash"' >/dev/null 2>&1 || pkill -x Stash || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x Stash >/dev/null 2>&1 || break
        sleep 0.3
    done
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Stash" "$APP/Contents/MacOS/Stash"
cp "$ROOT/Sources/Stash/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc imza. Erişilebilirlik izni imzaya bağlanır: imza her derlemede
# değişirse macOS izni unutur, o yüzden ad-hoc imzayı sabit tutuyoruz.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
```

- [ ] **Step 6: Build and run the app by hand**

```bash
chmod +x scripts/bundle.sh
swift build
./scripts/bundle.sh debug
open build/Stash.app
```

Doğrula: menü çubuğunda ikon var; ⌥⌘V şeridi alttan getiriyor; Esc ve dışarı tıklama kapatıyor; şerit açıkken öndeki uygulamanın başlık çubuğu **soluklaşmıyor** (odak çalınmıyor).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/Stash scripts/bundle.sh
git commit -m "Uygulama kabuğu: menü çubuğu öğesi ve şerit penceresi"
```

---

### Task 10: Şerit görünümü — kartlar

**Files:**
- Create: `Sources/Stash/Theme.swift`
- Create: `Sources/Stash/ClipCardView.swift`
- Create: `Sources/Stash/StripView.swift`
- Modify: `Sources/Stash/AppDelegate.swift` (yer tutucu `Text` yerine `StripView`)

**Interfaces:**
- Consumes: `StashCore.StripModel`, `Store.Clip`
- Produces: `struct StripView: View` — `init(model: StripModel, onDismiss: @escaping () -> Void)`; `struct ClipCardView: View` — `init(clip: Clip, isSelected: Bool)`

Spec'teki görsel dil: panel degradesi `#3A2D50` → `#211D2D`, vurgu `#A06CF5`, kart 162×200 (seçili 224 yüksek), tip etiketi mono ve büyük harf.

- [ ] **Step 1: Write Theme**

```swift
// Sources/Stash/Theme.swift
import SwiftUI

enum Theme {
    static let panelTop = Color(red: 0x3A/255, green: 0x2D/255, blue: 0x50/255)
    static let panelBottom = Color(red: 0x21/255, green: 0x1D/255, blue: 0x2D/255)
    static let accent = Color(red: 0xA0/255, green: 0x6C/255, blue: 0xF5/255)
    static let cardFill = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.11)
    static let cardFillSelected = Color.white.opacity(0.17)
    static let cardStrokeSelected = Color.white.opacity(0.45)
    static let label = Color(red: 0xA9/255, green: 0x9F/255, blue: 0xC0/255)
    static let body = Color(red: 0xCD/255, green: 0xC6/255, blue: 0xDC/255)

    static let cardWidth: CGFloat = 162
    static let cardHeight: CGFloat = 200
    static let cardHeightSelected: CGFloat = 224
}
```

- [ ] **Step 2: Write ClipCardView**

```swift
// Sources/Stash/ClipCardView.swift
import Store
import SwiftUI

struct ClipCardView: View {
    let clip: Clip
    let isSelected: Bool

    private var typeLabel: String {
        switch clip.kind {
        case .text: return "METİN"
        case .image: return "GÖRSEL"
        case .link: return "BAĞLANTI"
        case .file: return "DOSYA"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(typeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(0.6)
                    .foregroundStyle(Theme.label)
                Spacer()
                if clip.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                }
            }
            content
            if let source = clip.sourceName {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.label.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: Theme.cardWidth,
               height: isSelected ? Theme.cardHeightSelected : Theme.cardHeight,
               alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(isSelected ? Theme.cardFillSelected : Theme.cardFill))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? Theme.cardStrokeSelected : Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(isSelected ? 0.4 : 0), radius: 10, y: 6)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder private var content: some View {
        if clip.kind == .image {
            if let path = clip.imagePath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                // Budanmış veya kayıp görsel: kart yalan söylemesin.
                Text("görsel artık saklanmıyor")
                    .font(.system(size: 11)).foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            Text(clip.text ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.body)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
```

- [ ] **Step 3: Write StripView**

```swift
// Sources/Stash/StripView.swift
import StashCore
import SwiftUI

struct StripView: View {
    @ObservedObject var model: StripModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, clip in
                            ClipCardView(clip: clip, isSelected: index == model.selectedIndex)
                                .id(clip.id)
                                .onTapGesture { model.select(index: index) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
                .onChange(of: model.selectedIndex) { _, new in
                    guard model.visible.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(model.visible[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Stash").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white).kerning(0.5)
            if !model.query.isEmpty {
                Text(model.query)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if model.visible.isEmpty {
                Text(model.query.isEmpty
                     ? "Henüz bir şey kopyalamadın."
                     : "Eşleşen kart yok.")
                    .font(.system(size: 12)).foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 17)
    }
}
```

- [ ] **Step 4: Wire it into AppDelegate**

`toggleStrip()` içindeki yer tutucuyu değiştir:

```swift
        let host = NSHostingView(rootView: StripView(model: model,
                                                     onDismiss: { [weak self] in
            self?.panel?.dismiss()
        }))
```

- [ ] **Step 5: Build and check by eye**

```bash
./scripts/bundle.sh debug && open build/Stash.app
```

Birkaç şey kopyala (metin, bir ekran görüntüsü, bir link), ⌥⌘V'ye bas. Doğrula: kartlar spec'teki ölçülerde, seçili kart büyüyor, görsel kartında gerçek önizleme var, kartın altında kaynak uygulama yazıyor.

- [ ] **Step 6: Commit**

```bash
git add Sources/Stash
git commit -m "Şerit görünümü: kart tasarımı ve plum panel"
```

---

### Task 11: Klavye — gezinme, arama, yapıştırma kısayolları

**Files:**
- Create: `Sources/Stash/StripKeyHandler.swift`
- Modify: `Sources/Stash/StripPanel.swift`
- Modify: `Sources/Stash/AppDelegate.swift`
- Test: `Tests/StashCoreTests/StripKeyCommandTests.swift`

**Interfaces:**
- Consumes: `StashCore.StripModel`
- Produces:
  - `enum StripKeyCommand: Equatable, Sendable { case moveLeft, moveRight, paste(filtered: Bool), pasteIndex(Int), togglePin, delete, nextTab, dismiss, type(Character), backspace }`
  - `func stripCommand(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> StripKeyCommand?`

Tuş eşlemesi saf bir fonksiyona alınıyor: `NSEvent` üretmeden test edilebilsin.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StashCoreTests/StripKeyCommandTests.swift
import Testing
import AppKit
@testable import StashCore

@Test func arrowKeysMoveTheSelection() {
    #expect(stripCommand(keyCode: 123, characters: nil, modifiers: []) == .moveLeft)
    #expect(stripCommand(keyCode: 124, characters: nil, modifiers: []) == .moveRight)
}

@Test func returnPastesAndOptionReturnPastesFiltered() {
    #expect(stripCommand(keyCode: 36, characters: "\r", modifiers: []) == .paste(filtered: false))
    #expect(stripCommand(keyCode: 36, characters: "\r", modifiers: [.option]) == .paste(filtered: true))
}

@Test func commandDigitsPasteByPosition() {
    #expect(stripCommand(keyCode: 18, characters: "1", modifiers: [.command]) == .pasteIndex(0))
    #expect(stripCommand(keyCode: 26, characters: "9", modifiers: [.command]) == .pasteIndex(8))
}

@Test func controlPPinsAndDeleteRemoves() {
    #expect(stripCommand(keyCode: 35, characters: "p", modifiers: [.control]) == .togglePin)
    #expect(stripCommand(keyCode: 51, characters: nil, modifiers: []) == .delete)
}

@Test func plainCharactersBecomeSearchInput() {
    #expect(stripCommand(keyCode: 0, characters: "a", modifiers: []) == .type("a"))
}

@Test func modifiedCharactersAreNotSearchInput() {
    // ⌘A "hepsini seç" olabilir; arama alanına 'a' yazmak yanlış olurdu.
    #expect(stripCommand(keyCode: 0, characters: "a", modifiers: [.command]) != .type("a"))
}

@Test func escapeDismisses() {
    #expect(stripCommand(keyCode: 53, characters: nil, modifiers: []) == .dismiss)
}
```

- [ ] **Step 2: Add the file to StashCore and run the test**

Dosya `Sources/StashCore/StripKeyCommand.swift` olarak `StashCore` içine yazılır (test hedefi zaten `StashCore`'a bağlı).

Run: `swift test --filter StripKeyCommandTests`
Expected: FAIL — `cannot find 'stripCommand' in scope`

- [ ] **Step 3: Write the mapping**

```swift
// Sources/StashCore/StripKeyCommand.swift
import AppKit

public enum StripKeyCommand: Equatable, Sendable {
    case moveLeft, moveRight
    case paste(filtered: Bool)
    case pasteIndex(Int)
    case togglePin, delete, nextTab, dismiss
    case type(Character)
    case backspace
}

public func stripCommand(keyCode: UInt16, characters: String?,
                         modifiers: NSEvent.ModifierFlags) -> StripKeyCommand? {
    let mods = modifiers.intersection([.command, .option, .control, .shift])
    switch keyCode {
    case 123: return .moveLeft
    case 124: return .moveRight
    case 53: return .dismiss
    case 48: return .nextTab                    // Tab
    case 51: return mods.isEmpty ? .delete : nil // Delete
    case 36: return .paste(filtered: mods.contains(.option))
    default: break
    }
    if mods == [.control], characters?.lowercased() == "p" { return .togglePin }
    if mods == [.command], let digit = characters.flatMap({ Int($0) }), (1...9).contains(digit) {
        return .pasteIndex(digit - 1)
    }
    // Değiştiricisiz karakterler arama alanına gider; ⌘/⌃/⌥ ile basılanlar
    // komut olabilir, onları metin sanmak yanlış olur.
    if mods.isEmpty || mods == [.shift], let char = characters?.first, !char.isNewline {
        return .type(char)
    }
    return nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StripKeyCommandTests`
Expected: PASS — 7 test

- [ ] **Step 5: Route real key events through it**

`StripPanel` içine ekle:

```swift
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        // Panel key olduğu için bütün tuşlar buraya düşer; işlemediğimizi
        // super'e bırakıyoruz ki sistem sesleri boşuna çalmasın.
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
```

`AppDelegate.toggleStrip()` içinde paneli kurarken:

```swift
        panel.onKey = { [weak self] event in
            guard let self, let model = self.model else { return false }
            guard let command = stripCommand(keyCode: event.keyCode,
                                             characters: event.charactersIgnoringModifiers,
                                             modifiers: event.modifierFlags) else { return false }
            switch command {
            case .moveLeft: model.moveSelection(by: -1)
            case .moveRight: model.moveSelection(by: 1)
            case .paste(let filtered):
                self.finishPaste(model.pasteSelected(applyingFilters: filtered))
            case .pasteIndex(let index):
                model.select(index: index)
                self.finishPaste(model.pasteSelected(applyingFilters: false))
            case .togglePin: try? model.togglePinSelected()
            case .delete: try? model.deleteSelected()
            case .nextTab: self.advanceTab()
            case .dismiss: self.panel?.dismiss()
            case .type(let char):
                model.query.append(char)
                try? model.reload()
            case .backspace:
                if !model.query.isEmpty { model.query.removeLast(); try? model.reload() }
            }
            return true
        }
```

Ve yapıştırma sonrası davranış:

```swift
    private func finishPaste(_ outcome: PasteOutcome?) {
        panel?.dismiss()
        model?.query = ""
        guard outcome == .copiedOnlyNoAccessibilityPermission else { return }
        // Sessizce kopyalayıp bırakmıyoruz: kullanıcı ⌘V beklerken hiçbir şey
        // olmadığını görürse uygulamayı bozuk sanır.
        let alert = NSAlert()
        alert.messageText = "Panoya kopyalandı"
        alert.informativeText = """
            Doğrudan yapıştırma için Stash'in Erişilebilirlik izni gerekiyor. \
            Şimdilik ⌘V ile yapıştırabilirsin.
            """
        alert.addButton(withTitle: "İzin ver")
        alert.addButton(withTitle: "Şimdi değil")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func advanceTab() {
        guard let model else { return }
        model.tab = switch model.tab {
        case .all: .pinned
        case .pinned: .images
        default: .all
        }
        try? model.reload()
    }
```

`.backspace`'i eşlemeye eklemeyi unutma: `case 51` şu an `.delete` döndürüyor. Arama açıkken silme tuşu kartı değil harfi silmeli:

```swift
    case 51: return mods.isEmpty ? .backspace : nil
```

ve kart silme ⌘⌫ olur:

```swift
    if mods == [.command], keyCode == 51 { return .delete }
```

Testi de buna göre güncelle:

```swift
@Test func deleteEditsTheSearchTextAndCommandDeleteRemovesTheCard() {
    #expect(stripCommand(keyCode: 51, characters: nil, modifiers: []) == .backspace)
    #expect(stripCommand(keyCode: 51, characters: nil, modifiers: [.command]) == .delete)
}
```

- [ ] **Step 6: Run tests and drive the app**

Run: `swift test --filter StashCoreTests` → PASS
Run: `./scripts/bundle.sh debug && open build/Stash.app`

Doğrula: ok tuşları geziyor, yazınca süzülüyor, ⌫ harf siliyor, ⌘⌫ kart siliyor, ↵ yapıştırıyor, ⌘2 ikinci kartı yapıştırıyor, ⌃P sabitliyor, ⇥ sekme değiştiriyor.

- [ ] **Step 7: Commit**

```bash
git add Sources/Stash Sources/StashCore Tests/StashCoreTests
git commit -m "Şeritte klavye gezinmesi, arama ve yapıştırma kısayolları"
```

---

### Task 12: Sekmeler ve raflar

**Files:**
- Create: `Sources/Store/Shelf.swift`
- Modify: `Sources/Store/ClipStore.swift`
- Modify: `Sources/Stash/StripView.swift`
- Test: `Tests/StoreTests/ShelfTests.swift`

**Interfaces:**
- Consumes: Task 2-3
- Produces: `struct Shelf: Identifiable, Sendable, Equatable { let id: UUID; var name: String }`; `ClipStore` üzerinde `func createShelf(name: String) throws -> Shelf`, `func shelves() throws -> [Shelf]`, `func renameShelf(_ id: UUID, to: String) throws`, `func deleteShelf(_ id: UUID) throws`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StoreTests/ShelfTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShelfTests`
Expected: FAIL — `value of type 'ClipStore' has no member 'createShelf'`

- [ ] **Step 3: Implement shelves**

```swift
// Sources/Store/Shelf.swift
import Foundation

public struct Shelf: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
```

`ClipStore.init` içindeki şema oluşturmaya ekle:

```swift
        try exec("""
            CREATE TABLE IF NOT EXISTS shelves (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              createdAt REAL NOT NULL
            );
            """)
```

Sınıfa ekle:

```swift
    public func createShelf(name: String) throws -> Shelf {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.queryFailed("raf adı boş olamaz") }
        let shelf = Shelf(id: UUID(), name: trimmed)
        try exec("""
            INSERT INTO shelves (id, name, createdAt)
            VALUES ('\(shelf.id.uuidString)',
                    '\(trimmed.replacingOccurrences(of: "'", with: "''"))',
                    \(Date().timeIntervalSince1970));
            """)
        return shelf
    }

    public func shelves() throws -> [Shelf] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, name FROM shelves ORDER BY createdAt ASC",
                                 -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var out: [Shelf] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(stmt, 0),
                  let nameText = sqlite3_column_text(stmt, 1),
                  let id = UUID(uuidString: String(cString: idText)) else { continue }
            out.append(Shelf(id: id, name: String(cString: nameText)))
        }
        return out
    }

    public func renameShelf(_ id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.queryFailed("raf adı boş olamaz") }
        try exec("""
            UPDATE shelves SET name = '\(trimmed.replacingOccurrences(of: "'", with: "''"))'
            WHERE id = '\(id.uuidString)';
            """)
    }

    /// Rafı siler ama kartlarını silmez: kullanıcı klasörü kaldırıyor,
    /// içindekini çöpe atmıyor.
    public func deleteShelf(_ id: UUID) throws {
        try exec("UPDATE clips SET shelfID = NULL WHERE shelfID = '\(id.uuidString)';")
        try exec("DELETE FROM shelves WHERE id = '\(id.uuidString)';")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreTests`
Expected: PASS — 19 test

- [ ] **Step 5: Add the tab bar to StripView**

`StripView.header` içine, `Text("Stash")`'in sağına:

```swift
            ForEach(tabs, id: \.self) { entry in
                Text(entry.title)
                    .font(.system(size: 12))
                    .padding(.horizontal, 13).padding(.vertical, 4)
                    .background(Capsule().fill(model.tab == entry.tab
                                               ? Theme.accent : Color.white.opacity(0.1)))
                    .foregroundStyle(model.tab == entry.tab ? .white : Theme.body)
                    .onTapGesture {
                        model.tab = entry.tab
                        try? model.reload()
                    }
            }
```

ve `StripView` içine:

```swift
    struct TabEntry: Hashable { let title: String; let tab: StripTab }

    private var tabs: [TabEntry] {
        // İlk üçü sabit ve silinemez: raf değiller, kayıt üzerindeki alanlara
        // bakan süzgeçler.
        [TabEntry(title: "Tümü", tab: .all),
         TabEntry(title: "Sabitlenen", tab: .pinned),
         TabEntry(title: "Görseller", tab: .images)]
        + model.shelves.map { TabEntry(title: $0.name, tab: .shelf($0.id)) }
    }
```

`StripModel`'e raf listesi ve ⌃S eylemi ekle:

```swift
    @Published public private(set) var shelves: [Shelf] = []

    public func reloadShelves() throws { shelves = try store.shelves() }
```

`reload()` sonuna `try reloadShelves()` ekle. `advanceTab()` artık rafları da dolaşmalı:

```swift
    private func advanceTab() {
        guard let model else { return }
        let all: [StripTab] = [.all, .pinned, .images] + model.shelves.map { .shelf($0.id) }
        let index = all.firstIndex(of: model.tab) ?? 0
        model.tab = all[(index + 1) % all.count]
        try? model.reload()
    }
```

`StripKeyCommand`'a `case moveToShelf` ekle ve ⌃S'yi eşle:

```swift
    if mods == [.control], characters?.lowercased() == "s" { return .moveToShelf }
```

`AppDelegate` bunu bir menüye bağlar: ⌃S basılınca `NSMenu` popup'ı raf listesini gösterir ve seçilen rafa `model.moveSelectedToShelf(_:)` çağrılır.

- [ ] **Step 6: Build and drive**

```bash
./scripts/bundle.sh debug && open build/Stash.app
```

Doğrula: Tümü/Sabitlenen/Görseller sekmeleri süzüyor, ⇥ aralarında dolaşıyor.

- [ ] **Step 7: Commit**

```bash
git add Sources/Store Sources/Stash Sources/StashCore Tests/StoreTests
git commit -m "Raflar ve şerit sekmeleri"
```

---

### Task 13: Ayarlar penceresi

**Files:**
- Create: `Sources/Stash/SettingsView.swift`
- Create: `Sources/Stash/SettingsWindowController.swift`
- Modify: `Sources/Stash/AppDelegate.swift`

**Interfaces:**
- Consumes: `StashCore.Settings`, `Store.ClipStore`, `HotKey.KeyCombo`
- Produces: `final class SettingsWindowController: NSWindowController` — `init(settings: Settings, store: ClipStore, onChange: @escaping (Settings) -> Void)`, `func present()`

Spec'teki ayarlar yüzeyi: kısayol, açılışta başlat, aktif filtreler ve sıraları, kara liste, raf yönetimi, disk kullanımı + temizleme, Erişilebilirlik izni durumu.

- [ ] **Step 1: Write SettingsView**

```swift
// Sources/Stash/SettingsView.swift
import ApplicationServices
import Filters
import HotKey
import StashCore
import Store
import SwiftUI

struct SettingsView: View {
    @State var settings: Settings
    let store: ClipStore
    let onChange: (Settings) -> Void
    @State private var diskText = "hesaplanıyor…"
    @State private var shelves: [Shelf] = []
    @State private var newShelfName = ""

    var body: some View {
        Form {
            Section("Kısayol") {
                LabeledContent("Şeridi aç", value: settings.combo.displayString)
                Text("Değiştirmek için kombinasyona bas.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Yapıştırma filtreleri") {
                ForEach(PasteFilter.allCases, id: \.self) { filter in
                    Toggle(title(for: filter), isOn: binding(for: filter))
                }
                Text("Filtreler ⌥↵ ile yapıştırırken listedeki sırayla uygulanır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kaydedilmeyecek uygulamalar") {
                ForEach(Array(settings.blockedBundleIDs).sorted(), id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Kaldır") {
                            settings.blockedBundleIDs.remove(id); onChange(settings)
                        }
                    }
                }
            }
            Section("Raflar") {
                ForEach(shelves) { shelf in Text(shelf.name) }
                HStack {
                    TextField("Yeni raf", text: $newShelfName)
                    Button("Ekle") {
                        guard let _ = try? store.createShelf(name: newShelfName) else { return }
                        newShelfName = ""
                        shelves = (try? store.shelves()) ?? []
                    }
                }
            }
            Section("Geçmiş") {
                LabeledContent("Görsellerin kapladığı alan", value: diskText)
                Button("Son bir saati temizle") {
                    try? store.deleteCreated(after: Date().addingTimeInterval(-3600))
                    refresh()
                }
                Button("Tümünü temizle", role: .destructive) {
                    try? store.deleteAll(); refresh()
                }
                Text("Sabitlediğin kartlar temizlemelerden etkilenmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("İzin") {
                LabeledContent("Erişilebilirlik",
                               value: AXIsProcessTrusted() ? "verildi" : "verilmedi")
                if !AXIsProcessTrusted() {
                    Button("Sistem Ayarları'nı aç") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Text("İzin olmadan Stash yapıştırmaz, sadece panoya kopyalar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        shelves = (try? store.shelves()) ?? []
        let bytes = (try? store.imagesByteSize()) ?? 0
        diskText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func title(for filter: PasteFilter) -> String {
        switch filter {
        case .plainText: return "Düz metin olarak yapıştır"
        case .collapseWhitespace: return "Fazla boşlukları temizle"
        case .straightenQuotes: return "Akıllı tırnakları düzelt"
        }
    }

    private func binding(for filter: PasteFilter) -> Binding<Bool> {
        Binding(
            get: { settings.activeFilters.contains(filter) },
            set: { isOn in
                if isOn { settings.activeFilters.append(filter) }
                else { settings.activeFilters.removeAll { $0 == filter } }
                onChange(settings)
            })
    }
}
```

- [ ] **Step 2: Write SettingsWindowController**

```swift
// Sources/Stash/SettingsWindowController.swift
import AppKit
import StashCore
import Store
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(settings: Settings, store: ClipStore,
                     onChange: @escaping (Settings) -> Void) {
        let view = SettingsView(settings: settings, store: store, onChange: onChange)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Stash Ayarları"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        // Ayarlar penceresi normal bir pencere: LSUIElement uygulaması olduğumuz
        // için öne gelmesi elle etkinleştirme istiyor.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: Hook it into the menu**

`AppDelegate.buildMenu()` içine:

```swift
        menu.addItem(withTitle: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
```

```swift
    private var settingsController: SettingsWindowController?

    @objc func openSettings() {
        guard let store = self.store else { return }
        let controller = settingsController ?? SettingsWindowController(
            settings: settings, store: store) { [weak self] updated in
                guard let self else { return }
                self.settings = updated
                updated.save()
                // Kısayol değiştiyse yeniden kaydet: eski kombinasyon canlı
                // kalırsa kullanıcı iki kısayolla açar ve sebebini anlamaz.
                self.registerHotKey()
                self.model?.settings = updated
            }
        settingsController = controller
        controller.present()
    }
```

`AppDelegate`'e `private var store: ClipStore?` alanını ekle ve `applicationDidFinishLaunching` içinde doldur.

- [ ] **Step 4: Build and drive**

```bash
./scripts/bundle.sh debug && open build/Stash.app
```

Doğrula: menüden Ayarlar açılıyor; filtre açıp kapatmak ⌥↵ davranışını değiştiriyor; "Tümünü temizle" sabitlenenleri bırakıyor; disk boyutu gerçek değeri gösteriyor.

- [ ] **Step 5: Commit**

```bash
git add Sources/Stash
git commit -m "Ayarlar penceresi"
```

---

### Task 14: Hassas içerik maskeleme

**Files:**
- Create: `Sources/PasteboardKit/SensitivePatterns.swift`
- Modify: `Sources/Stash/ClipCardView.swift`
- Test: `Tests/PasteboardKitTests/SensitivePatternsTests.swift`

**Interfaces:**
- Consumes: —
- Produces: `enum SensitivePatterns` — `static func isSensitive(_ text: String) -> Bool`, `static func mask(_ text: String) -> String`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PasteboardKitTests/SensitivePatternsTests.swift
import Testing
@testable import PasteboardKit

@Test func cardNumbersAreMaskedToTheLastFour() {
    #expect(SensitivePatterns.isSensitive("4242 4242 4242 4242"))
    #expect(SensitivePatterns.mask("4242 4242 4242 4242") == "•••• 4242")
}

@Test func cardNumbersWithoutSpacesAreCaughtToo() {
    #expect(SensitivePatterns.isSensitive("4242424242424242"))
}

@Test func longRandomLookingTokensAreMasked() {
    #expect(SensitivePatterns.isSensitive("ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"))
}

@Test func ordinarySentencesAreNotSensitive() {
    // Yanlış pozitif maskeleme, maskelemenin kendisinden daha can sıkıcı olur.
    #expect(!SensitivePatterns.isSensitive("bugün hava çok güzel ve biraz uzun bir cümle"))
    #expect(!SensitivePatterns.isSensitive("brew install --cask maccy"))
}

@Test func shortStringsAreNeverTokens() {
    #expect(!SensitivePatterns.isSensitive("abc123"))
}

@Test func maskedTokensShowNothingButTheirLength() {
    let masked = SensitivePatterns.mask("ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8")
    #expect(masked.hasPrefix("••••"))
    #expect(!masked.contains("ghp_"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SensitivePatternsTests`
Expected: FAIL — `cannot find 'SensitivePatterns' in scope`

- [ ] **Step 3: Implement the patterns**

```swift
// Sources/PasteboardKit/SensitivePatterns.swift
import Foundation

/// Kart içeriğinin omuz üstünden okunmasını engeller. Kayıt silinmez —
/// kullanıcı kendi verisine erişebilmeli — sadece varsayılan olarak gizlenir.
public enum SensitivePatterns {
    public static func isSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }
        if isCardNumber(trimmed) { return true }
        return isHighEntropyToken(trimmed)
    }

    public static func mask(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCardNumber(trimmed) {
            let digits = trimmed.filter(\.isNumber)
            return "•••• " + String(digits.suffix(4))
        }
        return String(repeating: "•", count: min(trimmed.count, 24))
    }

    static func isCardNumber(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }
        // Rakam ve boşluk/tire dışında bir şey varsa kart numarası değildir.
        return text.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" }
    }

    static func isHighEntropyToken(_ text: String) -> Bool {
        // Tek parça, uzun, hem harf hem rakam içeren diziler: API anahtarları
        // ve oturum jetonları böyle görünür, normal cümleler görünmez.
        guard !text.contains(" "), text.count >= 24 else { return false }
        let hasLetter = text.contains(where: \.isLetter)
        let hasDigit = text.contains(where: \.isNumber)
        guard hasLetter, hasDigit else { return false }
        let alphabet = Set(text.lowercased())
        return alphabet.count >= 12
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PasteboardKitTests`
Expected: PASS — 16 test

- [ ] **Step 5: Use it in the card**

`ClipCardView` içine:

```swift
    @State private var revealed = false

    private var displayText: String {
        guard let text = clip.text else { return "" }
        guard SensitivePatterns.isSensitive(text), !revealed else { return text }
        return SensitivePatterns.mask(text)
    }
```

`content` içindeki `Text(clip.text ?? "")` yerine `Text(displayText)` ve kartın gövdesine:

```swift
        .onTapGesture(count: 2) { revealed = true }
```

Kart üstüne küçük bir ipucu:

```swift
            if SensitivePatterns.isSensitive(clip.text ?? ""), !revealed {
                Text("çift tıkla, göster")
                    .font(.system(size: 9)).foregroundStyle(Theme.label.opacity(0.7))
            }
```

`Sources/Stash/ClipCardView.swift` dosyasına `import PasteboardKit` ekle ve `Package.swift`'te `Stash` hedefine `"PasteboardKit"` bağımlılığını ekle.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/PasteboardKit Sources/Stash Tests/PasteboardKitTests
git commit -m "Hassas içerik maskeleme"
```

---

### Task 15: Açılışta başlat, README ve elle QA

**Files:**
- Create: `Sources/StashCore/LoginItem.swift`
- Create: `README.md`
- Create: `LICENSE`
- Create: `CHANGELOG.md`
- Create: `docs/manual-qa.md`
- Modify: `Sources/Stash/SettingsView.swift`

**Interfaces:**
- Consumes: —
- Produces: `enum LoginItem` — `static var isEnabled: Bool`, `static func setEnabled(_ enabled: Bool) throws`

- [ ] **Step 1: Write LoginItem**

```swift
// Sources/StashCore/LoginItem.swift
import Foundation
import ServiceManagement

/// SMAppService kullanıyoruz: macOS 13'ten beri doğru yol bu ve kullanıcı
/// öğeyi Sistem Ayarları > Giriş Öğeleri'nde görüp kapatabiliyor.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
```

`SettingsView`'a ekle:

```swift
            Section("Genel") {
                Toggle("Açılışta başlat", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { try? LoginItem.setEnabled($0) }))
            }
```

- [ ] **Step 2: Write README.md**

```markdown
# Stash

macOS için pano geçmişi. Kopyaladıklarını ekranın altına yapışan bir kart
şeridinde gösterir; ⌥⌘V ile açılır, seçtiğini doğrudan öndeki uygulamaya
yapıştırır.

## Gizlilik

- **Ağ kodu yok.** Uygulama hiçbir sunucuya bağlanmaz. Kaynakta `URLSession`,
  `Network` veya soket kullanımı bulamazsınız — arayarak doğrulayabilirsiniz.
- **Şifre yöneticileri kaydedilmez.** Panoya `org.nspasteboard.ConcealedType`
  koyan uygulamaların içeriği hiç yazılmaz. 1Password ve Keychain Access
  ayrıca kara listededir.
- **Kart numaraları ve jetonlar maskelenir.** Kartta gizli görünür, çift
  tıklayınca açılır.
- **Veritabanı şifreli değildir.** `~/Library/Application Support/Stash/`
  dizini yalnızca sizin kullanıcınıza açıktır (0700), ama şifreleme için
  FileVault'a güvenir. Disk şifresi kapalıysa geçmiş düz metin olarak durur.

## Kurulum

Homebrew paketi ve imzalı sürüm yok; kaynaktan kurulur.

```bash
git clone https://github.com/selinihtyr/stash-clipboard.git
cd stash-clipboard
./scripts/bundle.sh
cp -R build/Stash.app /Applications/
open /Applications/Stash.app
```

İlk açılışta macOS imzasız uygulamayı engelleyebilir: `/Applications` içinde
Stash'e sağ tıklayıp **Aç** deyin.

## İzinler

Doğrudan yapıştırma için **Erişilebilirlik** izni gerekir (Sistem Ayarları →
Gizlilik ve Güvenlik → Erişilebilirlik). İzin vermezseniz Stash çalışmaya
devam eder, sadece seçtiğinizi panoya kopyalar ve ⌘V'yi size bırakır.

Global kısayol için izin gerekmez.

## Kısayollar

| Tuş | İş |
|---|---|
| ⌥⌘V | Şeridi aç/kapat |
| ← → | Kartlar arasında gez |
| yazmak | Geçmişte ara |
| ↵ | Yapıştır |
| ⌥↵ | Filtreleri uygulayarak yapıştır |
| ⌘1…⌘9 | Sıradaki kartı yapıştır |
| ⌃P | Sabitle |
| ⌃S | Rafa taşı |
| ⌘⌫ | Kartı sil |
| ⇥ | Sekme değiştir |
| Esc | Kapat |

## Geliştirme

```bash
swift test           # bütün modüller
./scripts/bundle.sh debug
```

Mimari ve kararlar: `docs/superpowers/specs/2026-08-04-stash-clipboard-design.md`

## Lisans

MIT
```

- [ ] **Step 3: Write LICENSE and CHANGELOG**

`LICENSE`: MIT metni, telif sahibi `Selin Göncü`, yıl `2026`.

```markdown
# Changelog

## 0.1.0 — yayınlanmadı

İlk sürüm.

- Metin, görsel, bağlantı ve dosya kopyalarının geçmişi
- Ekranın altına yapışık kart şeridi, ⌥⌘V ile açılır
- Yazarak arama
- Doğrudan yapıştırma (Erişilebilirlik izniyle), izinsizse panoya kopyalama
- Sabitleme ve raflar
- Yapıştırma filtreleri: düz metin, boşluk temizleme, akıllı tırnak düzeltme
- Hassas içerik koruması: iş birliği tipleri, uygulama kara listesi, desen maskeleme
- Elle temizleme; görseller 2 GB'ı aşarsa en eskiler budanır
```

- [ ] **Step 4: Write the manual QA checklist**

```markdown
# Elle QA

Otomatik test edilemeyen davranışlar. Her sürümden önce gerçek makinede.

## Odak
- [ ] Bir metin editöründe yazarken ⌥⌘V'ye bas. Editörün başlık çubuğu
      soluklaşmamalı, imleç yanıp sönmeye devam etmeli.
- [ ] ↵ ile yapıştır. Metin editöre girmeli, Stash'e değil.

## Ekranlar
- [ ] İki ekranlı kurulumda fareyi ikinci ekrana götür, ⌥⌘V. Şerit farenin
      olduğu ekranda açılmalı.
- [ ] Ekran çözünürlüğünü değiştir, tekrar dene.

## Space ve tam ekran
- [ ] Tam ekran bir uygulamada ⌥⌘V. Şerit üstte açılmalı, Space değişmemeli.
- [ ] Şerit açıkken Space değiştir. Şerit önceki Space'e takılıp kalmamalı.

## İzin
- [ ] Erişilebilirlik iznini kaldır, uygulamayı yeniden başlat, ↵ ile yapıştır.
      "Panoya kopyalandı" uyarısı çıkmalı, uygulama çökmemeli.
- [ ] İzni ver, uygulamayı yeniden başlatmadan tekrar dene. Yapıştırmalı.

## Kısayol çakışması
- [ ] ⌥⌘V'yi kullanan başka bir uygulama açıkken Stash'i başlat. Uyarı
      penceresi çıkmalı, sessiz kalmamalı.

## Veri
- [ ] Şifre yöneticisinden bir parola kopyala. Geçmişte görünmemeli.
- [ ] Bir kart numarası kopyala. Kartta maskeli görünmeli.
- [ ] 20-30 ekran görüntüsü kopyala, Ayarlar'da disk boyutunun büyüdüğünü gör.
- [ ] "Tümünü temizle" sonrası sabitlenen kartların kaldığını doğrula.
```

- [ ] **Step 5: Run the full suite and the checklist**

```bash
swift test
./scripts/bundle.sh
open build/Stash.app
```

`docs/manual-qa.md` listesini baştan sona uygula. Kırmızı kalan madde varsa düzeltilmeden sürüm işaretlenmez.

- [ ] **Step 6: Commit**

```bash
git add Sources README.md LICENSE CHANGELOG.md docs/manual-qa.md
git commit -m "Açılışta başlat, README, lisans ve elle QA listesi"
```

---

## Self-Review

**Spec coverage:**

| Spec bölümü | Task |
|---|---|
| Kart şeridi, 300px, alt kenar | 9 (pencere), 10 (kartlar) |
| Metin/görsel/bağlantı/dosya yakalama | 5 |
| Yazarak arama | 3 (sorgu), 8 (model), 11 (tuşlar) |
| Doğrudan yapıştırma + izinsiz düşüş | 7, 11 |
| Sabitleme ve raflar | 3, 12 |
| Yapıştırma filtreleri | 1, 7, 13 |
| Hassas içerik: iş birliği tipleri | 5 |
| Hassas içerik: kara liste | 5, 8 (varsayılanlar), 13 (yönetim) |
| Hassas içerik: desen maskeleme | 14 |
| Elle temizleme | 3, 13 |
| Disk supabı (2 GB → 1,5 GB, sabitlenenler hariç) | 4, 8 (çağrı) |
| Tekrar kopyalama birleştirmesi | 4 |
| `sourceApp` kartta | 8 (yakalama), 10 (görünüm) |
| Global kısayol + çakışma uyarısı | 6, 9 |
| Ayarlar yüzeyi | 13, 15 (açılışta başlat) |
| Hata durumları tablosu | 8 (disk), 9 (açılış, kısayol), 11 (izin), 10 (kayıp görsel) |
| Space/tam ekran davranışı | 9, 15 (QA) |
| Dağıtım: bundle.sh, README, LICENSE, CHANGELOG | 9, 15 |
| Veri dizini 0700 | 2 |
| Ağ kodu yok | Global Constraints, 15 (README iddiası) |

Açık kalan tek spec maddesi: **SQLite bozulduğunda yedekleyip yeni veritabanı açma.** Task 2'deki `init` şu an hatayı yukarı fırlatıyor ve Task 9 bunu ölümcül uyarıya çeviriyor — spec ise "yedekle, yeni aç, kullanıcıya söyle" diyor. Bu davranışı Task 2'ye eklemek yerine ayrı bırakıyorum çünkü kurtarma yolu kendi testini hak ediyor:

### Task 16: SQLite kurtarma

**Files:**
- Modify: `Sources/Store/ClipStore.swift`
- Test: `Tests/StoreTests/ClipStoreRecoveryTests.swift`

**Interfaces:**
- Consumes: Task 2
- Produces: `ClipStore.init(directory:)` bozuk veritabanında yedek alır ve boş bir veritabanıyla açılır; `var recoveredFromCorruption: URL?` yedeğin yolunu verir.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StoreTests/ClipStoreRecoveryTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipStoreRecoveryTests`
Expected: FAIL — `value of type 'ClipStore' has no member 'recoveredFromCorruption'`

- [ ] **Step 3: Implement recovery**

`ClipStore` içinde şema oluşturma çağrısını sarmala:

```swift
    public private(set) var recoveredFromCorruption: URL?

    // init içinde, sqlite3_open'dan sonra:
        do {
            try exec("PRAGMA journal_mode=WAL;")
            try createSchema()
        } catch {
            // Bozuk dosyayı silmiyoruz: kullanıcının verisi olabilir ve
            // kurtarma denemesi bize değil ona ait.
            sqlite3_close(db); db = nil
            let backup = directory.appendingPathComponent(
                "stash-corrupt-\(Int(Date().timeIntervalSince1970)).sqlite")
            try? FileManager.default.moveItem(
                at: directory.appendingPathComponent("stash.sqlite"), to: backup)
            recoveredFromCorruption = backup
            guard sqlite3_open(path, &db) == SQLITE_OK else {
                throw StoreError.openFailed(String(cString: sqlite3_errmsg(db)))
            }
            try exec("PRAGMA journal_mode=WAL;")
            try createSchema()
        }
```

Şema oluşturmayı `private func createSchema() throws` içine taşı (Task 2 ve Task 12'deki `CREATE TABLE` ifadeleri).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StoreTests`
Expected: PASS — 21 test

- [ ] **Step 5: Tell the user in AppDelegate**

`applicationDidFinishLaunching` içinde store kurulduktan sonra:

```swift
            if let backup = store.recoveredFromCorruption {
                let alert = NSAlert()
                alert.messageText = "Geçmiş veritabanı okunamadı"
                alert.informativeText = """
                    Stash boş bir geçmişle açıldı. Eski dosya silinmedi, \
                    yanına kopyalandı: \(backup.lastPathComponent)
                    """
                alert.runModal()
            }
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Store Sources/Stash Tests/StoreTests
git commit -m "Bozuk veritabanından kurtarma"
```

---

**Placeholder scan:** Yok. Her adımda çalıştırılacak komut, beklenen çıktı ve kod var.

**Type consistency:** `Clip`, `ClipKind`, `CapturedClip`, `CapturedKind`, `PasteOutcome`, `StripTab`, `StripKeyCommand`, `Settings`, `Shelf` isimleri tanımlandıkları taskla kullanıldıkları tasklarda aynı. Task 11'de `case 51` önce `.delete` sonra `.backspace` olarak iki kez tanımlanıyor — Step 5 bunu açıkça düzeltiyor ve testi de güncelliyor, kasıtlı.
