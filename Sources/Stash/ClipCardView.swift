import PasteboardKit
import Store
import SwiftUI

struct ClipCardView: View {
    let clip: Clip
    let isSelected: Bool

    // Bilerek klibin kimliğine (Store.Clip.id, ForEach'te .id(clip.id) ile
    // eşleşir) bağlı, panel-genelinde değil: LazyHStack kaydırırken kartları
    // geri kullanabilir ama SwiftUI @State'i identity'e göre taşır, pozisyona
    // göre değil — yanlış kartın açığa çıkması bu yüzden olmuyor. Panel her
    // kapanışta gerçek pencere/host view'ı da atılıp yeniden kuruluyor
    // (bkz. AppDelegate.toggleStrip), o yüzden yeniden açılış zaten maskeli
    // başlıyor; burada ekstra bir "sıfırla" mantığı gerekmiyor.
    @State private var revealed = false

    private var typeLabel: String {
        switch clip.kind {
        case .text: return "METİN"
        case .image: return "GÖRSEL"
        case .link: return "BAĞLANTI"
        case .file: return "DOSYA"
        }
    }

    private var isSensitive: Bool {
        shouldMask(kind: clip.kind, text: clip.text)
    }

    private var displayText: String {
        guard let text = clip.text else { return "" }
        guard isSensitive, !revealed else { return text }
        return SensitivePatterns.mask(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(typeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(0.6)
                    .foregroundStyle(Theme.label)
                Spacer()
                if isSensitive, !revealed {
                    Text("çift tıkla, göster")
                        .font(.system(size: 9)).foregroundStyle(Theme.label.opacity(0.7))
                }
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
        // count: 2 kasıtlı: tek tıklama zaten StripView'de seçim yapıyor
        // (ForEach içindeki .onTapGesture { model.select(...) }); çift tık
        // olmasaydı her seçim aynı zamanda açığa çıkarırdı.
        .onTapGesture(count: 2) { revealed = true }
    }

    @ViewBuilder private var content: some View {
        if clip.kind == .image {
            // Küçük resim varsa onu tercih et: LazyHStack görünüme yakın
            // kartları kursa da her kart hâlâ NSImage(contentsOfFile:) ile
            // senkron çözüyor — orijinal ekran görüntüsünü değil, küçük
            // resmi çözmek bu maliyeti gerçekten düşürüyor. Küçük resim
            // üretilememişse (üretim başarısız olmuş ya da bu klip küçük
            // resimler eklenmeden önce yakalanmış) orijinale dönmek zorunlu:
            // yoksa her eski klip bu düşer.
            if let path = clip.thumbPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let path = clip.imagePath, let image = NSImage(contentsOfFile: path) {
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
            Text(displayText)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.body)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
