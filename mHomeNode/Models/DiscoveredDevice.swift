import Foundation
import CoreBluetooth

public enum DeviceFamily: String, Codable, Sendable {
    case shellyBlu = "Shelly BLU"
    case qingping = "QingPing"
    case btHomeGeneric = "BTHome Device"
    case standardBLE = "Bluetooth LE Device"
}

public struct DiscoveredDevice: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var rssi: Int
    public var rssiHistory: [Int]
    public var serviceUUIDs: [String]
    public var manufacturerDataHex: String?
    public var btHomeData: BTHomeData?
    public var family: DeviceFamily
    public var isConnectable: Bool
    public var assignedRoom: String?
    public var firstSeen: Date
    public var lastSeen: Date

    public init(
        id: UUID,
        name: String,
        rssi: Int,
        rssiHistory: [Int] = [],
        serviceUUIDs: [String] = [],
        manufacturerDataHex: String? = nil,
        btHomeData: BTHomeData? = nil,
        family: DeviceFamily = .standardBLE,
        isConnectable: Bool = false,
        assignedRoom: String? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.rssiHistory = rssiHistory.isEmpty ? [rssi] : rssiHistory
        self.serviceUUIDs = serviceUUIDs
        self.manufacturerDataHex = manufacturerDataHex
        self.btHomeData = btHomeData
        self.family = family
        self.isConnectable = isConnectable
        self.assignedRoom = assignedRoom
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    /// Signal strength quality level: 0 (poor) to 4 (excellent)
    public var signalBars: Int {
        switch rssi {
        case -60...0: return 4
        case -72 ..< -60: return 3
        case -84 ..< -72: return 2
        case -95 ..< -84: return 1
        default: return 0
        }
    }

    public var displayTitle: String {
        if !name.isEmpty && name != "Unknown" {
            return name
        }
        if family != .standardBLE {
            return family.rawValue
        }
        return "BLE Device (" + id.uuidString.prefix(6) + ")"
    }
}
