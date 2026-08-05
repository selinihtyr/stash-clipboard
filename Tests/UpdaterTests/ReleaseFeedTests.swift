import Foundation
import Testing
@testable import Updater

private func json(tag: String = "v0.2.0", body: String = "Fixes the shortcut.",
                  assetName: String = "Stash.zip", draft: Bool = false,
                  prerelease: Bool = false) -> Data {
    """
    {
      "tag_name": "\(tag)",
      "draft": \(draft),
      "prerelease": \(prerelease),
      "body": "\(body)",
      "html_url": "https://github.com/selinihtyr/stash-clipboard/releases/tag/\(tag)",
      "assets": [
        {"name": "\(assetName)", "size": 2400000,
         "browser_download_url": "https://github.com/selinihtyr/stash-clipboard/releases/download/\(tag)/\(assetName)"}
      ]
    }
    """.data(using: .utf8)!
}

@Test func aPublishedReleaseIsParsedIntoSomethingInstallable() throws {
    let release = try parseLatestRelease(json(), assetName: "Stash.zip")
    #expect(release.version == AppVersion("0.2.0"))
    #expect(release.tag == "v0.2.0")
    #expect(release.notes == "Fixes the shortcut.")
    #expect(release.downloadURL.absoluteString.hasSuffix("/Stash.zip"))
    #expect(release.downloadSize == 2_400_000)
}

@Test func aReleaseWithoutTheBuildIsRejected() {
    // Yarım yayınlanmış bir sürümü "güncelleme var" diye göstermek, tıklayınca
    // hiçbir şey olmamasıyla biterdi.
    #expect(throws: ReleaseFeedError.missingAsset(tag: "v0.2.0", expected: "Stash.zip")) {
        try parseLatestRelease(json(assetName: "Stash-source.tar.gz"), assetName: "Stash.zip")
    }
}

@Test func draftsAndPrereleasesAreNeverOffered() {
    #expect(throws: ReleaseFeedError.notAStableRelease(tag: "v0.3.0")) {
        try parseLatestRelease(json(tag: "v0.3.0", draft: true), assetName: "Stash.zip")
    }
    #expect(throws: ReleaseFeedError.notAStableRelease(tag: "v0.3.0")) {
        try parseLatestRelease(json(tag: "v0.3.0", prerelease: true), assetName: "Stash.zip")
    }
}

@Test func anUnreadableTagIsAnErrorNotAnUpdate() {
    #expect(throws: ReleaseFeedError.unreadableVersion(tag: "nightly")) {
        try parseLatestRelease(json(tag: "nightly"), assetName: "Stash.zip")
    }
}

@Test func garbageIsNotMistakenForARelease() {
    #expect(throws: ReleaseFeedError.malformedJSON) {
        try parseLatestRelease(Data("not json".utf8), assetName: "Stash.zip")
    }
}

@Test func onlyANewerVersionCountsAsAnUpdate() throws {
    let release = try parseLatestRelease(json(tag: "v0.2.0"), assetName: "Stash.zip")
    #expect(updateAvailability(current: AppVersion("0.1.0")!, latest: release) == .available(release))
    #expect(updateAvailability(current: AppVersion("0.2.0")!, latest: release) == .upToDate)
    // Kaynaktan derleyip yayınlanandan ileride olan biri (bu depoyu klonlayan
    // herkes) geriye "güncellenmemeli".
    #expect(updateAvailability(current: AppVersion("0.3.0")!, latest: release) == .upToDate)
}
