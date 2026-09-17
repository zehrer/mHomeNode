import Foundation

/// Represents a device that is ignored/blocked (e.g. neighbor's BLE sensor)
public struct IgnoredDeviceRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String?
    public var reason: String
    public var ignoredAt: String

    public init(
        id: String,
        name: String? = nil,
        reason: String = "Nachbargerät",
        ignoredAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.ignoredAt = ignoredAt
    }

    public var normalizedId: String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case reason
        case ignoredAt = "ignored_at"
    }
}
