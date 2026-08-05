import Foundation
import Security

/// İndirilen bir bundle'ın kabul edilme şartı.
///
/// Bu, güncelleyicinin tamamındaki en önemli parça: indirilen şeyi çalıştırmak,
/// makinede kod çalıştırma yetkisi vermek demek. HTTPS yalnızca "GitHub'dan
/// geldi"yi söyler; imza "Stash'i imzalayan kimlik imzaladı"yı söyler. İkincisi
/// olmadan, GitHub hesabına erişen ya da aradaki her kim olursa, bir sonraki
/// güncellemeyle istediği kodu gönderebilirdi.
///
/// Ekip kimliği KAYNAKTA sabit yazılı: çalışan kopyanın imzasından okunsaydı,
/// kaynaktan ad-hoc derleyen (imzasında ekip kimliği olmayan) herkes hiçbir
/// şeye karşı doğrulama yapamazdı — yani doğrulama tam da en çok gereken yerde
/// kapanırdı. Sabit olduğu için de denetlenebilir: depo herkese açık, bu satır
/// beklenen imzacıyı açıkça söylüyor.
public struct CodeSignaturePolicy: Sendable, Equatable {
    public let teamIdentifier: String
    public let bundleIdentifier: String

    public init(teamIdentifier: String, bundleIdentifier: String) {
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
    }

    /// `anchor apple generic`: sertifika zinciri Apple'a çıkmalı — kendi
    /// ürettiği bir sertifikayla imzalanmış bir bundle bu şartı geçemez.
    /// `certificate leaf[subject.OU]`: imzalayan ekip. `identifier`: bundle
    /// kimliği, yani "Stash yerine başka bir uygulama" gelmesini de eler.
    public var requirementText: String {
        "identifier \"\(bundleIdentifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

public enum SignatureCheckError: Error, Equatable {
    case unreadableCode(OSStatus)
    case invalidRequirement(OSStatus)
    /// İmza yok, bozuk ya da beklenen kimliğe ait değil. Ayrımı OSStatus
    /// taşıyor; kullanıcıya gösterilen metin ikisini de "bu güncelleme
    /// doğrulanamadı" diye özetliyor — doğru teşhis kullanıcıda değil,
    /// bizde işe yarıyor.
    case rejected(OSStatus)
}

/// `codesign` çıktısını metin olarak ayrıştırmak yerine Security çerçevesini
/// çağırıyoruz: çıktı biçimi macOS sürümleri arasında değişebilir, bir
/// ayrıştırma hatası da sessizce "doğrulandı" demeye dönüşebilirdi.
public func verifyCodeSignature(ofBundleAt url: URL, policy: CodeSignaturePolicy) throws {
    var staticCode: SecStaticCode?
    let codeStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard codeStatus == errSecSuccess, let staticCode else {
        throw SignatureCheckError.unreadableCode(codeStatus)
    }

    var requirement: SecRequirement?
    let requirementStatus = SecRequirementCreateWithString(
        policy.requirementText as CFString, [], &requirement)
    guard requirementStatus == errSecSuccess, let requirement else {
        throw SignatureCheckError.invalidRequirement(requirementStatus)
    }

    // `kSecCSCheckAllArchitectures` + `kSecCSCheckNestedCode`: bundle'ın
    // yalnızca ana binary'si değil, içindeki her şey mühürle uyuşmalı —
    // aksi halde imzalı bir kabuğun içine imzasız bir yardımcı sıkıştırmak
    // doğrulamayı geçerdi.
    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
    let validity = SecStaticCodeCheckValidity(staticCode, flags, requirement)
    guard validity == errSecSuccess else {
        throw SignatureCheckError.rejected(validity)
    }
}
