import Combine
import Filters
import Foundation
import PasteEngine
import Store

public enum StripTab: Hashable, Sendable {
    case all, pinned, images
    case shelf(UUID)
}

@MainActor
public final class StripModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var tab: StripTab = .all
    @Published public private(set) var visible: [Clip] = []
    @Published public private(set) var selectedIndex: Int = 0
    /// Kullanıcının oluşturduğu raflar; sekme çubuğu ve ⌃S menüsü bundan
    /// besleniyor. Tümü/Sabitlenen/Görseller burada YOK — onlar raf değil,
    /// mevcut alanlar üzerindeki süzgeçler (bkz. StripTab).
    @Published public private(set) var shelves: [Shelf] = []
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
        // Raflar önce tazelenir: tab silinmiş bir rafı gösteriyorsa
        // reloadShelves onu .all'a düşürür, filtre bunu geçerli tab ile
        // hesaplar. Sırayı tersine çevirirsek bir kart görmeden boş bir
        // şeride ve sekme çubuğunda hiçbir şeyin seçili görünmediği bir
        // ara duruma düşülür.
        try reloadShelves()
        // Süzgeç artık SQL'de: 300'lük sayfa limiti her sekmenin KENDİ
        // sonuç kümesine uygulanıyor, "300 en yeni satırı çek, sonra
        // bellekte sekmeye göre süz" değil — aksi halde sabitlenmiş/rafa
        // konmuş/görsel bir klip 300 satırdan eskiyince ilgili sekmede hiç
        // görünmezdi (C2), arama ise ayrı bir yoldan geçtiği için bunu hiç
        // fark ettirmezdi.
        let scope: ClipStore.ClipScope
        switch tab {
        case .all: scope = .all
        case .pinned: scope = .pinned
        case .images: scope = .kind(.image)
        case .shelf(let id): scope = .shelf(id)
        }
        visible = try store.clips(in: scope, matching: query.isEmpty ? nil : query, limit: Self.pageSize)
        // Liste değiştiğinde eski indekste kalmak yanlış kartı yapıştırır.
        selectedIndex = 0
    }

    /// Rafları tazeler ve aktif tab artık var olmayan bir rafa işaret
    /// ediyorsa .all'a düşürür. Burada durmasının sebebi: bu, reload() dahil
    /// rafları değiştirebilecek HER yolun geçtiği tek nokta (reload, ⌃S'teki
    /// createShelf) — tab düzeltmesini tek bir çağrı yerine buraya koymak,
    /// bir sonraki raf-değiştiren kod yolunun bunu unutmasını imkansız kılar.
    public func reloadShelves() throws {
        shelves = try store.shelves()
        if case .shelf(let id) = tab, !shelves.contains(where: { $0.id == id }) {
            tab = .all
        }
    }

    /// Şerit penceresi doğrudan ClipStore'a erişmiyor; ⌃S menüsü "önce raf
    /// yoksa oluştur" akışını burada tetikler ki store bağımlılığı model
    /// katmanında kalsın.
    public func createShelf(name: String) throws -> Shelf {
        let shelf = try store.createShelf(name: name)
        try reloadShelves()
        return shelf
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
