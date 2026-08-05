import Foundation

/// Uygulamanın ağa çıktığı TEK yer. Bunu bir protokolün arkasına koymak
/// yalnızca test kolaylığı değil, denetlenebilirlik meselesi: "Stash ne zaman
/// ağa çıkıyor?" sorusunun cevabı tek dosyada duruyor (bkz. README, Gizlilik).
public protocol ReleaseFetching: Sendable {
    /// En son kararlı sürümün ham JSON'u.
    func latestReleaseJSON() async throws -> Data
    /// Dosyayı indirir ve geçici dizindeki yolunu döner. Çağıran taraf silmekle
    /// yükümlü.
    func download(_ url: URL) async throws -> URL
}

public enum ReleaseClientError: Error, Equatable {
    case http(status: Int)
    /// Sürüm hiç yayınlanmamış (GitHub 404 döner). Bu bir hata değil, bilgi:
    /// kaynaktan derleyen biri için normal durum, kullanıcıya kırmızı bir
    /// uyarı olarak gösterilmemeli.
    case noReleaseYet
    case tooLarge(bytes: Int64)
}

public struct GitHubReleaseClient: ReleaseFetching {
    public let owner: String
    public let repo: String
    public let userAgent: String
    /// İndirilen dosya için üst sınır. Sunucunun söylediği boyuta güvenmek
    /// yerine gerçekten inen baytları sınırlıyoruz: aksi halde yanlış (ya da
    /// kötü niyetli) bir yanıt diski doldurabilirdi.
    public let maximumDownloadBytes: Int64

    public init(owner: String, repo: String, userAgent: String,
                maximumDownloadBytes: Int64 = 200 * 1024 * 1024) {
        self.owner = owner
        self.repo = repo
        self.userAgent = userAgent
        self.maximumDownloadBytes = maximumDownloadBytes
    }

    /// `ephemeral`: çerez, önbellek ve kimlik bilgisi diske hiç yazılmıyor.
    /// Bir güncelleme kontrolünün kullanıcının makinesinde iz bırakması için
    /// hiçbir sebep yok.
    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 300
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        // Kimlik doğrulama YOK: istek anonim, kullanıcı hakkında hiçbir şey
        // taşımıyor. User-Agent GitHub'ın zorunlu tuttuğu tek alan.
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    public func latestReleaseJSON() async throws -> Data {
        var request = URLRequest(url: URL(string:
            "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw ReleaseClientError.noReleaseYet }
        guard status == 200 else { throw ReleaseClientError.http(status: status) }
        return data
    }

    public func download(_ url: URL) async throws -> URL {
        let (bytes, response) = try await session.bytes(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ReleaseClientError.http(status: status) }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("stash-update-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                written += Int64(buffer.count)
                guard written <= maximumDownloadBytes else {
                    try? FileManager.default.removeItem(at: destination)
                    throw ReleaseClientError.tooLarge(bytes: written)
                }
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        written += Int64(buffer.count)
        guard written <= maximumDownloadBytes else {
            try? FileManager.default.removeItem(at: destination)
            throw ReleaseClientError.tooLarge(bytes: written)
        }
        try handle.write(contentsOf: buffer)
        return destination
    }
}
