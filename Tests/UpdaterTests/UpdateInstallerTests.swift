import Foundation
import Security
import Testing
@testable import Updater

private let policy = CodeSignaturePolicy(teamIdentifier: "HN964HX2UA",
                                         bundleIdentifier: "social.selin.stash")

// MARK: - Takas betiği
//
// Betik saf bir fonksiyon olarak üretiliyor çünkü buradaki bir hatanın bedeli
// "kullanıcının uygulaması yok oldu" — gerçek bir uygulamayı silmeden test
// edebilmek şart.

@Test func theHandoffScriptWaitsForTheOldProcessBeforeTouchingTheBundle() {
    let script = updateHandoffScript(
        stagedApp: URL(fileURLWithPath: "/tmp/new/Stash.app"),
        destination: URL(fileURLWithPath: "/Applications/Stash.app"),
        quittingPID: 4242, cleanUp: [])
    let wait = script.range(of: "kill -0 4242")
    let move = script.range(of: "mv '/Applications/Stash.app'")
    #expect(wait != nil)
    #expect(move != nil)
    // Çalışan sürecin bundle'ını değiştirmek onu çökertir; bekleme takastan
    // ÖNCE gelmeli.
    #expect(wait!.lowerBound < move!.lowerBound)
}

@Test func theHandoffScriptMovesTheOldCopyAsideBeforeCopyingTheNewOne() {
    let script = updateHandoffScript(
        stagedApp: URL(fileURLWithPath: "/tmp/new/Stash.app"),
        destination: URL(fileURLWithPath: "/Applications/Stash.app"),
        quittingPID: 1, cleanUp: [])
    let backup = script.range(of: "mv '/Applications/Stash.app' '/Applications/Stash.app.stash-old'")!
    let copy = script.range(of: "ditto '/tmp/new/Stash.app' '/Applications/Stash.app'")!
    let restore = script.range(of: "mv '/Applications/Stash.app.stash-old' '/Applications/Stash.app'")!
    #expect(backup.lowerBound < copy.lowerBound)
    // Kopyalama başarısız olursa geri dönüş yolu var: kullanıcı güncellenmemiş
    // ama çalışan bir Stash ile kalır, hiç Stash olmadan değil.
    #expect(copy.lowerBound < restore.lowerBound)
    #expect(script.contains("open '/Applications/Stash.app'"))
}

@Test func pathsWithSpacesAndQuotesCannotBreakOutOfTheScript() {
    // "Selin's Apps" gibi bir klasör adı, tırnaklama yanlışsa betiği bambaşka
    // bir komuta çevirirdi.
    let script = updateHandoffScript(
        stagedApp: URL(fileURLWithPath: "/tmp/staged dir/Stash.app"),
        destination: URL(fileURLWithPath: "/Users/x/Selin's Apps/Stash.app"),
        quittingPID: 7, cleanUp: [URL(fileURLWithPath: "/tmp/staged dir")])
    #expect(script.contains("'/Users/x/Selin'\\''s Apps/Stash.app'"))
    #expect(script.contains("'/tmp/staged dir/Stash.app'"))
    // Kaçırılmamış çıplak bir kesme işareti kalmamalı.
    #expect(!script.contains("Selin's Apps/Stash.app'"))
}

@Test func theHandoffScriptActuallySwapsTheBundleWhenRun() throws {
    // Betiği okumak yetmez — çalıştırıyoruz. Sıralama ya da tırnaklama
    // yanlışsa buradaki iddia patlar; kullanıcının makinesinde patlarsa
    // uygulaması gider.
    try withTemporaryDirectory { directory in
        let staged = directory.appendingPathComponent("staged")
        let newApp = try makeFakeApp(bundleID: "social.selin.stash", version: "0.2.0", in: staged)
        let destination = directory.appendingPathComponent("Applications/Stash.app")
        try FileManager.default.createDirectory(
            at: destination.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("Contents/marker"))
        try Data("new".utf8).write(to: newApp.appendingPathComponent("Contents/marker"))

        // Çıkmış bir süreç: bekleme döngüsü ilk turda düşmeli.
        let deadPID: Int32 = 999_999
        let script = directory.appendingPathComponent("handoff.sh")
        try updateHandoffScript(stagedApp: newApp, destination: destination,
                                quittingPID: deadPID, cleanUp: [staged])
            .write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.standardError = FileHandle.nullDevice   // `open` sahte bundle'ı açamaz
        try process.run()
        process.waitUntilExit()

        let marker = try String(contentsOf: destination.appendingPathComponent("Contents/marker"),
                                encoding: .utf8)
        #expect(marker == "new")
        // Yedek geride bırakılmaz: kullanıcının Uygulamalar klasöründe
        // "Stash.app.stash-old" diye bir artık kalmamalı.
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".stash-old"))
        // İndirilen geçici kopya da temizlenir.
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }
}

