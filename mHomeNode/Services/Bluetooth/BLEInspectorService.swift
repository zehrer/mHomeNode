import Foundation
import CoreBluetooth
import OSLog

/// Standard Bluetooth SIG GATT characteristic and service UUIDs
public enum StandardGATTUUID {
    // Device Information Service (0x180A)
    public static let deviceInformationService = CBUUID(string: "180A")
    public static let manufacturerNameString = CBUUID(string: "2A29")
    public static let modelNumberString = CBUUID(string: "2A24")
    public static let serialNumberString = CBUUID(string: "2A25")
    public static let firmwareRevisionString = CBUUID(string: "2A26")
    public static let hardwareRevisionString = CBUUID(string: "2A27")
    public static let softwareRevisionString = CBUUID(string: "2A28")

    // Generic Access Service (0x1800)
    public static let genericAccessService = CBUUID(string: "1800")
    public static let deviceName = CBUUID(string: "2A00")
    public static let appearance = CBUUID(string: "2A01")

    // Battery Service (0x180F)
    public static let batteryService = CBUUID(string: "180F")
    public static let batteryLevel = CBUUID(string: "2A19")
}

public enum KnownGATTService {
    public static func name(for uuid: String) -> String {
        let upper = uuid.uppercased()
        if upper.contains("180A") { return "Device Information" }
        if upper.contains("1800") { return "Generic Access" }
        if upper.contains("1801") { return "Generic Attribute" }
        if upper.contains("180F") { return "Battery Service" }
        if upper.contains("180D") { return "Heart Rate" }
        if upper.contains("1809") { return "Health Thermometer" }
        if upper.contains("FD5A") { return "Samsung SmartThings (Easy Setup)" }
        if upper.contains("FD6F") { return "Samsung Find My Mobile" }
        if upper.contains("FE2C") { return "Google Fast Pair" }
        if upper.contains("FCD2") { return "BTHome V2" }
        if upper.contains("FDCD") { return "Qingping Service" }
        if upper.contains("FE95") { return "Xiaomi MiHome" }
        if upper.contains("FFF0") { return "Tuya / Telink Service" }
        return "Service (\(uuid.prefix(8)))"
    }
}

public enum KnownGATTCharacteristic {
    public static func name(for uuid: String) -> String {
        let upper = uuid.uppercased()
        if upper.contains("2A00") { return "Device Name" }
        if upper.contains("2A01") { return "Appearance" }
        if upper.contains("2A19") { return "Battery Level" }
        if upper.contains("2A29") { return "Manufacturer Name" }
        if upper.contains("2A24") { return "Model Number" }
        if upper.contains("2A25") { return "Serial Number" }
        if upper.contains("2A26") { return "Firmware Revision" }
        if upper.contains("2A27") { return "Hardware Revision" }
        if upper.contains("2A28") { return "Software Revision" }
        return "Char (\(uuid.prefix(8)))"
    }
}

public struct DiscoveredCharacteristicInfo: Sendable, Codable, Equatable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public var name: String?
    public var properties: [String]
    public var valueHex: String?
    public var valueText: String?
    public var error: String?

    public init(
        uuid: String,
        name: String? = nil,
        properties: [String] = [],
        valueHex: String? = nil,
        valueText: String? = nil,
        error: String? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.properties = properties
        self.valueHex = valueHex
        self.valueText = valueText
        self.error = error
    }
}

public struct DiscoveredServiceInfo: Sendable, Codable, Equatable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public var name: String?
    public var characteristics: [DiscoveredCharacteristicInfo]

    public init(
        uuid: String,
        name: String? = nil,
        characteristics: [DiscoveredCharacteristicInfo] = []
    ) {
        self.uuid = uuid
        self.name = name
        self.characteristics = characteristics
    }
}

/// Information retrieved from active GATT characteristics of a connectable peripheral
public struct DeviceInspectionInfo: Sendable, Codable, Equatable {
    public var deviceName: String?
    public var manufacturerName: String?
    public var modelNumber: String?
    public var serialNumber: String?
    public var firmwareRevision: String?
    public var hardwareRevision: String?
    public var appearance: UInt16?
    public var appearanceCategory: String?
    public var batteryLevel: UInt8?
    public var inspectedAt: Date
    public var discoveredServices: [DiscoveredServiceInfo]
    public var statusSummary: String?
    public var isProtected: Bool

