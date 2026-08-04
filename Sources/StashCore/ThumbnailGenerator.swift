import AppKit
import Foundation

/// Kart, orijinal ekran görüntüsünü tam çözünürlükte açmasın diye ayrı, küçük
/// bir JPEG üretir — bkz. Task 10 fix round 1: LazyHStack sadece kaç kartın
/// kurulacağını sınırlıyordu, her kartın kendi maliyetini değil. Üretim
/// başarısız olursa çağıran orijinali diskte bırakmaya devam eder; küçük
/// resim kayıptan asla klibin kendisini götürmez.
enum ThumbnailGenerator {
    /// Kartın görsel alanı ~138×150pt; Retina için uzun kenarda bunun
    /// yaklaşık iki katını (300pt) hedefliyoruz. Zaten daha küçük olan
    /// görseller büyütülmez — `scale` asla 1'i aşmaz.
    static func makeJPEG(from data: Data, maxLongEdge: CGFloat = 300) -> Data? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, maxLongEdge / longEdge)
        let targetSize = NSSize(width: (image.size.width * scale).rounded(.up),
                                 height: (image.size.height * scale).rounded(.up))

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1)
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
