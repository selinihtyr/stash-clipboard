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

    private var currentScope: ClipStore.ClipScope {
        switch tab {
        case .all: return .all
        case .pinned: return .pinned
        case .images: return .kind(.image)
        case .shelf(let id): return .shelf(id)
        }
    }

    // Süzgeç artık SQL'de: 300'lük sayfa limiti her sekmenin KENDİ sonuç
    // kümesine uygulanıyor, "300 en yeni satırı çek, sonra bellekte sekmeye
    // göre süz" değil — aksi halde sabitlenmiş/rafa konmuş/görsel bir klip
    // 300 satırdan eskiyince ilgili sekmede hiç görünmezdi (C2), arama ise
    // ayrı bir yoldan geçtiği için bunu hiç fark ettirmezdi.
    private func fetchVisible() throws -> [Clip] {
        try store.clips(in: currentScope, matching: query.isEmpty ? nil : query, limit: Self.pageSize)
    }

    public func reload() throws {
        // Raflar önce tazelenir: tab silinmiş bir rafı gösteriyorsa
        // reloadShelves onu .all'a düşürür, filtre bunu geçerli tab ile
        // hesaplar. Sırayı tersine çevirirsek bir kart görmeden boş bir
        // şeride ve sekme çubuğunda hiçbir şeyin seçili görünmediği bir
        // ara duruma düşülür.
        try reloadShelves()
        visible = try fetchVisible()
        // Liste değiştiğinde eski indekste kalmak yanlış kartı yapıştırır.
        selectedIndex = 0
    }

    /// Fare imleci hangi karttaysa tetiklenen sabitle/rafa-taşı/sil (bkz.
    /// ClipCardView'daki ⌃P/⋯ kontrolleri) hovered kart üzerinde çalışır,
    /// bu kart seçili olan kart olmak ZORUNDA DEĞİL. `reload()` gibi
    /// selectedIndex'i sıfırlamak burada yanlış olurdu: kullanıcı üçüncü
    /// kartın üstündeyken onu silip seçili birinci kart hâlâ görünürken
    /// seçim sessizce başka bir kartı işaret ederse, ↵'in ne yapıştıracağı
    /// kullanıcının beklemediği bir kart olur. Bunun yerine mutasyondan önce
    /// seçili klibin kimliği saklanır; yeni listede hâlâ oradaysa (silinen/
    /// taşınan/sabitlenen başka bir klipti) seçim ona yapışık kalır, yoksa
    /// (kendisi silindi/listeden düştü) en yakın geçerli indekse düşülür.
    private func refreshPreservingSelection() throws {
        let anchorID = visible.indices.contains(selectedIndex) ? visible[selectedIndex].id : nil
        try reloadShelves()
        visible = try fetchVisible()
        if let anchorID, let idx = visible.firstIndex(where: { $0.id == anchorID }) {
            selectedIndex = idx
        } else {
            selectedIndex = min(selectedIndex, max(visible.count - 1, 0))
        }
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

    /// `restoreFocus`u doğrudan `engine.paste`e aktarır, hiç dokunmadan —
    /// bu, panelin ne zaman/nasıl kapandığını bilen tek katmanın (AppDelegate)
    /// hâlâ o kancayı sağladığı, `StripModel`in (ya da `PasteEngine`in) bir
    /// `NSPanel` bilmesi gerekmediği anlamına geliyor.
    ///
    /// Dönüş değeri artık `PasteOutcome?` değil `Bool`: içerik gerçekten
    /// var mıydı (yapıştırma denendi mi) sorusunu senkron cevaplıyor,
    /// sonucun kendisi (izin/tuş başarısı) `completion`a asenkron geliyor —
    /// engine artık odak geri verilene kadar sonucu bilmiyor.
    @discardableResult
    public func pasteSelected(applyingFilters: Bool,
                              restoreFocus: @escaping FocusRestoration,
                              completion: @escaping (PasteOutcome) -> Void) -> Bool {
        guard visible.indices.contains(selectedIndex) else { return false }
        let clip = visible[selectedIndex]
        let filters = applyingFilters ? settings.activeFilters : []
        if clip.kind == .image, let path = clip.imagePath,
           let data = FileManager.default.contents(atPath: path) {
            engine.paste(imageData: data, fileURL: URL(fileURLWithPath: path),
                        restoreFocus: restoreFocus, completion: completion)
            return true
        }
        guard let text = clip.text else { return false }
        engine.paste(text: text, filters: filters, restoreFocus: restoreFocus, completion: completion)
        return true
    }

    /// `pasteSelected` iki farklı "hiçbir şey olmadı" durumunu aynı `false`
    /// ile döndürüyor: hiçbir kart seçili değilken (boş şerit — başlık
    /// zaten sebebini söylüyor, sessiz kalmak doğru) ve seçili bir kart
    /// görünürken ama yapıştıracak içeriği kalmamışken (I3: budanmış bir
    /// görsel — kart "görsel artık saklanmıyor" diyor ama ↵'e basmak hâlâ
    /// hiçbir şey yapmıyordu, hiçbir geri bildirim yok). Çağıran taraf
    /// (`AppDelegate`) bu ikisini ayırt edip yalnızca ikincisinde görünür
    /// bir uyarı göstermeli — bu yüzden karar burada, `pasteSelected`in
    /// imzasını (ve onu zaten test eden `StripModelTests`i) bozmadan ayrı
    /// bir yüzeyde.
    public enum PasteAttempt: Equatable {
        case nothingSelected
        case nothingToPaste
        case outcome(PasteOutcome)
    }

    /// Sonuç artık senkron dönmüyor: `.nothingSelected`/`.nothingToPaste`
    /// (engine hiç devreye girmeden bilinen durumlar) `completion`a hemen
    /// gelir, `.outcome` ise `restoreFocus` `proceed`i çağırana kadar
    /// gecikebilir — bkz. `PasteEngine.FocusRestoration`.
    public func attemptPaste(applyingFilters: Bool,
                             restoreFocus: @escaping FocusRestoration,
                             completion: @escaping (PasteAttempt) -> Void) {
        guard visible.indices.contains(selectedIndex) else { completion(.nothingSelected); return }
        let attempted = pasteSelected(applyingFilters: applyingFilters, restoreFocus: restoreFocus) { outcome in
            completion(.outcome(outcome))
        }
        if !attempted { completion(.nothingToPaste) }
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

    // MARK: - Kart-başına eylemler (fare/hover yolu)
    //
    // Yukarıdaki üç `…Selected` metodu klavye yolunu (⌃P/⌃S/⌘⌫, hep seçili
    // kart üzerinde) besliyor ve olduğu gibi kalıyor. Aşağıdakiler
    // ClipCardView'un hover kontrolleri için: aynı üç işlem, ama parametre
    // olarak verilen KİMLİĞİN kartı üzerinde — o kart seçili olmayabilir.
    // Seçimi önce o karta taşıyıp sonra `…Selected`i çağırmak kısayol gibi
    // görünür ama değildir: bu, ↵'in yapıştıracağı kartı kullanıcı fark
    // etmeden değiştirir (bkz. refreshPreservingSelection üstündeki not).

    public func togglePin(id: UUID) throws {
        guard let clip = visible.first(where: { $0.id == id }) else { return }
        try store.setPinned(!clip.pinned, id: clip.id)
        try refreshPreservingSelection()
    }

    public func moveToShelf(id: UUID, shelfID: UUID?) throws {
        guard visible.contains(where: { $0.id == id }) else { return }
        try store.setShelf(shelfID, id: id)
        try refreshPreservingSelection()
    }

    public func delete(id: UUID) throws {
        guard visible.contains(where: { $0.id == id }) else { return }
        try store.delete(id: id)
        try refreshPreservingSelection()
    }
}
