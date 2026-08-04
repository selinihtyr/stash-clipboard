import Foundation

/// Tek bir dosyanın izleyici için önemli olan kısmı: yolu ve boyutu.
/// Boyut, "dosya tamamen yazıldı mı" kararını veren istikrar kontrolünde
/// kullanılıyor (bkz. `ScreenshotWatcher`).
public struct ScreenshotFileInfo: Equatable, Sendable {
    public let url: URL
    public let size: Int
    public init(url: URL, size: Int) {
        self.url = url
        self.size = size
    }
}

/// `ScreenshotWatcher`in gerçek `FileManager` okumasının arkasına alındığı
/// ince arayüz. Asıl amacı dizin YOLUNU sahtelemek değil (buna bir `URL`
/// closure'ı zaten yetiyor) — TCC izin reddini gerçek bir Masaüstü/Belgeler
/// erişim reddi üretmeden testte deterministik olarak üretebilmek. Gerçek
/// uygulamada `FileManager.contentsOfDirectory` korumalı bir klasörde daha
/// önce hiç izin verilmemişse bir sistem izin istemi gösterip kullanıcı
/// yanıt verene kadar bloklanır, reddedilirse hata fırlatır; testler bunu
/// gerçek bir istem tetiklemeden, hata fırlatan sahte bir okuyucuyla taklit
/// ediyor.
public protocol ScreenshotDirectoryReading: Sendable {
    func contentsOfDirectory(at url: URL) throws -> [ScreenshotFileInfo]
}

public struct FileManagerScreenshotDirectoryReader: ScreenshotDirectoryReading {
    public init() {}

    public func contentsOfDirectory(at url: URL) throws -> [ScreenshotFileInfo] {
        let fm = FileManager.default
        // BURASI TCC kapısı: Masaüstü/Belgeler/İndirilenler gibi korumalı bir
        // klasörde daha önce hiç izin sorulmadıysa bu çağrı senkron bir
        // sistem izin istemi gösterir ve kullanıcı yanıt verene kadar
        // bloklanır; reddedilirse `throw` eder — `ScreenshotWatcher` bunu
        // yakalayıp durumu `.permissionDenied`e çeviriyor (görev kuralı 7).
        let urls = try fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])
        return urls.compactMap { fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            // Alt dizinleri ve paket/klasör türü dosyaları (nadir ama
            // olası) atlıyoruz — bir ekran görüntüsü her zaman düz bir
            // dosyadır.
            guard values?.isRegularFile == true else { return nil }
            return ScreenshotFileInfo(url: fileURL, size: values?.fileSize ?? 0)
        }
    }
}