    public init(
        deviceName: String? = nil,
        manufacturerName: String? = nil,
        modelNumber: String? = nil,
        serialNumber: String? = nil,
        firmwareRevision: String? = nil,
        hardwareRevision: String? = nil,
        appearance: UInt16? = nil,
        appearanceCategory: String? = nil,
        batteryLevel: UInt8? = nil,
        inspectedAt: Date = Date(),
        discoveredServices: [DiscoveredServiceInfo] = [],
        statusSummary: String? = nil,
        isProtected: Bool = false
    ) {
        self.deviceName = deviceName
        self.manufacturerName = manufacturerName
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.firmwareRevision = firmwareRevision
        self.hardwareRevision = hardwareRevision
        self.appearance = appearance
        self.appearanceCategory = appearanceCategory
        self.batteryLevel = batteryLevel
        self.inspectedAt = inspectedAt
        self.discoveredServices = discoveredServices
        self.statusSummary = statusSummary
        self.isProtected = isProtected
    }

    /// Maps a 16-bit Bluetooth SIG Appearance value to a human-readable category
    public static func category(for appearance: UInt16) -> String {
        // Bluetooth Core Specification: Appearance category is top 10 bits (appearance >> 6)
        let category = appearance >> 6
        switch category {
        case 1: return "Phone"
        case 2: return "Computer"
        case 3: return "Watch"
        case 4: return "Clock"
        case 5: return "Display"
        case 6: return "Remote Control"
        case 7: return "Eye-glasses"
        case 8: return "Tag / Tracker"
        case 9: return "Keyring"
        case 10: return "Media Player"
        case 11: return "Barcode Scanner"
        case 12: return "Thermometer"
        case 13: return "Heart Rate Sensor"
        case 14: return "Blood Pressure"
        case 15: return "Human Interface Device"
        case 16: return "Glucose Meter"
        case 17: return "Running Walking Sensor"
        case 18: return "Cycling"
        case 19: return "Control Device"
        case 20: return "Network Device"
        case 21: return "Sensor"
        case 22: return "Light Fixture / Lamp"
        case 23: return "Fan"
        case 24: return "HVAC"
        case 25: return "Air Conditioning"
        case 26: return "Humidifier"
        case 27: return "Heating"
        case 28: return "Access Control"
        case 29: return "Motorized Device"
        case 30: return "Power Device"
        case 31: return "Light Source"
        case 81: return "Pulse Oximeter"
        case 82: return "Weight Scale"
        case 83: return "Personal Mobility Device"
        case 84: return "Continuous Glucose Monitor"
        case 85: return "Insulin Pump"
        case 86: return "Medication Delivery"
        case 87: return "Outdoor Sports Activity"
        default:
            // Direct 16-bit matches for common subcategories
            switch appearance {
            case 512: return "Generic Tag"
            case 576: return "Keyring / Tracker"
            case 768: return "Generic Thermometer"
            case 769: return "Ear Thermometer"
            case 1408: return "Light Fixture"
            default:
                return "Device (0x\(String(format: "%04X", appearance)))"
            }
        }
    }
}

