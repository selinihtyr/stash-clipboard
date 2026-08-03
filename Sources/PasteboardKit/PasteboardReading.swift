import AppKit
import Foundation

/// Panoyu protokolün arkasına alıyoruz: yakalama kararlarının tamamı saf kodla
/// test edilebilsin, testler gerçek panoyu kirletmesin.
public protocol PasteboardReading: Sendable {
    var changeCount: Int { get }
    var types: [String] { get }
    func string() -> String?
    func imageData() -> Data?
    func fileURLStrings() -> [String]?
}

public struct SystemPasteboard: PasteboardReading, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    public init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public var changeCount: Int { pasteboard.changeCount }
    public var types: [String] { (pasteboard.types ?? []).map(\.rawValue) }
    public func string() -> String? { pasteboard.string(forType: .string) }
    public func imageData() -> Data? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return data }
        }
        return nil
    }
    public func fileURLStrings() -> [String]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return nil }
        return urls.map(\.path)
    }
}
