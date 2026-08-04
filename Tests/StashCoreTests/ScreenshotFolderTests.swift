import Testing
import Foundation
@testable import StashCore

// `com.apple.screencapture` GERÇEK domain'ine asla dokunmuyoruz (o, sahibinin
// gerçek ⌘⇧4 hedefini kontrol ediyor) — her test kendi rastgele adlı süitini
// kurup temizliyor.

private func makeSuite() -> (UserDefaults, String) {
    let name = "stash-screenshot-folder-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, name)
}

@Test func unsetLocationFallsBackToDesktop() {
    let (defaults, name) = makeSuite()
    defer { UserDefaults().removePersistentDomain(forName: name) }
    let home = URL(fileURLWithPath: "/Users/test-user")

    let resolved = ScreenshotFolder.resolve(defaults: defaults, home: home)

    #expect(resolved == home.appendingPathComponent("Desktop"))
}

@Test func emptyStringLocationAlsoFallsBackToDesktop() {
    // Elle silinmiş bir tercih boş dizeye düşebilir; bunu "ayarlanmamış"
    // gibi ele alıyoruz, boş bir yola düşmüyoruz.
    let (defaults, name) = makeSuite()
    defer { UserDefaults().removePersistentDomain(forName: name) }
    defaults.set("", forKey: "location")
    let home = URL(fileURLWithPath: "/Users/test-user")

    let resolved = ScreenshotFolder.resolve(defaults: defaults, home: home)

    #expect(resolved == home.appendingPathComponent("Desktop"))
}

@Test func explicitAbsoluteLocationOverridesDesktop() {
    let (defaults, name) = makeSuite()
    defer { UserDefaults().removePersistentDomain(forName: name) }
    defaults.set("/Users/test-user/Shots", forKey: "location")
    let home = URL(fileURLWithPath: "/Users/test-user")

    let resolved = ScreenshotFolder.resolve(defaults: defaults, home: home)

    #expect(resolved == URL(fileURLWithPath: "/Users/test-user/Shots"))
}

@Test func tildeInLocationIsExpanded() {
    // `defaults write` Terminal'den elle girilirse tilde'li bir yol
    // yazılabilir; `screencapture`ın kendisi bunu genişletiyor, biz de
    // aynısını yapmalıyız yoksa "~/Shots" harfi harfine bir dizin adı olarak
    // yorumlanır.
    let (defaults, name) = makeSuite()
    defer { UserDefaults().removePersistentDomain(forName: name) }
    defaults.set("~/Shots", forKey: "location")
    let home = URL(fileURLWithPath: NSHomeDirectory())

    let resolved = ScreenshotFolder.resolve(defaults: defaults, home: home)

    #expect(resolved == home.appendingPathComponent("Shots"))
}