/// Service that performs active, short-lived GATT connections to read device info and appearance
public final class BLEInspectorService: NSObject, @unchecked Sendable, CBPeripheralDelegate {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "BLEInspector")

    private var activeContinuation: CheckedContinuation<DeviceInspectionInfo, Error>?
    private var activePeripheral: CBPeripheral?
    private var pendingInfo = DeviceInspectionInfo()
    private var timeoutWorkItem: DispatchWorkItem?
    private weak var centralManager: CBCentralManager?

    public init(centralManager: CBCentralManager? = nil) {
        self.centralManager = centralManager
        super.init()
    }

    public func setCentralManager(_ manager: CBCentralManager) {
        self.centralManager = manager
    }

    /// Asynchronously connects to a peripheral, reads standard GATT info, and disconnects immediately
    public func inspect(peripheral: CBPeripheral, timeoutSeconds: TimeInterval = 6.0) async throws -> DeviceInspectionInfo {
        guard let central = centralManager else {
            throw NSError(domain: "BLEInspectorService", code: 1, userInfo: [NSLocalizedDescriptionKey: "CBCentralManager is not set"])
        }

        // Clean any existing state
        cancelCurrentInspection()

        return try await withCheckedThrowingContinuation { continuation in
            self.activeContinuation = continuation
            self.activePeripheral = peripheral
            self.pendingInfo = DeviceInspectionInfo()
            peripheral.delegate = self

            // Setup timeout
            let item = DispatchWorkItem { [weak self] in
                self?.handleTimeout()
            }
            self.timeoutWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: item)

            self.logger.info("Connecting to peripheral \(peripheral.identifier) for GATT inspection...")
            central.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: false
            ])
        }
    }

    // MARK: - Central Manager Events (called from BLEScannerService)

    public func didConnect(peripheral: CBPeripheral) {
        guard peripheral == activePeripheral else { return }
        logger.info("Connected to \(peripheral.identifier). Discovering all services...")
        // Discover ALL services (standard and vendor proprietary like Samsung 0xFD5A)
        peripheral.discoverServices(nil)
    }

    public func didFailToConnect(peripheral: CBPeripheral, error: Error?) {
        guard peripheral == activePeripheral else { return }
        logger.warning("Failed to connect to \(peripheral.identifier): \(error?.localizedDescription ?? "unknown error")")
        finish(with: .failure(error ?? NSError(domain: "BLEInspectorService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Connection failed. Please move closer to the device."])))
    }

    public func didDisconnect(peripheral: CBPeripheral, error: Error?) {
        guard peripheral == activePeripheral else { return }
        logger.info("Disconnected from \(peripheral.identifier).")
        // Conclude with whatever info was gathered
        disconnectAndFinish()
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == activePeripheral else { return }
        if let err = error {
            logger.warning("Service discovery failed: \(err.localizedDescription)")
            pendingInfo.statusSummary = "Service discovery failed: \(err.localizedDescription)"
            disconnectAndFinish()
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            logger.info("No services found on \(peripheral.identifier).")
            pendingInfo.statusSummary = "Connected, but peripheral exposed no GATT services."
            disconnectAndFinish()
            return
        }

        pendingInfo.discoveredServices = services.map { s in
            DiscoveredServiceInfo(
                uuid: s.uuid.uuidString,
                name: KnownGATTService.name(for: s.uuid.uuidString),
                characteristics: []
            )
        }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == activePeripheral else { return }
        if let err = error {
            logger.warning("Characteristics discovery failed for \(service.uuid): \(err.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics, !characteristics.isEmpty else { return }
        if let sIndex = pendingInfo.discoveredServices.firstIndex(where: { $0.uuid == service.uuid.uuidString }) {
            for char in characteristics {
                var props: [String] = []
                if char.properties.contains(.read) { props.append("Read") }
                if char.properties.contains(.write) { props.append("Write") }
                if char.properties.contains(.writeWithoutResponse) { props.append("WriteNoResp") }
                if char.properties.contains(.notify) { props.append("Notify") }
                if char.properties.contains(.indicate) { props.append("Indicate") }

                let cInfo = DiscoveredCharacteristicInfo(
                    uuid: char.uuid.uuidString,
                    name: KnownGATTCharacteristic.name(for: char.uuid.uuidString),
                    properties: props
                )
                pendingInfo.discoveredServices[sIndex].characteristics.append(cInfo)

                if char.properties.contains(.read) {
                    peripheral.readValue(for: char)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == activePeripheral else { return }

        // Find characteristic in pendingInfo to record value or error
        for sIdx in 0..<pendingInfo.discoveredServices.count {
            if let cIdx = pendingInfo.discoveredServices[sIdx].characteristics.firstIndex(where: { $0.uuid == characteristic.uuid.uuidString }) {
                if let err = error {
                    let errStr = err.localizedDescription
                    pendingInfo.discoveredServices[sIdx].characteristics[cIdx].error = errStr
                    let low = errStr.lowercased()
                    if low.contains("auth") || low.contains("encrypt") || low.contains("pair") {
                        pendingInfo.isProtected = true
                        pendingInfo.statusSummary = "Protected: Device requires Bluetooth authentication / SmartThings pairing"
                    }
                    return
                }

                if let data = characteristic.value, !data.isEmpty {
                    let hex = data.map { String(format: "%02X", $0) }.joined()
                    pendingInfo.discoveredServices[sIdx].characteristics[cIdx].valueHex = hex
                    if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !str.isEmpty,
                       str.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0.isWhitespace) }) {
                        pendingInfo.discoveredServices[sIdx].characteristics[cIdx].valueText = str
                    }
                }
            }
        }

        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }

        switch characteristic.uuid {
        case StandardGATTUUID.deviceName:
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                pendingInfo.deviceName = str
                logger.debug("Read Device Name: \(str)")
            }

        case StandardGATTUUID.manufacturerNameString:
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                pendingInfo.manufacturerName = str
                logger.debug("Read Manufacturer Name: \(str)")
            }

        case StandardGATTUUID.modelNumberString:
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                pendingInfo.modelNumber = str
                logger.debug("Read Model Number: \(str)")
            }

        case StandardGATTUUID.serialNumberString:
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                pendingInfo.serialNumber = str
            }

        case StandardGATTUUID.firmwareRevisionString:
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                pendingInfo.firmwareRevision = str
                logger.debug("Read Firmware Revision: \(str)")
            }

        case StandardGATTUUID.hardwareRevisionString:
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                pendingInfo.hardwareRevision = str
            }

        case StandardGATTUUID.appearance:
            if data.count >= 2 {
                let val = UInt16(data[0]) | (UInt16(data[1]) << 8)
                pendingInfo.appearance = val
                let cat = DeviceInspectionInfo.category(for: val)
                pendingInfo.appearanceCategory = cat
                logger.debug("Read Appearance: 0x\(String(format: "%04X", val)) -> \(cat)")
            }

        case StandardGATTUUID.batteryLevel:
            pendingInfo.batteryLevel = data[0]
            logger.debug("Read Battery Level: \(data[0])%")

        default:
            break
        }
    }

    // MARK: - Lifecycle & Cleanup

    private func handleTimeout() {
        logger.info("GATT inspection timed out for \(self.activePeripheral?.identifier.uuidString ?? ""). Disconnecting...")
        disconnectAndFinish()
    }

    private func disconnectAndFinish() {
        if pendingInfo.statusSummary == nil {
            if pendingInfo.isProtected {
                pendingInfo.statusSummary = "Protected: Device requires Bluetooth authentication / SmartThings pairing"
            } else if pendingInfo.modelNumber != nil || pendingInfo.manufacturerName != nil {
                pendingInfo.statusSummary = "Device information retrieved successfully"
            } else if !pendingInfo.discoveredServices.isEmpty {
                pendingInfo.statusSummary = "Discovered \(pendingInfo.discoveredServices.count) service(s)"
            } else {
                pendingInfo.statusSummary = "No GATT response received from device"
            }
        }
        if let p = activePeripheral, let central = centralManager {
            central.cancelPeripheralConnection(p)
        }
        finish(with: .success(pendingInfo))
    }

    private func finish(with result: Result<DeviceInspectionInfo, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        let cont = activeContinuation
        activeContinuation = nil
        activePeripheral = nil

        switch result {
        case .success(let info):
            cont?.resume(returning: info)
        case .failure(let err):
            cont?.resume(throwing: err)
        }
    }

    private func cancelCurrentInspection() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let p = activePeripheral, let central = centralManager {
            central.cancelPeripheralConnection(p)
        }
        activeContinuation?.resume(throwing: NSError(domain: "BLEInspectorService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Inspection cancelled"]))
        activeContinuation = nil
        activePeripheral = nil
    }
}
