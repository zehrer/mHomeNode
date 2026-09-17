import Foundation

/// Represents a room/location configured in HomeNode Server
public struct ServerRoom: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let floor: String?
    public let icon: String?
    public let archetype: String?
    public let deviceCount: Int?

    public init(
        id: String,
        name: String,
        floor: String? = nil,
        icon: String? = nil,
        archetype: String? = nil,
        deviceCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.floor = floor
        self.icon = icon
        self.archetype = archetype
        self.deviceCount = deviceCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case floor
        case icon
        case archetype
        case deviceCount = "device_count"
    }

    public var displayIcon: String {
        icon ?? "🏠"
    }

    public var displayTitle: String {
        "\(displayIcon) \(name)"
    }
}
