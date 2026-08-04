import AppKit
import Carbon.HIToolbox
import Foundation

public struct KeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command = UInt32(cmdKey)
    public static let option = UInt32(optionKey)
    public static let control = UInt32(controlKey)
    public static let shift = UInt32(shiftKey)
    public static let keyCodeV = UInt32(kVK_ANSI_V)

    /// ⌘⇧V değil: global kısayol olarak kaydedilirse her uygulamadaki
    /// "biçimlendirmeyi eşleyerek yapıştır"ı gölgeler.
    public static let defaultCombo = KeyCombo(keyCode: keyCodeV,
                                              modifiers: option | command)

    public var displayString: String {
        var out = ""
        if modifiers & Self.control != 0 { out += "⌃" }
        if modifiers & Self.option != 0 { out += "⌥" }
        if modifiers & Self.shift != 0 { out += "⇧" }
        if modifiers & Self.command != 0 { out += "⌘" }
        out += Self.characterName(for: keyCode)
        return out
    }

    static func characterName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_C: return "C"
        case kVK_Space: return "Space"
        default: return "#\(keyCode)"
        }
    }

    /// Carbon değiştiricileri (bu `modifiers` alanının biçimi, çünkü Carbon
    /// global kısayol kaydı için gerekiyor) AppKit'in `NSEvent.ModifierFlags`
    /// ailesine çevirir. Menü öğesi kısayolları (`NSMenuItem.keyEquivalentModifierMask`)
    /// AppKit tarafında yaşıyor; ikisi arasında ortak bir tip yok.
    public var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & Self.control != 0 { flags.insert(.control) }
        if modifiers & Self.option != 0 { flags.insert(.option) }
        if modifiers & Self.shift != 0 { flags.insert(.shift) }
        if modifiers & Self.command != 0 { flags.insert(.command) }
        return flags
    }

    /// `NSMenuItem.keyEquivalent` için küçük harfli, tek karakterlik temsil.
    /// Yalnızca `characterName(for:)`in gerçek bir harf/rakam bildiği kodlar
    /// için dolu döner (`displayString`teki "#42" gibi numara yedeklemeleri
    /// hariç) — menüde "⌥⌘#42" gibi anlamsız bir kısayol göstermektense hiç
    /// göstermemek, kullanıcıyı yanlış bir tuşa yönlendirmekten daha dürüst.
    public var keyEquivalent: String? {
        switch Int(keyCode) {
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_C: return "c"
        case kVK_Space: return " "
        default: return nil
        }
    }
}
