import Foundation

/// An attachment's identity: a lowercase UUID string. Stored as plain TEXT, encoded as a bare JSON string, and written
/// into a note as the line `[[attachment:<id>]]` (``AttachmentToken``).
public struct AttachmentID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> AttachmentID {
        AttachmentID(rawValue: UUID().uuidString.lowercased())
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
