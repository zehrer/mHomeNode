import Foundation
import CoreBluetooth

public enum DeviceFamily: String, Codable, Sendable {
    case shellyBlu = "Shelly BLU"
    case qingping = "QingPing"
    case btHomeGeneric = "BTHome Device"
    case govee = "Govee"
    case nuki = "Nuki"
    case ecoflow = "EcoFlow"
    case switchBot = "SwitchBot"
    case apple = "Apple"
    case standardBLE = "Bluetooth LE Device"
}

public struct DiscoveredDevice: Identifiable, Sendable, Equatable, Codable {
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
    public var customName: String?
    public var isIgnored: Bool
    public var macAddress: String?
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
        customName: String? = nil,
        isIgnored: Bool = false,
        macAddress: String? = nil,
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
        self.customName = customName
        self.isIgnored = isIgnored
        self.macAddress = macAddress
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    /// Whether this device has advertised recently (within the last 45 seconds)
    public var isCurrentlyActive: Bool {
        Date().timeIntervalSince(lastSeen) < 45.0
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
        if let cName = customName, !cName.isEmpty {
            return cName
        }
        if !name.isEmpty && name != "Unknown" {
            return name
        }
        if let mac = macAddress, !mac.isEmpty {
            return "\(family.rawValue) (\(mac))"
        }
        if family != .standardBLE {
            return family.rawValue
        }
        return "BLE Device (" + id.uuidString.prefix(6) + ")"
    }

    /// Whether this device represents a lighting accessory (Govee, LED strip, smart bulb, etc.)
    public var isLightingDevice: Bool {
        if family == .govee { return true }
        let low = (displayTitle + " " + name).lowercased()
        return low.contains("light") || low.contains("lamp") || low.contains("led") || low.contains("bulb") || low.contains("strip")
    }

    /// Converts into the HomeNode Server MobileBleScanItem format
    public func toMobileBleScanItem(scoutName: String = "iPhone (mHomeNode)") -> MobileBleScanItem {
        MobileBleScanItem(
            id: macAddress ?? id.uuidString,
            name: customName ?? (name == "Unknown" ? nil : name),
            rssi: Int16(clamping: rssi),
            manufacturerDataHex: manufacturerDataHex,
            family: family.rawValue,
            assignedRoom: assignedRoom,
            scoutName: scoutName,
            bthomeVersion: btHomeData != nil ? UInt8(btHomeData!.version) : nil,
            battery: btHomeData?.battery,
            temperatureC: btHomeData?.temperature.map { Float($0) },
            humidityPct: btHomeData?.humidity.map { Float($0) },
            illuminanceLux: btHomeData?.illuminance.map { Float($0) },
            pressureHpa: btHomeData?.pressure.map { Float($0) },
            contactOpen: btHomeData?.isDoorOpen,
            motionDetected: btHomeData?.isMotionDetected,
            buttonEvent: btHomeData?.buttonEvent?.rawValue
        )
    }
}
