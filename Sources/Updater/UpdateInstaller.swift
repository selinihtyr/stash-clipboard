import Foundation

public enum UpdateInstallError: Error, Equatable {
    case extractionFailed(status: Int32)
    case noAppInArchive
    case wrongBundleIdentifier(found: String?)
    /// İnen bundle, sürüm notlarında vaat edilen sürüm değil. Aynı imzayla
    /// imzalanmış ESKİ bir zip'i tekrar sunmak (downgrade) da bu şarta takılır.
    case versionMismatch(found: String?, expected: String)
    /// Uygulama yazılamayan bir yerde duruyor (başka bir kullanıcının
    /// klasörü, salt okunur birim). Kullanıcıyı uygulamadan ETMEDEN önce
    /// bakıyoruz: yoksa Stash kapanır, takas başarısız olur ve geriye
    /// çalıştırılacak hiçbir şey kalmazdı.
    case destinationNotWritable(path: String)
}

/// İndirilen zip'i açıp doğrulayan ve yerine koyan parça.
///
/// "Doğrula, sonra kur" sırası pazarlık konusu değil: imza kontrolü
/// karantina bayrağı kaldırılmadan ÖNCE yapılıyor. Tersi olsaydı,
/// doğrulanmamış bir bundle bir an için Gatekeeper'sız çalıştırılabilir
/// halde diskte dururdu.
public struct UpdateInstaller {
    public let policy: CodeSignaturePolicy
    public let fileManager: FileManager

    public init(policy: CodeSignaturePolicy, fileManager: FileManager = .default) {
        self.policy = policy
        self.fileManager = fileManager
    }

    /// Zip'i geçici bir dizine açar, içindeki `.app`i doğrular ve yolunu döner.
    /// Doğrulama geçmezse açılan her şey silinir — reddedilen bir bundle diskte
    /// bırakılmaz.
    public func stageVerifiedApp(fromZip zip: URL, expectedVersion: AppVersion) throws -> URL {
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("stash-update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        do {
            // `ditto -x -k`: macOS'un kendi zip açıcısı. `unzip`in aksine
            // genişletilmiş öznitelikleri ve imza mühürlerini koruyor —
            // `unzip` ile açılan bir bundle'ın imzası bozuk görünürdü.
            let status = try run("/usr/bin/ditto",
                                 ["-x", "-k", zip.path, workDirectory.path])
            guard status == 0 else { throw UpdateInstallError.extractionFailed(status: status) }

            let contents = try fileManager.contentsOfDirectory(
                at: workDirectory, includingPropertiesForKeys: nil)
            guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateInstallError.noAppInArchive
            }

            let info = try? PropertyListSerialization.propertyList(
                from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                format: nil) as? [String: Any]
            let foundBundleID = info?["CFBundleIdentifier"] as? String
            guard foundBundleID == policy.bundleIdentifier else {
                throw UpdateInstallError.wrongBundleIdentifier(found: foundBundleID)
            }
            let foundVersion = info?["CFBundleShortVersionString"] as? String
            guard let foundVersion, AppVersion(foundVersion) == expectedVersion else {
                throw UpdateInstallError.versionMismatch(
                    found: foundVersion, expected: expectedVersion.description)
            }

            try verifyCodeSignature(ofBundleAt: app, policy: policy)
            // Karantina ancak imza doğrulandıktan SONRA kalkıyor. İndirilen
            // dosyaya macOS'un koyduğu bayrak bu; kaldırmasak kullanıcı her
            // güncellemeden sonra "sağ tık → Aç" yapmak zorunda kalırdı —
            // yani otomatik güncelleme diye bir şey olmazdı.
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
            return app
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    /// Takasın yapılabileceğini uygulamayı kapatmadan ÖNCE doğrular.
    public func preflight(destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path),
              fileManager.isWritableFile(atPath: destination.path)
        else { throw UpdateInstallError.destinationNotWritable(path: parent.path) }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Takası yapan kabuk betiği.
///
/// Neden ayrı bir süreç: çalışan uygulama kendi bundle'ını değiştiremez. macOS
/// binary'yi tembel sayfalıyor, dosya altından çekildiğinde ihtiyaç duyduğu bir
/// sonraki sayfa yok oluyor ve süreç bus error alıyor (aynı sebep
/// `scripts/bundle.sh`de de yazılı). Bu yüzden takası, Stash çıktıktan SONRA
/// çalışan bağımsız bir betik yapıyor.
///
/// Saf bir fonksiyon olması kasıtlı: üretilen betik, gerçekten bir uygulamayı
/// silmeden test edilebiliyor — tırnaklama ve sıralama hatalarının bedeli
/// burada "kullanıcının uygulaması yok oldu" olurdu.
public func updateHandoffScript(
    stagedApp: URL, destination: URL, quittingPID: Int32, cleanUp: [URL]
) -> String {
    // Tek tırnak içinde tek tırnağı kaçırmanın POSIX yolu: '\'' — boşluk ya da
    // tırnak içeren yollar (kullanıcı uygulamayı "Selin's Apps"e koymuş olabilir)
    // aksi halde betiği bambaşka bir şeye çevirirdi.
    func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let source = quote(stagedApp.path)
    let target = quote(destination.path)
    let backup = quote(destination.path + ".stash-old")
    let cleanUpPaths = cleanUp.map { quote($0.path) }.joined(separator: " ")

    return """
    #!/bin/sh
    # Stash güncelleme takası — Stash tarafından üretildi, elle çalıştırılmaz.
    set -u

    # Eski süreç gerçekten ölene kadar bekle: hâlâ çalışırken bundle'ı
    # değiştirmek onu çökertir. 10 saniye sonra yine de devam ediyoruz —
    # takılmış bir süreç yüzünden güncelleme sonsuza kadar askıda kalmasın.
    i=0
    while kill -0 \(quittingPID) 2>/dev/null && [ $i -lt 100 ]; do
        sleep 0.1
        i=$((i + 1))
    done

    rm -rf \(backup)
    # Önce eskisini kenara AL, sonra yenisini koy. Doğrudan üzerine yazmak,
    # yarıda kalan bir kopyada kullanıcıyı hiçbir uygulaması olmadan bırakırdı.
    if ! mv \(target) \(backup); then
        exit 1
    fi
    if ditto \(source) \(target); then
        rm -rf \(backup)
    else
        # Kopyalama başarısız: eskisini geri koy. Kullanıcı güncellenmemiş ama
        # ÇALIŞAN bir Stash ile kalır.
        rm -rf \(target)
        mv \(backup) \(target)
    fi

    open \(target)
    rm -rf \(cleanUpPaths)
    """
}
