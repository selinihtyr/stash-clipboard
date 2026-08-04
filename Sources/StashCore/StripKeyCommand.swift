import AppKit

public enum StripKeyCommand: Equatable, Sendable {
    case moveLeft, moveRight
    case paste(filtered: Bool)
    case pasteIndex(Int)
    case togglePin, delete, nextTab, dismiss, moveToShelf
    case type(Character)
    case backspace
}

/// Tuş eşlemesi saf bir fonksiyon: NSEvent üretmeden test edilebiliyor.
///
/// Delete tuşu (keyCode 51) arama kutusuyla kart silme arasında paylaşılıyor.
/// Arama açıkken Delete harf silmeli — aksi halde kullanıcı yazarken kartını
/// kaybeder. Kart silme bu yüzden ⌘⌫'e taşındı; Delete tek başına her zaman
/// arama metnini düzenler.
public func stripCommand(keyCode: UInt16, characters: String?,
                         modifiers: NSEvent.ModifierFlags) -> StripKeyCommand? {
    let mods = modifiers.intersection([.command, .option, .control, .shift])
    // ⌘⌫ önce kontrol ediliyor: aşağıdaki switch'teki `case 51` kendi içinde
    // return ettiği için (fall-through yok), ona ulaşmadan önce yakalanmalı.
    if mods == [.command], keyCode == 51 { return .delete }
    switch keyCode {
    case 123: return .moveLeft
    case 124: return .moveRight
    case 53: return .dismiss
    case 48: return .nextTab                       // Tab
    case 51: return mods.isEmpty ? .backspace : nil // Delete
    case 36: return .paste(filtered: mods.contains(.option))
    default: break
    }
    if mods == [.control], characters?.lowercased() == "p" { return .togglePin }
    if mods == [.control], characters?.lowercased() == "s" { return .moveToShelf }
    if mods == [.command], let digit = characters.flatMap({ Int($0) }), (1...9).contains(digit) {
        return .pasteIndex(digit - 1)
    }
    // Değiştiricisiz karakterler arama alanına gider; ⌘/⌃/⌥ ile basılanlar
    // komut olabilir, onları metin sanmak yanlış olur.
    if mods.isEmpty || mods == [.shift], let char = characters?.first, isTypable(char) {
        return .type(char)
    }
    return nil
}

/// Bir tuşun arama metnine girmeye hakkı var mı.
///
/// Eşlenmemiş her tuşun `.type`'a düşmesi tek başına yeterli değildi: AppKit,
/// ok ve fonksiyon tuşlarını Unicode özel kullanım alanındaki (U+F700…U+F8FF)
/// karakterlerle bildirir. Yukarı/aşağı ok tuşları bu yüzden arama kutusuna
/// görünmeyen çöp yazıyordu — kullanıcının gördüğü şey kutu içinde soru
/// işaretiydi. Buradaki kural eşlemeyi tamamlamaktan daha dayanıklı: yeni bir
/// tuş eşlenmeyi unutsa bile metne dönüşemez.
func isTypable(_ char: Character) -> Bool {
    for scalar in char.unicodeScalars {
        if (0xF700...0xF8FF).contains(scalar.value) { return false }  // fonksiyon tuşları
        if scalar.properties.generalCategory == .control { return false }
    }
    return !char.isNewline
}
