import Foundation
import Store

/// "Bir görsel klibi depoya yaz" mantığının tek yeri. `CaptureCoordinator`
/// (pano) ve `ScreenshotWatcher` (ekran görüntüsü klasörü) aynı adımları
/// izlemek ZORUNDA: var olan satırı contentHash'e göre bul, dosyası eksikse
/// (ilk yakalama ya da budanmış — bkz. I3) yeniden yaz, küçük resim üret,
/// satırı upsert et. Bu ikisinin birbirinden bağımsız kopyalar tutması,
/// orphan-önleme sırasının (dosya SATIRDAN önce yazılır — yazma başarısız
/// olursa hiç var olmayan bir dosyaya işaret eden satır oluşmaz) ikisinde de
/// doğru kalmasını umuda bırakırdı. Tek yer, tek doğruluk kaynağı — aynı
/// zamanda görev kuralı 6'nın ("aynı görsel iki kez gelirse tek satır")
/// dayandığı `ClipStore.upsert`in contentHash eşleşmesi, iki çağıranın da
/// AYNI hash algoritmasını (bkz. `ClipCapture.hash`) kullanmasına bağlı.
@MainActor
struct ImageClipWriter {
    let store: ClipStore

    @discardableResult
    func write(imageData: Data, contentHash: String,
               sourceBundleID: String?, sourceName: String?,
               createdAt: Date = Date()) throws -> Clip {
        let existing = try store.find(contentHash: contentHash)
        let id = existing?.id ?? UUID()
        var imagePath = existing?.imagePath
        let fileMissing = imagePath.map { !FileManager.default.fileExists(atPath: $0) } ?? true
        if fileMissing {
            let url = store.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
            try imageData.write(to: url)
            imagePath = url.path
            // Küçük resim türetilmiş bir dosya; üretimi başarısız olsa da
            // (ör. çözülemeyen veri) yakalama yine de başarılı sayılır.
            if let thumbData = ThumbnailGenerator.makeJPEG(from: imageData) {
                let thumbURL = store.thumbsDirectory.appendingPathComponent("\(id.uuidString).jpg")
                try? thumbData.write(to: thumbURL)
            }
        }
        let clip = Clip(
            id: id, createdAt: createdAt, kind: .image,
            text: nil, imagePath: imagePath,
            sourceBundleID: sourceBundleID, sourceName: sourceName,
            pinned: false, shelfID: nil,
            contentHash: contentHash, byteSize: imageData.count)
        try store.upsert(clip)
        return clip
    }
}
