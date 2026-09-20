import Foundation

/// Persistent record of a device registered to a specific managed location (e.g. "Home")
/// Preserves user-assigned room, custom name, and vendor identity across scan clears and restarts.
public struct LocationDeviceRecord: Identifiable, Codable, Equatable, Sendable {
    /// Device identifier: normalized MAC address if available, otherwise peripheral UUID string
    public let id: String
    public var customName: String?
    public var assignedRoom: String?
    public var vendorFamily: String
    public var firstRegistered: Date
    public var lastSeenAt: Date?

    public init(
        id: String,
        customName: String? = nil,
        assignedRoom: String? = nil,
        vendorFamily: String = "Bluetooth LE",
        firstRegistered: Date = Date(),
        lastSeenAt: Date? = Date()
    ) {
        self.id = id
        self.customName = customName
        self.assignedRoom = assignedRoom
        self.vendorFamily = vendorFamily
        self.firstRegistered = firstRegistered
        self.lastSeenAt = lastSeenAt
    }

    /// Primary display title
    public var displayTitle: String {
        if let custom = customName, !custom.isEmpty {
            return custom
        }
        return id
    }
}
