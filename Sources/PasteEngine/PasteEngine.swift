import Filters
import Foundation

public enum PasteOutcome: Equatable {
    case pastedIntoFrontmostApp
    case copiedOnlyNoAccessibilityPermission
    /// Permission was present but the synthetic ⌘V itself could not be
    /// posted (event construction failed). The content is safely on the
    /// pasteboard; the user still needs to press ⌘V themselves.
    case copiedOnlyKeystrokeFailed
}

/// Pano yazımıyla sentetik ⌘V arasında çağrılan kanca. `PasteEngine`, `deliver()`i
/// YALNIZCA bu fonksiyonun kendisine verdiği `proceed` çağrılınca tetikler — bu
/// kancayı atlayıp doğrudan bir `PasteOutcome` alacak başka bir yol yok.
///
/// Bu, orijinal hatanın ta kendisini API düzeyinde imkansız kılmak için böyle:
/// eskiden `paste(...)` yazma ve teslimatı tek bir senkron çağrıda yapıyordu,
/// çağıran taraf (AppDelegate) da paneli teslimattan SONRA kapatıyordu — tuş
/// hâlâ key window olan panelimize düşüyordu. "Yaz" ve "teslim et"i iki ayrı
/// public metoda ayırmak aynı hatayı bir sonraki çağırana açık bırakırdı
/// (sırayı doğru tutmak çağıranın disiplinine kalırdı). Bunun yerine `paste`
/// tek bir public giriş noktası kalıyor ve odağı geri vermek zorunlu, ara bir
/// adım oluyor — sıra, tipin kendisi tarafından zorlanıyor.
///
/// Gerçek hayattaki bir uygulama (bkz. AppDelegate) genelde asenkrondur:
/// paneli kapatıp `proceed`i bir sonraki run loop turuna erteler, çünkü odak
/// geri verme (pencere sunucusunun key window'u devretmesi) anlık değildir.
/// Buna ihtiyacı olmayan çağıranlar (testler, UI'siz yapıştır-ve-bastır
/// koşumları) `{ proceed in proceed() }` geçer — bu seçim her çağrı yerinde
/// AÇIKÇA görünür, bir varsayılan parametrenin arkasına gizlenmez.
public typealias FocusRestoration = (_ proceed: @escaping () -> Void) -> Void

public final class PasteEngine {
    private let pasteboard: PasteWriting
    private let keystrokes: KeystrokeSending

    /// Her başarılı pano yazımından hemen sonra, o yazımın ürettiği
    /// `changeCount` ile çağrılır. `PasteEngine` panoyu yoklayan tarafı
    /// (ayrı bir modülde yaşayan `ClipCapture`) hiç bilmiyor ve bilmemeli —
    /// bu kancayı kimin dinlediği tamamen çağırana kalmış (bkz.
    /// `AppDelegate`, iki modülü birbirine bağlayan tek yer). Boş bırakılırsa
    /// hiçbir şey değişmez, sadece kendi yazdığımız değişiklik normal bir
    /// kullanıcı kopyalaması gibi geri yakalanabilir hale gelir (I2).
    ///
    /// Sıra hâlâ garanti: bu her zaman yazımdan hemen sonra, `restoreFocus`
    /// çağrılmadan ÖNCE tetiklenir — `suppressChangeCount` bu changeCount'u
    /// panel kapanmadan, dolayısıyla kullanıcının panelin arkasında yeni bir
    /// şey kopyalayabileceği pencere açılmadan önce işaretlemiş olur.
    public var onWrite: ((Int) -> Void)?

    public init(pasteboard: PasteWriting, keystrokes: KeystrokeSending) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    public func paste(text: String, filters: [PasteFilter],
                      restoreFocus: @escaping FocusRestoration,
                      completion: @escaping (PasteOutcome) -> Void) {
        let changeCount = pasteboard.writeText(apply(filters, to: text),
                                               plainOnly: filters.contains(.plainText))
        onWrite?(changeCount)
        restoreFocus { [self] in completion(deliver()) }
    }

    /// `fileURL` görselin diskteki gerçek konumu — çağıran (`StripModel`)
    /// zaten `Clip.imagePath`ten okuduğu için burada zorunlu parametre;
    /// `PasteEngine` `Store`u hiç bilmiyor, bu yüzden yolu kendi başına
    /// türetemez, çağırandan almak zorunda (bkz. `PasteWriting.writeImage`).
    public func paste(imageData: Data, fileURL: URL,
                      restoreFocus: @escaping FocusRestoration,
                      completion: @escaping (PasteOutcome) -> Void) {
        let changeCount = pasteboard.writeImage(imageData, fileURL: fileURL)
        onWrite?(changeCount)
        restoreFocus { [self] in completion(deliver()) }
    }

    /// İzin kontrolü burada, `deliver()`in her çağrılışında taze okunuyor —
    /// `restoreFocus` yüzünden yazımdan bir run loop turu sonra çalışsa bile,
    /// bir önceki paste'ten kalma önbelleklenmiş bir değer değil, o anki
    /// `AXIsProcessTrusted()` sonucu kullanılıyor.
    private func deliver() -> PasteOutcome {
        guard keystrokes.isTrusted else { return .copiedOnlyNoAccessibilityPermission }
        return keystrokes.sendCommandV() ? .pastedIntoFrontmostApp : .copiedOnlyKeystrokeFailed
    }
}
