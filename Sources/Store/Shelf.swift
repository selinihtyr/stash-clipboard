import Foundation

public struct Shelf: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
