import Foundation
import ServiceManagement

/// SMAppService kullanıyoruz: macOS 13'ten beri doğru yol bu ve kullanıcı
/// öğeyi Sistem Ayarları > Giriş Öğeleri'nde görüp kapatabiliyor.
///
/// `isEnabled` her seferinde `SMAppService.mainApp.status`'u okur — kendi
/// tuttuğumuz bir bayrak değil. Kayıt durumu zaten macOS tarafından kalıcı
/// tutuluyor; onu `Settings`'te ikinci kez saklamak iki doğruluk kaynağı
/// yaratırdı (bkz. Task 15 raporu).
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
