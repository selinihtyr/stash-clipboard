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

    /// `ClipStore` yazar orijinali `images/<id>.png`, küçük resmi (varsa)
    /// `thumbs/<id>.jpg` olarak, ikisi de aynı depo dizininin kardeş alt
    /// dizinlerinde — bkz. `ClipStore.imagesDirectory`/`thumbsDirectory`.
    /// Buradan yola çıkarak dosyaya dokunmadan beklenen yolu türetiyoruz;
    /// dosya orada olmayabilir (küçük resim üretilememiş ya da bu klip
    /// küçük resimler eklenmeden önce yakalanmış) — çağıran orijinale
    /// dönmeli, `imagePath` gibi bunun da var olduğunu varsaymamalı.
    public var thumbPath: String? {
        guard let imagePath else { return nil }
        let imagesDir = URL(fileURLWithPath: imagePath).deletingLastPathComponent()
        let root = imagesDir.deletingLastPathComponent()
        return root.appendingPathComponent("thumbs")
            .appendingPathComponent("\(id.uuidString).jpg").path
    }
}
