import Foundation
import CoreBluetooth

public enum DeviceFamily: String, Codable, Sendable {
    case shellyBlu = "Shelly BLU"
    case qingping = "QingPing"
    case xiaomi = "Xiaomi Mijia"
    case btHomeGeneric = "BTHome Device"
    case govee = "Govee"
    case nuki = "Nuki"
    case ecoflow = "EcoFlow"
    case switchBot = "SwitchBot"
    case apple = "Apple"
    case samsung = "Samsung"
    case microsoft = "Microsoft Windows"
    case smartLight = "Smart Light"
    case tuya = "Tuya / Telink"
    case audio = "Audio Device"
    case google = "Google"
    case sony = "Sony"
    case bose = "Bose"
    case garmin = "Garmin"
    case ruuvi = "Ruuvi"
    case nordic = "Nordic Semiconductor"
    case standardBLE = "Bluetooth LE Device"
}

public struct DiscoveredDevice: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public var name: String
    public var rssi: Int
    public var rssiHistory: [Int]
    public var serviceUUIDs: [String]
    public var manufacturerDataHex: String?
    public var serviceDataHex: [String: String]?
    public var btHomeData: BTHomeData?
    public var family: DeviceFamily
    public var isConnectable: Bool
    public var assignedRoom: String?
    public var customName: String?
    public var isIgnored: Bool
    public var macAddress: String?
    public var firstSeen: Date
    public var lastSeen: Date
    public var lastMeasurementDate: Date?
    public var inspectionInfo: DeviceInspectionInfo?

    public init(
        id: UUID,
        name: String,
        rssi: Int,
        rssiHistory: [Int] = [],
        serviceUUIDs: [String] = [],
        manufacturerDataHex: String? = nil,
        serviceDataHex: [String: String]? = nil,
        inspectionInfo: DeviceInspectionInfo? = nil,
        btHomeData: BTHomeData? = nil,
        family: DeviceFamily = .standardBLE,
        isConnectable: Bool = false,
        assignedRoom: String? = nil,
        customName: String? = nil,
        isIgnored: Bool = false,
        macAddress: String? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        lastMeasurementDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.rssiHistory = rssiHistory.isEmpty ? [rssi] : rssiHistory
        self.serviceUUIDs = serviceUUIDs
        self.manufacturerDataHex = manufacturerDataHex
        self.serviceDataHex = serviceDataHex
        self.inspectionInfo = inspectionInfo
        self.btHomeData = btHomeData
        self.family = family
        self.isConnectable = isConnectable
        self.assignedRoom = assignedRoom
        self.customName = customName
        self.isIgnored = isIgnored
        self.macAddress = macAddress
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastMeasurementDate = lastMeasurementDate ?? (btHomeData != nil ? lastSeen : nil)
    }

    /// Merges retrieved GATT inspection info and updates name, family, and battery if unassigned
    public mutating func applyInspectionInfo(_ info: DeviceInspectionInfo) {
        self.inspectionInfo = info

        if self.name == "Unknown" || self.name.isEmpty {
            if let dname = info.deviceName, !dname.isEmpty {
                self.name = dname
            } else if let model = info.modelNumber, !model.isEmpty {
                self.name = model
            } else if let mfg = info.manufacturerName, !mfg.isEmpty {
                self.name = "\(mfg) Device"
            }
        }

        if self.family == .standardBLE, let mfg = info.manufacturerName?.lowercased() {
            if mfg.contains("apple") {
                self.family = .apple
            } else if mfg.contains("samsung") {
                self.family = .samsung
            } else if mfg.contains("microsoft") {
                self.family = .microsoft
            } else if mfg.contains("shelly") || mfg.contains("alterco") {
                self.family = .shellyBlu
            } else if mfg.contains("xiaomi") {
                self.family = .xiaomi
            } else if mfg.contains("tuya") {
                self.family = .tuya
            } else if mfg.contains("google") {
                self.family = .google
            } else if mfg.contains("sony") {
                self.family = .sony
            } else if mfg.contains("bose") {
                self.family = .bose
            } else if mfg.contains("garmin") {
                self.family = .garmin
            } else if mfg.contains("ruuvi") {
                self.family = .ruuvi
            } else if mfg.contains("govee") {
                self.family = .govee
            } else if mfg.contains("nordic") {
                self.family = .nordic
            }
        }

        if let bat = info.batteryLevel {
            if self.btHomeData != nil {
                self.btHomeData?.battery = bat
            } else {
                self.btHomeData = BTHomeData(battery: bat)
            }
        }
    }

    /// Elapsed time in seconds since the last sensor measurement packet arrived
    public var measurementAgeSeconds: TimeInterval? {
        guard let date = lastMeasurementDate else { return nil }
        return Date().timeIntervalSince(date)
    }

    /// Whether the sensor reading is stale / out of signal range (threshold: 30 minutes)
    public var isSignalLost: Bool {
        guard let age = measurementAgeSeconds else { return true }
        return age >= 1800.0 // 30 minutes
    }

    /// Human-readable quantized measurement age level: "now", "1 min", "2 min" ... "1h"
    public var measurementAgeText: String {
        guard let age = measurementAgeSeconds else { return "No signal" }
        if age >= 1800.0 {
            return "No signal"
        }
        if age < 45.0 {
            return "now"
        }
        let minutes = Int(age / 60.0)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = Int(age / 3600.0)
        return "\(hours)h"
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