// MARK: - İndirileni doğrulama

private func makeFakeApp(bundleID: String, version: String, in directory: URL) throws -> URL {
    let app = directory.appendingPathComponent("Stash.app")
    try FileManager.default.createDirectory(
        at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleShortVersionString": version,
        "CFBundleExecutable": "Stash",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    FileManager.default.createFile(
        atPath: app.appendingPathComponent("Contents/MacOS/Stash").path,
        contents: Data("#!/bin/sh\n".utf8))
    return app
}

private func zipUp(_ app: URL, in directory: URL) throws -> URL {
    let zip = directory.appendingPathComponent("Stash.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
    try process.run()
    process.waitUntilExit()
    return zip
}

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("updater-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

@Test func anUnsignedBuildIsRejectedNoMatterHowRightItLooks() throws {
    // Güncelleyicinin tek gerçek savunması bu: doğru bundle kimliği, doğru
    // sürüm, doğru dosya adı — ama imza yok. Kabul edilseydi, indirilen her
    // şey çalıştırılırdı.
    try withTemporaryDirectory { directory in
        let app = try makeFakeApp(bundleID: "social.selin.stash", version: "0.2.0", in: directory)
        let zip = try zipUp(app, in: directory)
        let installer = UpdateInstaller(policy: policy)
        #expect(throws: SignatureCheckError.self) {
            try installer.stageVerifiedApp(fromZip: zip, expectedVersion: AppVersion("0.2.0")!)
        }
    }
}

@Test func anotherAppWearingTheStashNameIsRejected() throws {
    try withTemporaryDirectory { directory in
        let app = try makeFakeApp(bundleID: "com.example.other", version: "0.2.0", in: directory)
        let zip = try zipUp(app, in: directory)
        let installer = UpdateInstaller(policy: policy)
        #expect(throws: UpdateInstallError.wrongBundleIdentifier(found: "com.example.other")) {
            try installer.stageVerifiedApp(fromZip: zip, expectedVersion: AppVersion("0.2.0")!)
        }
    }
}

@Test func aBuildThatIsNotTheVersionItPromisedIsRejected() throws {
    // Aynı imzayla imzalanmış ESKİ bir zip'i "0.3.0" diye sunmak (downgrade
    // saldırısı) da bu şarta takılır.
    try withTemporaryDirectory { directory in
        let app = try makeFakeApp(bundleID: "social.selin.stash", version: "0.1.0", in: directory)
        let zip = try zipUp(app, in: directory)
        let installer = UpdateInstaller(policy: policy)
        #expect(throws: UpdateInstallError.versionMismatch(found: "0.1.0", expected: "0.3.0")) {
            try installer.stageVerifiedApp(fromZip: zip, expectedVersion: AppVersion("0.3.0")!)
        }
    }
}

@Test func aRejectedUpdateLeavesNothingBehindOnDisk() throws {
    try withTemporaryDirectory { directory in
        let app = try makeFakeApp(bundleID: "com.example.other", version: "0.2.0", in: directory)
        let zip = try zipUp(app, in: directory)
        let before = try FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("stash-update-") }
        _ = try? UpdateInstaller(policy: policy)
            .stageVerifiedApp(fromZip: zip, expectedVersion: AppVersion("0.2.0")!)
        let after = try FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("stash-update-") }
        #expect(after.count == before.count)
    }
}

@Test func preflightRefusesBeforeQuittingWhenTheAppCannotBeReplaced() throws {
    // Bu kontrol uygulamayı kapatmadan ÖNCE çalışıyor: yoksa Stash kapanır,
    // takas başarısız olur ve geriye çalıştırılacak hiçbir şey kalmazdı.
    try withTemporaryDirectory { directory in
        let readOnly = directory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        let app = try makeFakeApp(bundleID: "social.selin.stash", version: "0.2.0", in: readOnly)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                       ofItemAtPath: readOnly.path) }
        #expect(throws: UpdateInstallError.destinationNotWritable(path: readOnly.path)) {
            try UpdateInstaller(policy: policy).preflight(destination: app)
        }
    }
}

@Test func theSignatureRequirementIsSomethingSecurityActuallyUnderstands() {
    // Şart metnindeki bir yazım hatası her güncellemeyi reddederdi — üstelik
    // "imza doğrulanamadı" diye, yani hatanın bizde olduğu hiç anlaşılmazdı.
    var requirement: SecRequirement?
    let status = SecRequirementCreateWithString(policy.requirementText as CFString, [], &requirement)
    #expect(status == errSecSuccess)
    #expect(policy.requirementText.contains("anchor apple generic"))
    #expect(policy.requirementText.contains("HN964HX2UA"))
    #expect(policy.requirementText.contains("identifier \"social.selin.stash\""))
}
