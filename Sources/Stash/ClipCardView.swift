import PasteboardKit
import Store
import StashCore
import SwiftUI

struct ClipCardView: View {
    @ObservedObject var model: StripModel
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

    // Sabitleme/⋯ kontrolleri sadece fare kartın üstündeyken görünür (bkz.
    // dosya sonundaki hoverControls). Aynı sebeple identity'e bağlı: panel
    // her açılışta yeniden kurulduğundan burada da fazladan bir "sıfırla"
    // gerekmiyor.
    @State private var isHovering = false
    @State private var showingNewShelfPrompt = false
    @State private var newShelfName = ""
    @State private var shelfCreationError: String?

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
                // Hover'dayken bu ikonun yerini hoverControls'teki sabitle
                // düğmesi alır — o düğme dolu/boş ikonuyla zaten aynı durumu
                // anlatıyor (bkz. o değişkenin üstündeki not), ikisini aynı
                // anda göstermek aynı bilgiyi iki kere basardı.
                if clip.pinned, !isHovering {
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
        // Kontroller kartın üstüne BİNDİRİLİYOR (overlay), VStack'e satır
        // olarak eklenmiyor: aksi halde görünmelerinin kendisi kartın
        // boyunu değiştirip metni kaydırırdı — brief'in yasakladığı tam da
        // bu. onHover, hover'da mı olduğumuzu söyleyen tek gerçek kaynak;
        // .overlay içindeki `if` de ondan başka bir şeye bakmıyor.
        .overlay(alignment: .topTrailing) {
            if isHovering { hoverControls.padding(8) }
        }
        .onHover { hovering in isHovering = hovering }
        .alert("Yeni raf", isPresented: $showingNewShelfPrompt) {
            TextField("Raf adı", text: $newShelfName)
            Button("Oluştur") { createShelfAndMove() }
            Button("Vazgeç", role: .cancel) { newShelfName = "" }
        } message: {
            Text("Rafa bir ad ver.")
        }
        .alert("Raf oluşturulamadı", isPresented: Binding(
            get: { shelfCreationError != nil },
            set: { if !$0 { shelfCreationError = nil } }
        )) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(shelfCreationError ?? "")
        }
    }

    /// Sabitle düğmesi + ⋯ taşma menüsü. İkisi de HOVERED kartı hedefler,
    /// seçili kartı değil (bkz. StripModel'in "Kart-başına eylemler" bölümü)
    /// — model.select(...)'i önce çağırıp sonra `…Selected`i kullanmak
    /// kısayol gibi görünür ama ↵'in yapıştıracağı kartı sessizce değiştirir.
    private var hoverControls: some View {
        HStack(spacing: 6) {
            Button {
                try? model.togglePin(id: clip.id)
            } label: {
                Image(systemName: clip.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(clip.pinned ? Theme.accent : Theme.body)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(clip.pinned ? "Sabitlemeyi kaldır (⌃P)" : "Sabitle (⌃P)")

            // Silme burada, çıplak bir çöp kutusu ikonu olarak DEĞİL: 162pt
            // genişlikte iki ikon zaten sıkışık dururdu, ve yıkıcı eylemi bir
            // kademe gömmek bilinçli bir seçim (brief'in gerekçesi).
            Menu {
                Menu("Rafa taşı") {
                    ForEach(model.shelves) { shelf in
                        Button(shelf.name) {
                            try? model.moveToShelf(id: clip.id, shelfID: shelf.id)
                        }
                    }
                    if !model.shelves.isEmpty { Divider() }
                    Button("Yeni raf oluştur…") {
                        newShelfName = ""
                        showingNewShelfPrompt = true
                    }
                }
                Button("Sil", role: .destructive) {
                    try? model.delete(id: clip.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.body)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rafa taşı (⌃S) · Sil (⌘⌫)")
        }
        .padding(4)
        .background(Capsule().fill(Theme.cardFillSelected))
        .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
    }

    /// `try? model.createShelf` yerine hatayı yakalayıp gösteriyor: boş ad
    /// `createShelf`i StoreError ile düşürür (bkz. AppDelegate'teki ⌃S
    /// akışının aynı gerekçesi), sessizce yutmak kullanıcıyı "Oluştur"a
    /// bastığı hâlde hiçbir şey olmamış gibi bırakırdı.
    private func createShelfAndMove() {
        let name = newShelfName
        newShelfName = ""
        do {
            let shelf = try model.createShelf(name: name)
            try model.moveToShelf(id: clip.id, shelfID: shelf.id)
        } catch {
            shelfCreationError = "\(error)"
        }
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
