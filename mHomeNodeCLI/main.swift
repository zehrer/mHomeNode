import Foundation
import CoreBluetooth

// MARK: - mHomeNode CLI - Advanced BLE Analyzer & GATT Deep Probe (macOS)
// Scans for nearby BLE devices, identifies vendor families, decodes sensor telemetry,
// and actively probes connectable devices (GATT Service & Characteristic exploration).

public struct BleVendorInfo {
    public let name: String
    public let category: String
}

public enum KnownCompanyIDs {
    public static let lookup: [UInt16: BleVendorInfo] = [
        0x004C: BleVendorInfo(name: "Apple Inc.", category: "Personal Device / Accessory"),
        0x0006: BleVendorInfo(name: "Microsoft", category: "PC / Accessory"),
        0x0075: BleVendorInfo(name: "Samsung", category: "Mobile / Smart Device"),
        0x0087: BleVendorInfo(name: "Garmin", category: "Wearable / Watch"),
        0x00E0: BleVendorInfo(name: "Google", category: "Smart Home / Mobile"),
        0x0157: BleVendorInfo(name: "Anhui Huami (Amazfit)", category: "Wearable / Health"),
        0x01A8: BleVendorInfo(name: "Xiaomi Inc.", category: "Smart Home / Sensor"),
        0x038F: BleVendorInfo(name: "Xiaomi Mijia", category: "Smart Home / Sensor"),
        0x02D0: BleVendorInfo(name: "Nordic Semiconductor", category: "SoC / Sensor Beacon"),
        0x0059: BleVendorInfo(name: "Nordic Semiconductor", category: "SoC / Sensor Beacon"),
        0x0499: BleVendorInfo(name: "Ruuvi Innovations", category: "Environmental Sensor"),
        0x08A0: BleVendorInfo(name: "Allterco (Shelly)", category: "Smart Home / Sensor"),
        0x088B: BleVendorInfo(name: "Qingping Technology", category: "Environmental Sensor"),
        0x0825: BleVendorInfo(name: "TP-Link", category: "Smart Home / Network"),
        0x09CD: BleVendorInfo(name: "Woan Tech (SwitchBot)", category: "Smart Home / Automation"),
        0x08F6: BleVendorInfo(name: "SwitchBot", category: "Smart Home / Automation"),
        0x07D7: BleVendorInfo(name: "Nuki Home Solutions", category: "Smart Lock"),
        0xEC88: BleVendorInfo(name: "Govee (Intellirocks)", category: "Smart Lighting / Climate"),
        0x0001: BleVendorInfo(name: "Govee / Telink", category: "Smart Lighting / Climate"),
        0x0796: BleVendorInfo(name: "Tuya Global", category: "Smart Home / IoT"),
        0x004F: BleVendorInfo(name: "Sony", category: "Audio / Headphone"),
        0x009E: BleVendorInfo(name: "Bose", category: "Audio / Headphone"),
        0x05A7: BleVendorInfo(name: "Sonos", category: "Smart Audio"),
        0x000D: BleVendorInfo(name: "Texas Instruments", category: "SoC / Beacon"),
    ]
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
        if upper.contains("1805") { return "Current Time Service" }
        if upper.contains("FD5A") { return "Samsung SmartThings (Easy Setup)" }
        if upper.contains("FD6F") { return "Samsung Find / SmartThings" }
        if upper.contains("FE2C") { return "Google Fast Pair" }
        if upper.contains("FCD2") { return "BTHome V2" }
        if upper.contains("FDCD") { return "Qingping Service" }
        if upper.contains("FE95") { return "Xiaomi MiHome" }
        if upper.contains("FFF0") { return "Tuya / Telink Proprietary" }
        return "Service (\(uuid.prefix(8)))"
    }
}

public enum KnownGATTCharacteristic {
    public static func name(for uuid: String) -> String {
        let upper = uuid.uppercased()
        if upper.contains("2A00") { return "Device Name" }
        if upper.contains("2A01") { return "Appearance" }
        if upper.contains("2A04") { return "Peripheral Preferred Connection Parameters" }
        if upper.contains("2A19") { return "Battery Level" }
        if upper.contains("2A29") { return "Manufacturer Name String" }
        if upper.contains("2A24") { return "Model Number String" }
        if upper.contains("2A25") { return "Serial Number String" }
        if upper.contains("2A26") { return "Firmware Revision String" }
        if upper.contains("2A27") { return "Hardware Revision String" }
        if upper.contains("2A28") { return "Software Revision String" }
        if upper.contains("2A23") { return "System ID" }
        if upper.contains("2A2A") { return "IEEE 11073-20601 Regulatory Cert" }
        if upper.contains("2A50") { return "PnP ID" }
        return "Char (\(uuid.prefix(8)))"
    }
}

struct DiscoveredCLIDevice {
    let id: String
    var rawName: String
    var resolvedName: String
    var family: String
    var vendor: String?
    var category: String
    var rssi: Int
    var isConnectable: Bool
    var peripheral: CBPeripheral?
    var mac: String?
    var temperature: Double?
    var humidity: Double?
    var battery: UInt8?
    var pressure: Double?
    var manufacturerDataHex: String?
    var serviceDataHex: [String: String] = [:]
    var serviceUUIDs: [String] = []
    var packetCount: Int = 1
    var firstSeen: Date = Date()
    var lastSeen: Date = Date()
}

struct CLICharacteristicInfo {
    let uuid: String
    var name: String
    var properties: [String]
    var valueHex: String?
    var valueText: String?
    var error: String?
}

struct CLIServiceInfo {
    let uuid: String
    var name: String
    var characteristics: [CLICharacteristicInfo] = []
}

struct CLIDeviceInspectionResult {
    let deviceId: String
    let deviceName: String
    var manufacturer: String?
    var model: String?
    var serial: String?
    var firmware: String?
    var hardware: String?
    var battery: UInt8?
    var services: [CLIServiceInfo] = []
    var isProtected: Bool = false
    var statusSummary: String = "Inspection Completed"
}

// MARK: - GATT Deep Probe Runner
final class CLIGATTProber: NSObject, CBPeripheralDelegate {
    private let central: CBCentralManager
    private let peripheral: CBPeripheral
    private let deviceName: String
    private let onComplete: (CLIDeviceInspectionResult) -> Void

    private var result: CLIDeviceInspectionResult
    private var pendingReads = 0
    private var completionTimer: Timer?
    private var hasFinished = false

    init(
        central: CBCentralManager,
        peripheral: CBPeripheral,
        deviceName: String,
        onComplete: @escaping (CLIDeviceInspectionResult) -> Void
    ) {
        self.central = central
        self.peripheral = peripheral
        self.deviceName = deviceName
        self.onComplete = onComplete
        self.result = CLIDeviceInspectionResult(
            deviceId: peripheral.identifier.uuidString,
            deviceName: deviceName
        )
        super.init()
        self.peripheral.delegate = self
    }

    func start() {
        print("\u{001B}[34m[>] Connecting to '\(deviceName)' [\(peripheral.identifier.uuidString)]...\u{001B}[0m")
        central.connect(peripheral, options: nil)

        completionTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.hasFinished else { return }
            print("\u{001B}[33m[!] GATT Probe timeout reached (7s). Wrapping up discovered data...\u{001B}[0m")
            self.finish()
        }
    }

    func handleConnected() {
        print("\u{001B}[32m[✓] Connected! Discovering all GATT services...\u{001B}[0m")
        peripheral.discoverServices(nil)
    }

    func handleConnectionFailed(error: Error?) {
        print("\u{001B}[31m[-] Failed to connect: \(error?.localizedDescription ?? "Unknown error")\u{001B}[0m")
        result.statusSummary = "Connection Failed: \(error?.localizedDescription ?? "Unknown")"
        finish()
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("\u{001B}[31m[-] Error discovering services: \(error.localizedDescription)\u{001B}[0m")
            finish()
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            print("\u{001B}[33m[!] No GATT services discovered on device.\u{001B}[0m")
            result.statusSummary = "No Services Found"
            finish()
            return
        }

        print("[+] Discovered \(services.count) GATT services. Exploring characteristics...")
        for service in services {
            let sInfo = CLIServiceInfo(
                uuid: service.uuid.uuidString,
                name: KnownGATTService.name(for: service.uuid.uuidString)
            )
            result.services.append(sInfo)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("\u{001B}[33m[!] Characteristics error in \(service.uuid): \(error.localizedDescription)\u{001B}[0m")
            return
        }

        guard let chars = service.characteristics else { return }
        guard let sIdx = result.services.firstIndex(where: { $0.uuid == service.uuid.uuidString }) else { return }

        for c in chars {
            var props: [String] = []
            if c.properties.contains(.read) { props.append("Read") }
            if c.properties.contains(.write) { props.append("Write") }
            if c.properties.contains(.writeWithoutResponse) { props.append("WriteNoResp") }
            if c.properties.contains(.notify) { props.append("Notify") }
            if c.properties.contains(.indicate) { props.append("Indicate") }

            let cInfo = CLICharacteristicInfo(
                uuid: c.uuid.uuidString,
                name: KnownGATTCharacteristic.name(for: c.uuid.uuidString),
                properties: props
            )
            result.services[sIdx].characteristics.append(cInfo)

            if c.properties.contains(.read) {
                pendingReads += 1
                peripheral.readValue(for: c)
            }
        }

        if pendingReads == 0 {
            checkIfDone()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        pendingReads = max(0, pendingReads - 1)

        let cUuid = characteristic.uuid.uuidString
        for sIdx in 0..<result.services.count {
            if let cIdx = result.services[sIdx].characteristics.firstIndex(where: { $0.uuid == cUuid }) {
                if let error = error as? NSError {
                    let isAuth = error.domain == CBATTErrorDomain &&
                        (error.code == CBATTError.insufficientAuthentication.rawValue ||
                         error.code == CBATTError.insufficientEncryption.rawValue)
                    if isAuth {
                        result.isProtected = true
                        result.services[sIdx].characteristics[cIdx].error = "Protected (Requires Pairing/Auth)"
                    } else {
                        result.services[sIdx].characteristics[cIdx].error = error.localizedDescription
                    }
                } else if let data = characteristic.value {
                    let hex = data.map { String(format: "%02X", $0) }.joined()
                    result.services[sIdx].characteristics[cIdx].valueHex = hex

                    let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
                    if let s = str, !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " ") }) {
                        result.services[sIdx].characteristics[cIdx].valueText = s
                        assignStandardField(uuid: cUuid, text: s, data: data)
                    } else {
                        // Extract printable ASCII string (e.g. JSON payloads with binary headers)
                        let asciiBytes = data.filter { ($0 >= 32 && $0 <= 126) || $0 == 9 || $0 == 10 || $0 == 13 }
                        if asciiBytes.count >= 6,
                           let extracted = String(bytes: asciiBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !extracted.isEmpty {
                            result.services[sIdx].characteristics[cIdx].valueText = extracted
                        }
                        assignStandardField(uuid: cUuid, text: nil, data: data)
                    }
                }
                break
            }
        }

        if pendingReads == 0 {
            checkIfDone()
        }
    }

    private func assignStandardField(uuid: String, text: String?, data: Data) {
        let u = uuid.uppercased()
        if u.contains("2A29"), let t = text { result.manufacturer = t }
        if u.contains("2A24"), let t = text { result.model = t }
        if u.contains("2A25"), let t = text { result.serial = t }
        if u.contains("2A26"), let t = text { result.firmware = t }
        if u.contains("2A27"), let t = text { result.hardware = t }
        if u.contains("2A19"), let first = data.first { result.battery = first }
    }

    private func checkIfDone() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.hasFinished else { return }
            if self.pendingReads == 0 {
                self.finish()
            }
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        completionTimer?.invalidate()
        completionTimer = nil

        central.cancelPeripheralConnection(peripheral)
        onComplete(result)
    }
}

// MARK: - Advanced CLI Scanner & Orchestrator
final class AdvancedCLIBleScanner: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager!
    private var devices: [String: DiscoveredCLIDevice] = [:]
    private var scanDuration: TimeInterval = 0
    private var verbose: Bool = false
    private var probeTarget: String?
    private var startTime = Date()

    // Probing state
    private var probeQueue: [DiscoveredCLIDevice] = []
    private var activeProber: CLIGATTProber?
    private var inspectionResults: [CLIDeviceInspectionResult] = []

    init(duration: TimeInterval = 0, verbose: Bool = false, probeTarget: String? = nil) {
        self.scanDuration = duration
        self.verbose = verbose
        self.probeTarget = probeTarget
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("\u{001B}[32m[+] Bluetooth Powered On.\u{001B}[0m")
            print("Starting continuous BLE Scan on macOS...")
            if let target = probeTarget {
                print("\u{001B}[35m[i] GATT Deep Probe enabled for target: '\(target)'\u{001B}[0m")
            }
            if scanDuration > 0 {
                print("Running discovery scan for \(Int(scanDuration)) seconds...\n")
                Timer.scheduledTimer(withTimeInterval: scanDuration, repeats: false) { [weak self] _ in
                    self?.handleScanDurationExpired()
                }
            } else {
                print("Live Monitor Mode. Press Ctrl+C to terminate and view summary.\n")
            }

            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )

        case .unauthorized:
            print("\u{001B}[31m[-] Bluetooth Permission Denied.\u{001B}[0m")
            print("Please grant Terminal or your IDE Bluetooth permissions in System Settings -> Privacy & Security -> Bluetooth.")
            exit(1)
        case .poweredOff:
            print("\u{001B}[33m[!] Bluetooth is turned off. Please enable it in macOS Control Center.\u{001B}[0m")
            exit(1)
        default:
            print("[*] Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let rssiVal = RSSI.intValue
        guard rssiVal != 127 else { return }

        let uuidStr = peripheral.identifier.uuidString
        let rawName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let advertisedUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []

        var mfgHex: String?
        var vendorName: String?
        var vendorCategory = "Standard BLE"
        var family = "Bluetooth LE"
        var resolvedName = rawName.isEmpty ? "Unknown" : rawName
        var hardwareMac: String?
        var temp: Double?
        var hum: Double?
        var bat: UInt8?
        var press: Double?
        var serviceDataMap: [String: String] = [:]

        // 1. Manufacturer Data Parsing & Vendor Identification
        if let mfg = mfgData, mfg.count >= 2 {
            mfgHex = mfg.map { String(format: "%02X", $0) }.joined()
            let compId = UInt16(mfg[0]) | (UInt16(mfg[1]) << 8)

            if let vendor = KnownCompanyIDs.lookup[compId] {
                vendorName = vendor.name
                vendorCategory = vendor.category
                family = vendor.name
            }

            // Apple specific decoding
            if compId == 0x004C && mfg.count >= 4 {
                let appleType = mfg[2]
                switch appleType {
                case 0x02: resolvedName = "iBeacon"; vendorCategory = "Proximity Beacon"
                case 0x07: resolvedName = "AirPods / Audio Accessory"; vendorCategory = "Audio"
                case 0x09: resolvedName = "AirPlay / HomeKit Device"; vendorCategory = "Smart Home"
                case 0x10: if rawName.isEmpty { resolvedName = "Apple Device (Nearby)" }; vendorCategory = "Continuity / Nearby"
                case 0x12: resolvedName = "Find My / AirTag"; vendorCategory = "Tracker"
                default: if rawName.isEmpty { resolvedName = "Apple Device" }
                }
            }

            // Samsung Appliance & TV decoding
            if compId == 0x0075 && mfg.count >= 4 {
                let proto = mfg[2]
                let subtype = mfg[3]
                family = "Samsung"
                vendorName = "Samsung Electronics"
                if proto == 0x42 {
                    if subtype == 0x0C {
                        resolvedName = rawName.isEmpty ? "Samsung Washer/Dryer" : rawName
                        vendorCategory = "Smart Appliance"
                    } else if subtype == 0x04 {
                        resolvedName = rawName.isEmpty ? "Samsung Smart TV" : rawName
                        vendorCategory = "Smart TV"
                    } else if subtype == 0x01 {
                        resolvedName = rawName.isEmpty ? "Samsung Refrigerator" : rawName
                        vendorCategory = "Smart Appliance"
                    }
                } else if proto == 0x02 && subtype == 0x18 {
                    resolvedName = rawName.isEmpty ? "Samsung Smart TV" : rawName
                    vendorCategory = "Smart TV"
                } else {
                    let lowRaw = rawName.lowercased()
                    if lowRaw.contains("tv") || lowRaw.contains("crystal") || lowRaw.contains("qled") || lowRaw.contains("uhd") || lowRaw.contains("oled") {
                        resolvedName = rawName
                        vendorCategory = "Smart TV"
                    }
                }
            }

            // Smart TV fallback by name
            let lowRaw = rawName.lowercased()
            if lowRaw.starts(with: "[tv]") || lowRaw.contains("crystal uhd") || lowRaw.contains("smart tv") {
                vendorCategory = "Smart TV"
                if lowRaw.contains("samsung") || lowRaw.contains("crystal") {
                    family = "Samsung"
                    vendorName = "Samsung Electronics"
                }
                if resolvedName == "Unknown" || resolvedName.isEmpty {
                    resolvedName = rawName
                }
            }

            // Govee
            if compId == 0xEC88 || compId == 0x0001 || rawName.lowercased().starts(with: "govee") {
                family = "Govee"
                vendorName = "Govee (Intellirocks)"
                vendorCategory = "Smart Lighting / Sensor"
                if mfg.count >= 7 {
                    let b3 = Int(mfg[3])
                    let b4 = Int(mfg[4])
                    let b5 = Int(mfg[5])
                    let combined = (b3 << 16) | (b4 << 8) | b5
                    if combined > 0 && combined < 10000000 {
                        let potentialTemp = Double(combined / 1000) / 10.0
                        let potentialHum = Double(combined % 1000) / 10.0
                        if potentialTemp >= -20 && potentialTemp <= 60 && potentialHum >= 0 && potentialHum <= 100 {
                            temp = potentialTemp
                            hum = potentialHum
                            bat = mfg[6]
                        }
                    }
                }
            }

            // Qingping
            if compId == 0x088B {
                family = "Qingping"
                vendorName = "Qingping"
                vendorCategory = "Environmental Sensor"
                if mfg.count >= 8 {
                    let macSlice = Array(mfg[2...7].reversed())
                    hardwareMac = macSlice.map { String(format: "%02X", $0) }.joined(separator: ":")
                }
            }
        }

        // 2. Service Data Parsing
        if let sData = serviceData {
            for (uuid, data) in sData {
                let uStr = uuid.uuidString.uppercased()
                serviceDataMap[uStr] = data.map { String(format: "%02X", $0) }.joined()

                // Qingping 0xFDCD
                if uStr.contains("FDCD") && data.count >= 8 {
                    family = "Qingping"
                    vendorName = "Qingping"
                    vendorCategory = "Environmental Sensor"
                    let prodId = data[1]
                    switch prodId {
                    case 0x01: resolvedName = "Qingping CGG1"
                    case 0x07: resolvedName = "Qingping CGG1-M"
                    case 0x0C: resolvedName = "Qingping CGD1 Alarm Clock"
                    case 0x10: resolvedName = "Qingping CGDK2"
                    case 0x09: resolvedName = "Qingping CGP1W"
                    default: resolvedName = "Qingping (0x\(String(format: "%02X", prodId)))"
                    }
                    let macSlice = Array(data[2...7].reversed())
                    hardwareMac = macSlice.map { String(format: "%02X", $0) }.joined(separator: ":")
                } else if uStr.contains("FCD2") && data.count >= 3 {
                    // BTHome V2
                    family = "BTHome"
                    vendorCategory = "Smart Sensor (BTHome)"
                    var off = 1
                    while off < data.count {
                        let objId = data[off]
                        off += 1
                        switch objId {
                        case 0x01: if off < data.count { bat = data[off]; off += 1 }
                        case 0x02:
                            if off + 1 < data.count {
                                let r = Int16(bitPattern: UInt16(data[off]) | (UInt16(data[off + 1]) << 8))
                                temp = Double(r) * 0.01; off += 2
                            }
                        case 0x03:
                            if off + 1 < data.count {
                                let r = UInt16(data[off]) | (UInt16(data[off + 1]) << 8)
                                hum = Double(r) * 0.01; off += 2
                            }
                        case 0x04:
                            if off + 2 < data.count {
                                let r = UInt32(data[off]) | (UInt32(data[off + 1]) << 8) | (UInt32(data[off + 2]) << 16)
                                press = Double(r) * 0.01; off += 3
                            }
                        default: off += 1
                        }
                    }
                } else if uStr.contains("FE95") && data.count >= 5 {
                    // Xiaomi MiBeacon
                    family = "Xiaomi Mijia"
                    vendorName = "Xiaomi"
                    vendorCategory = "Smart Home Sensor"
                    let prodId = UInt16(data[2]) | (UInt16(data[3]) << 8)
                    switch prodId {
                    case 0x01AA: resolvedName = "Xiaomi Mijia Temp & RH (LYWSDCGQ)"
                    case 0x045B: resolvedName = "Xiaomi E-Ink Clock (LYWSD02)"
                    case 0x055B: resolvedName = "Xiaomi Mijia Square Temp & RH (LYWSD03MMC)"
                    case 0x0347: resolvedName = "Qingping Temp & RH (CGG1)"
                    case 0x0576: resolvedName = "Qingping Alarm Clock (CGD1)"
                    case 0x066F: resolvedName = "Qingping Temp & RH Lite (CGDK2)"
                    case 0x0387: resolvedName = "Miaomiaoce E-Ink Temp & RH (MHO-C401)"
                    default: if rawName.isEmpty { resolvedName = "Xiaomi Mijia (0x\(String(format: "%04X", prodId)))" }
                    }
                }
            }
        }

        let deviceKey = hardwareMac ?? uuidStr

        if var existing = devices[deviceKey] {
            existing.rssi = rssiVal
            existing.packetCount += 1
            existing.lastSeen = Date()
            existing.peripheral = peripheral
            existing.isConnectable = isConnectable
            if resolvedName != "Unknown" && (existing.resolvedName == "Unknown" || existing.resolvedName.isEmpty) {
                existing.resolvedName = resolvedName
            }
            if family != "Bluetooth LE" { existing.family = family }
            if let v = vendorName { existing.vendor = v }
            if vendorCategory != "Standard BLE" { existing.category = vendorCategory }
            if let t = temp { existing.temperature = t }
            if let h = hum { existing.humidity = h }
            if let b = bat { existing.battery = b }
            if let p = press { existing.pressure = p }
            if let m = mfgHex { existing.manufacturerDataHex = m }
            if !serviceDataMap.isEmpty {
                existing.serviceDataHex.merge(serviceDataMap) { _, new in new }
            }
            if !advertisedUUIDs.isEmpty {
                for u in advertisedUUIDs where !existing.serviceUUIDs.contains(u) {
                    existing.serviceUUIDs.append(u)
                }
            }
            devices[deviceKey] = existing
        } else {
            let item = DiscoveredCLIDevice(
                id: deviceKey,
                rawName: rawName,
                resolvedName: resolvedName,
                family: family,
                vendor: vendorName,
                category: vendorCategory,
                rssi: rssiVal,
                isConnectable: isConnectable,
                peripheral: peripheral,
                mac: hardwareMac,
                temperature: temp,
                humidity: hum,
                battery: bat,
                pressure: press,
                manufacturerDataHex: mfgHex,
                serviceDataHex: serviceDataMap,
                serviceUUIDs: advertisedUUIDs,
                packetCount: 1,
                firstSeen: Date(),
                lastSeen: Date()
            )
            devices[deviceKey] = item

            if verbose {
                printDeviceDiscoveryEvent(item)
            }
        }
    }

    private func printDeviceDiscoveryEvent(_ d: DiscoveredCLIDevice) {
        print("\u{001B}[36m>>> [NEW BLE DEVICE DETECTED]\u{001B}[0m")
        print("    ID/MAC:        \(d.id)")
        print("    Name:          \(d.resolvedName) (raw: '\(d.rawName)')")
        print("    Family:        \(d.family) • Category: \(d.category)")
        print("    Connectable:   \(d.isConnectable ? "YES (GATT Connect Possible)" : "NO (Broadcast Only)")")
        if let v = d.vendor { print("    Vendor:        \(v)") }
        print("    RSSI:          \(d.rssi) dBm")
        if let t = d.temperature, let h = d.humidity {
            print("    Sensor:        \(String(format: "%.1f°C", t)) | \(String(format: "%.0f%%", h))")
        }
        if let mfg = d.manufacturerDataHex {
            print("    Mfg Data (Hex): \(mfg)")
        }
        if !d.serviceDataHex.isEmpty {
            print("    Service Data:  \(d.serviceDataHex)")
        }
        if !d.serviceUUIDs.isEmpty {
            print("    Services:      \(d.serviceUUIDs.joined(separator: ", "))")
        }
        print("--------------------------------------------------------------------------------")
    }

    private func handleScanDurationExpired() {
        manager.stopScan()
        print("\n\u{001B}[32m[✓] Scan finished. Total devices discovered: \(devices.count)\u{001B}[0m\n")

        if let target = probeTarget {
            setupGATTProbeQueue(target: target)
        } else {
            finishAndPrintReport()
        }
    }

    private func setupGATTProbeQueue(target: String) {
        let lower = target.lowercased()
        let connectableDevices = devices.values.filter { $0.isConnectable && $0.peripheral != nil }

        if lower == "all" || lower == "connectable" {
            probeQueue = Array(connectableDevices.sorted(by: { $0.rssi > $1.rssi }))
        } else {
            probeQueue = connectableDevices.filter { d in
                d.resolvedName.lowercased().contains(lower) ||
                d.rawName.lowercased().contains(lower) ||
                d.id.lowercased().contains(lower)
            }
        }

        if probeQueue.isEmpty {
            print("\u{001B}[33m[!] No connectable devices matched target '\(target)'.\u{001B}[0m")
            let available = connectableDevices.map { "'\($0.resolvedName)' (\($0.id.prefix(8))...)" }.joined(separator: ", ")
            print("    Connectable devices found: \(available.isEmpty ? "None" : available)\n")
            finishAndPrintReport()
            return
        }

        print("\u{001B}[35m[i] Found \(probeQueue.count) target device(s) for GATT Deep Probe:\u{001B}[0m")
        for d in probeQueue {
            print("    • \(d.resolvedName) (RSSI: \(d.rssi) dBm, ID: \(d.id))")
        }
        print("")

        processNextProbe()
    }

    private func processNextProbe() {
        guard !probeQueue.isEmpty else {
            print("\u{001B}[32m[✓] All GATT Deep Probes completed!\u{001B}[0m\n")
            finishAndPrintReport()
            return
        }

        let device = probeQueue.removeFirst()
        guard let peripheral = device.peripheral else {
            processNextProbe()
            return
        }

        activeProber = CLIGATTProber(
            central: manager,
            peripheral: peripheral,
            deviceName: device.resolvedName
        ) { [weak self] inspectionResult in
            self?.inspectionResults.append(inspectionResult)
            self?.activeProber = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.processNextProbe()
            }
        }
        activeProber?.start()
    }

    // MARK: - Central Manager Connection Callbacks
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        activeProber?.handleConnected()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        activeProber?.handleConnectionFailed(error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    }

    func finishAndPrintReport() {
        print("=========================================================================================================")
        print("                     mHomeNode BLE ENVIRONMENT & GATT REPORT (macOS)                                     ")
        print("=========================================================================================================")
        print("Total Devices Discovered: \(devices.count)\n")

        // Group by category
        let grouped = Dictionary(grouping: devices.values) { $0.category }

        for (category, items) in grouped.sorted(by: { $0.key < $1.key }) {
            print("\u{001B}[1mCategory: \(category) (\(items.count))\u{001B}[0m")
            print(String(repeating: "-", count: 105))

            let sorted = items.sorted { $0.rssi > $1.rssi }
            for d in sorted {
                var metrics = ""
                if let t = d.temperature { metrics += String(format: "%.1f°C ", t) }
                if let h = d.humidity { metrics += String(format: "%.0f%% ", h) }
                if let b = d.battery { metrics += "Bat:\(b)% " }

                let idStr = (d.mac != nil ? "\(d.mac!) [MAC]" : String(d.id.prefix(18)))
                let nameStr = d.resolvedName.isEmpty ? "Unknown" : d.resolvedName
                let connTag = d.isConnectable ? "[Connectable]" : "[Broadcast]"

                print("  • \(idStr.padding(toLength: 22, withPad: " ", startingAt: 0)) | \(nameStr.padding(toLength: 32, withPad: " ", startingAt: 0)) | \(connTag.padding(toLength: 14, withPad: " ", startingAt: 0)) | \(String(format: "%4d dBm", d.rssi)) | \(metrics)")

                if let mfg = d.manufacturerDataHex, d.family != "Apple" {
                    print("    └─ Mfg Hex: \(mfg)")
                }
                if !d.serviceDataHex.isEmpty {
                    for (u, hex) in d.serviceDataHex {
                        print("    └─ Service Data [\(u)]: \(hex)")
                    }
                }
            }
            print("")
        }

        // Print GATT Deep Probe Section if any performed
        if !inspectionResults.isEmpty {
            print("=========================================================================================================")
            print("                                GATT DEEP INSPECTION RESULTS                                             ")
            print("=========================================================================================================")
            for r in inspectionResults {
                print("\u{001B}[1;36mDevice: \(r.deviceName) [\(r.deviceId)]\u{001B}[0m")
                print("Status: \(r.statusSummary) • Protected/Encrypted: \(r.isProtected ? "\u{001B}[33mYES (Pairing Required)\u{001B}[0m" : "\u{001B}[32mNO\u{001B}[0m")")

                if let m = r.manufacturer { print("  ├─ Manufacturer: \(m)") }
                if let mod = r.model { print("  ├─ Model Number: \(mod)") }
                if let s = r.serial { print("  ├─ Serial Number: \(s)") }
                if let fw = r.firmware { print("  ├─ Firmware:     \(fw)") }
                if let hw = r.hardware { print("  ├─ Hardware:     \(hw)") }
                if let bat = r.battery { print("  ├─ GATT Battery: \(bat)%") }

                print("  └─ Discovered Services (\(r.services.count)):")
                for (sIdx, s) in r.services.enumerated() {
                    let isLastService = sIdx == r.services.count - 1
                    let sPrefix = isLastService ? "     └──" : "     ├──"
                    print("\(sPrefix) Service: \u{001B}[1m\(s.name)\u{001B}[0m (\(s.uuid))")

                    let cPrefixBase = isLastService ? "        " : "     │  "
                    if s.characteristics.isEmpty {
                        print("\(cPrefixBase)└── (No characteristics found)")
                    } else {
                        for (cIdx, c) in s.characteristics.enumerated() {
                            let isLastChar = cIdx == s.characteristics.count - 1
                            let cPrefix = isLastChar ? "\(cPrefixBase)└──" : "\(cPrefixBase)├──"
                            var line = "\(cPrefix) [\(c.properties.joined(separator: ","))] \(c.name) (\(c.uuid))"
                            if let val = c.valueText {
                                line += " => \u{001B}[32m\"\(val)\"\u{001B}[0m"
                            } else if let hex = c.valueHex {
                                line += " => \u{001B}[34m0x\(hex)\u{001B}[0m"
                            }
                            if let err = c.error {
                                line += " => \u{001B}[33m[\(err)]\u{001B}[0m"
                            }
                            print(line)
                        }
                    }
                }
                print(String(repeating: "-", count: 105))
            }
        }

        print("=========================================================================================================\n")
        exit(0)
    }
}

// MARK: - Interactive BLE REPL & GATT Debugger / Proxy Engine
final class InteractiveBLERepl: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
    private var central: CBCentralManager!
    private var proxyManager: CBPeripheralManager!
    
    // Discovered devices list for indexed selection
    private var discoveredDevices: [DiscoveredCLIDevice] = []
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
    // Active peripheral session
    private var activePeripheral: CBPeripheral?
    private var activeServices: [CBService] = []
    private var activeCharacteristics: [CBCharacteristic] = []
    private var activeNotifications: Set<CBUUID> = []
    private var charValueCache: [CBUUID: Data] = [:]
    
    // Proxy state
    private var isProxyActive: Bool = false
    private var proxyName: String = "mHomeNode_Proxy"
    private var proxyServices: [CBMutableService] = []
    private var proxyCharMap: [CBUUID: CBMutableCharacteristic] = [:]
    
    // State flags
    private var isScanning: Bool = false
    private var pendingScan: Bool = false
    private var pendingConnectTarget: String? = nil
    private var isConnecting: Bool = false
    private var isRunning: Bool = true
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        proxyManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func start() {
        printBanner()
        
        // Background input reader loop
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            while let self = self, self.isRunning {
                self.printPrompt()
                guard let line = readLine() else { break }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                
                let sema = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    self.executeCommand(trimmed)
                    sema.signal()
                }
                sema.wait()
            }
            exit(0)
        }
        
        RunLoop.main.run()
    }
    
    private func printBanner() {
        print("""
        \u{001B}[1;36m
        ===================================================================================
                       mHomeNode BLE REPL & Low-Level GATT Diagnostic Console              
        ===================================================================================\u{001B}[0m
        Type \u{001B}[1;33mhelp\u{001B}[0m for available commands, \u{001B}[1;33mscan start\u{001B}[0m to discover devices, or \u{001B}[1;33mexit\u{001B}[0m to quit.
        """)
    }
    
    private func printPrompt() {
        var statusStr = "\u{001B}[31mDisconnected\u{001B}[0m"
        if let p = activePeripheral {
            let pName = p.name ?? "Unknown Device"
            statusStr = "\u{001B}[32mConnected: \(pName)\u{001B}[0m"
            if isProxyActive {
                statusStr += " \u{001B}[35m[Proxy: \(proxyName)]\u{001B}[0m"
            }
        } else if isScanning {
            statusStr = "\u{001B}[33mScanning\u{001B}[0m"
        }
        print("\u{001B}[1m[\(statusStr)] mHomeNode>\u{001B}[0m ", terminator: "")
        fflush(stdout)
    }
    
    private func printHelp() {
        print("""
        \u{001B}[1mCommands:\u{001B}[0m
          \u{001B}[1;33mscan [start|stop]\u{001B}[0m               - Start or stop Bluetooth Low Energy scanning
          \u{001B}[1;33mdevices [pattern]\u{001B}[0m / \u{001B}[1;33mls [pattern]\u{001B}[0m - List devices with wildcards (e.g. 'ls Go*' or 'ls *H70B*')
          \u{001B}[1;33mconnect <index|name|uuid>\u{001B}[0m       - Connect to a peripheral (e.g. 'connect 1' or 'connect H70B5')
          \u{001B}[1;33mdisconnect\u{001B}[0m                      - Disconnect from current peripheral
          \u{001B}[1;33mstatus\u{001B}[0m                          - Show current connection and proxy status
          \u{001B}[1;33mservices\u{001B}[0m                        - List GATT services discovered on connected peripheral
          \u{001B}[1;33mchars [service_uuid]\u{001B}[0m            - List characteristics and their permissions (read/write/notify)
          \u{001B}[1;33mread <char_uuid>\u{001B}[0m                - Read characteristic value (displays Hex and ASCII)
          \u{001B}[1;33mwrite <char> <hex> [-r] [-c]\u{001B}[0m    - Write hex bytes to characteristic.
                                               Flags: -r / --response (request write ack)
                                                      -c / --checksum (auto-calculate XOR checksum)
          \u{001B}[1;33mnotify <char> [on|off]\u{001B}[0m          - Subscribe to / unsubscribe from notifications
          \u{001B}[1;33mproxy start [name]\u{001B}[0m              - Mirror connected device GATT services and advertise as proxy
          \u{001B}[1;33mproxy stop\u{001B}[0m                      - Stop advertising and shutdown proxy
          \u{001B}[1;33mhelp\u{001B}[0m                            - Print this help message
          \u{001B}[1;33mclear\u{001B}[0m                           - Clear terminal screen
          \u{001B}[1;33mexit\u{001B}[0m / \u{001B}[1;33mquit\u{001B}[0m                    - Exit REPL
        """)
    }
    
    // MARK: - Command Execution
    private func executeCommand(_ rawLine: String) {
        let parts = rawLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let cmd = parts.first?.lowercased() else { return }
        let args = Array(parts.dropFirst())
        
        switch cmd {
        case "help", "?":
            printHelp()
            
        case "clear":
            print("\u{001B}[2J\u{001B}[H")
            
        case "scan":
            handleScanCommand(args)
            
        case "devices", "ls":
            listDevices(filter: args.isEmpty ? nil : args.joined(separator: " "))
            
        case "connect":
            handleConnectCommand(args)
            
        case "disconnect":
            handleDisconnectCommand()
            
        case "status":
            showStatus()
            
        case "services":
            listServices()
            
        case "chars", "characteristics":
            listCharacteristics(serviceQuery: args.first)
            
        case "read":
            handleReadCommand(args)
            
        case "write":
            handleWriteCommand(args)
            
        case "notify":
            handleNotifyCommand(args)
            
        case "proxy":
            handleProxyCommand(args)
            
        case "exit", "quit", "q":
            print("\u{001B}[33mExiting mHomeNode CLI...\u{001B}[0m")
            isRunning = false
            if let p = activePeripheral {
                central.cancelPeripheralConnection(p)
            }
            if isProxyActive {
                proxyManager.stopAdvertising()
            }
            exit(0)
            
        default:
            print("\u{001B}[31mUnknown command: '\(cmd)'. Type 'help' for instructions.\u{001B}[0m")
        }
    }
    
    // MARK: - Scan & Devices
    private func handleScanCommand(_ args: [String]) {
        let action = args.first?.lowercased() ?? "start"
        if action == "stop" {
            pendingScan = false
            if isScanning {
                central.stopScan()
                isScanning = false
                print("\u{001B}[33m[✓] Scan stopped. (\(discoveredDevices.count) devices in memory)\u{001B}[0m")
            } else {
                print("Scanner is not currently active.")
            }
        } else {
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                isScanning = true
                print("\u{001B}[32m[+] Continuous BLE scan active. Type 'devices' to view found devices or 'scan stop' to pause.\u{001B}[0m")
            } else {
                pendingScan = true
                print("\u{001B}[33m[*] Bluetooth adapter initializing... Scan will start automatically when powered on.\u{001B}[0m")
            }
        }
    }
    
    private func matchesGlob(pattern: String, text: String) -> Bool {
        var cleanPat = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleanPat.hasPrefix("\"") && cleanPat.hasSuffix("\"")) || (cleanPat.hasPrefix("'") && cleanPat.hasSuffix("'")) {
            cleanPat = String(cleanPat.dropFirst().dropLast())
        }

        if cleanPat.contains("*") || cleanPat.contains("?") {
            let escaped = NSRegularExpression.escapedPattern(for: cleanPat)
            let regexPattern = "^" + escaped
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            }
        }
        return text.localizedCaseInsensitiveContains(cleanPat)
    }

    private func listDevices(filter: String? = nil) {
        if discoveredDevices.isEmpty {
            print("\u{001B}[33mNo devices discovered yet. Run 'scan start' to search for nearby BLE devices.\u{001B}[0m")
            return
        }
        
        let cleanFilter = filter?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [(index: Int, dev: DiscoveredCLIDevice)]

        if let query = cleanFilter, !query.isEmpty {
            filtered = discoveredDevices.enumerated().compactMap { (idx, dev) in
                let matchesName = matchesGlob(pattern: query, text: dev.resolvedName)
                let matchesRaw = matchesGlob(pattern: query, text: dev.rawName)
                let matchesFamily = matchesGlob(pattern: query, text: dev.family)
                let matchesId = matchesGlob(pattern: query, text: dev.id)
                let matchesMac = dev.mac != nil && matchesGlob(pattern: query, text: dev.mac!)
                if matchesName || matchesRaw || matchesFamily || matchesId || matchesMac {
                    return (idx + 1, dev)
                }
                return nil
            }
        } else {
            filtered = discoveredDevices.enumerated().map { ($0 + 1, $1) }
        }

        if filtered.isEmpty {
            print("\u{001B}[33mNo devices matched filter '\(cleanFilter ?? "")' (\(discoveredDevices.count) total devices in memory).\u{001B}[0m\n")
            return
        }

        let title = cleanFilter != nil && !cleanFilter!.isEmpty
            ? "Filtered BLE Peripherals (\(filtered.count) of \(discoveredDevices.count) matching '\(cleanFilter!)'):"
            : "Discovered BLE Peripherals (\(discoveredDevices.count)):"

        print("\n\u{001B}[1m\(title)\u{001B}[0m")
        print("---------------------------------------------------------------------------------------------------------")
        print(" Idx | RSSI     | Conn | Family     | Name                             | Identifier")
        print("---------------------------------------------------------------------------------------------------------")
        
        for (idx1Based, dev) in filtered {
            let idxStr = String(format: "%3d", idx1Based)
            let rssiStr = String(format: "%4d dBm", dev.rssi)
            let connStr = dev.isConnectable ? "\u{001B}[32mYes \u{001B}[0m" : "\u{001B}[37mNo  \u{001B}[0m"
            let famStr = dev.family.padding(toLength: 10, withPad: " ", startingAt: 0)
            let nameStr = (dev.resolvedName.isEmpty ? "Unknown" : dev.resolvedName).prefix(32).padding(toLength: 32, withPad: " ", startingAt: 0)
            let idStr = dev.mac ?? dev.id
            
            print(" [\(idxStr)] | \(rssiStr) | \(connStr) | \(famStr) | \(nameStr) | \(idStr)")
            if let mfg = dev.manufacturerDataHex, dev.family != "Apple" {
                print("       └─ Mfg Data: \(mfg)")
            }
        }
        print("---------------------------------------------------------------------------------------------------------")
        print("Tip: Connect with \u{001B}[1;33mconnect <index>\u{001B}[0m (e.g. 'connect \(filtered.first?.index ?? 1)')\n")
    }
    
    // MARK: - Connect & Disconnect
    private func handleConnectCommand(_ args: [String]) {
        guard let query = args.first else {
            print("\u{001B}[31mUsage: connect <index | name | uuid>\u{001B}[0m")
            return
        }
        
        var targetPeripheral: CBPeripheral?
        
        // 1. Check if index number
        if let idx = Int(query), idx >= 1 && idx <= discoveredDevices.count {
            let dev = discoveredDevices[idx - 1]
            if let u = UUID(uuidString: dev.id) {
                targetPeripheral = discoveredPeripherals[u]
            }
        }
        
        // 2. Check if UUID
        if targetPeripheral == nil, let u = UUID(uuidString: query) {
            targetPeripheral = discoveredPeripherals[u] ?? central.retrievePeripherals(withIdentifiers: [u]).first
        }
        
        // 3. Search by name substring
        if targetPeripheral == nil {
            let qLower = query.lowercased()
            if let found = discoveredDevices.first(where: {
                $0.resolvedName.lowercased().contains(qLower) || $0.rawName.lowercased().contains(qLower)
            }) {
                if let u = UUID(uuidString: found.id) {
                    targetPeripheral = discoveredPeripherals[u]
                }
            }
        }
        
        // 4. Also search discoveredPeripherals directly
        if targetPeripheral == nil {
            let qLower = query.lowercased()
            for (_, p) in discoveredPeripherals {
                if let name = p.name?.lowercased(), name.contains(qLower) {
                    targetPeripheral = p
                    break
                }
            }
        }

        guard let p = targetPeripheral else {
            if isScanning {
                pendingConnectTarget = query
                print("\u{001B}[33m[*] Device '\(query)' not seen yet. Waiting for it to appear in scan...\u{001B}[0m")
            } else {
                print("\u{001B}[31m[-] Target '\(query)' not found in discovered devices. Run 'scan start' then 'devices'.\u{001B}[0m")
            }
            return
        }
        
        if isScanning {
            central.stopScan()
            isScanning = false
        }
        
        if let current = activePeripheral, current.identifier != p.identifier {
            central.cancelPeripheralConnection(current)
        }
        
        activePeripheral = p
        p.delegate = self
        isConnecting = true
        activeServices = []
        activeCharacteristics = []
        activeNotifications.removeAll()
        
        print("\u{001B}[33m[*] Connecting to \(p.name ?? p.identifier.uuidString) [\(p.identifier)]...\u{001B}[0m")
        central.connect(p, options: nil)
    }
    
    private func handleDisconnectCommand() {
        guard let p = activePeripheral else {
            print("No peripheral is currently connected.")
            return
        }
        if isProxyActive {
            handleProxyCommand(["stop"])
        }
        print("\u{001B}[33m[*] Disconnecting from \(p.name ?? p.identifier.uuidString)...\u{001B}[0m")
        central.cancelPeripheralConnection(p)
        activePeripheral = nil
        activeServices = []
        activeCharacteristics = []
    }
    
    private func showStatus() {
        print("\n\u{001B}[1mBluetooth Session Status:\u{001B}[0m")
        print("  • Adapter State:       \(central.state.rawValue == 5 ? "\u{001B}[32mPowered ON\u{001B}[0m" : "\u{001B}[31mOffline (\(central.state.rawValue))\u{001B}[0m")")
        print("  • Background Scan:     \(isScanning ? "\u{001B}[32mActive\u{001B}[0m" : "Stopped")")
        print("  • Discovered Devices:  \(discoveredDevices.count)")
        if let p = activePeripheral {
            let stateStr: String
            switch p.state {
            case .connected: stateStr = "\u{001B}[32mConnected\u{001B}[0m"
            case .connecting: stateStr = "\u{001B}[33mConnecting...\u{001B}[0m"
            case .disconnecting: stateStr = "\u{001B}[33mDisconnecting...\u{001B}[0m"
            case .disconnected: stateStr = "\u{001B}[31mDisconnected\u{001B}[0m"
            @unknown default: stateStr = "Unknown"
            }
            print("  • Target Peripheral:   \(p.name ?? "Unnamed") (\(p.identifier)) [\(stateStr)]")
            print("  • Services Discovered: \(activeServices.count)")
            print("  • Chars Discovered:    \(activeCharacteristics.count)")
            print("  • Active Notifications:\(activeNotifications.count)")
        } else {
            print("  • Target Peripheral:   None")
        }
        print("  • GATT Mirror Proxy:   \(isProxyActive ? "\u{001B}[35mRunning (\(proxyName))\u{001B}[0m" : "Disabled")\n")
    }
    
    // MARK: - GATT Operations
    private func listServices() {
        guard let _ = activePeripheral else {
            print("\u{001B}[31m[-] Not connected to any peripheral. Use 'connect' first.\u{001B}[0m")
            return
        }
        if activeServices.isEmpty {
            print("No services discovered yet.")
            return
        }
        
        print("\n\u{001B}[1mGATT Services (\(activeServices.count)):\u{001B}[0m")
        for (i, s) in activeServices.enumerated() {
            let name = KnownGATTService.name(for: s.uuid.uuidString)
            print(" [\(i + 1)] \u{001B}[1;36m\(s.uuid.uuidString)\u{001B}[0m  \(name)")
        }
        print("Tip: Use \u{001B}[1;33mchars [service_uuid]\u{001B}[0m to inspect characteristics.\n")
    }
    
    private func listCharacteristics(serviceQuery: String?) {
        guard let _ = activePeripheral else {
            print("\u{001B}[31m[-] Not connected to any peripheral. Use 'connect' first.\u{001B}[0m")
            return
        }
        
        var targetServices = activeServices
        if let sq = serviceQuery?.uppercased() {
            targetServices = activeServices.filter { $0.uuid.uuidString.uppercased().contains(sq) }
            if targetServices.isEmpty {
                print("No service matching '\(sq)' found.")
                return
            }
        }
        
        print("\n\u{001B}[1mGATT Characteristics:\u{001B}[0m")
        for s in targetServices {
            let sName = KnownGATTService.name(for: s.uuid.uuidString)
            print("Service: \u{001B}[1;36m\(s.uuid.uuidString)\u{001B}[0m (\(sName))")
            let chars = s.characteristics ?? []
            if chars.isEmpty {
                print("  └── (None)")
            } else {
                for (cIdx, c) in chars.enumerated() {
                    let isLast = cIdx == chars.count - 1
                    let prefix = isLast ? "  └──" : "  ├──"
                    var propList: [String] = []
                    if c.properties.contains(.read) { propList.append("Read") }
                    if c.properties.contains(.write) { propList.append("Write") }
                    if c.properties.contains(.writeWithoutResponse) { propList.append("WriteWithoutResp") }
                    if c.properties.contains(.notify) { propList.append("Notify") }
                    if c.properties.contains(.indicate) { propList.append("Indicate") }
                    
                    let cName = KnownGATTCharacteristic.name(for: c.uuid.uuidString)
                    var line = "\(prefix) [\(propList.joined(separator: ", "))] \u{001B}[1m\(c.uuid.uuidString)\u{001B}[0m - \(cName)"
                    
                    if activeNotifications.contains(c.uuid) {
                        line += " \u{001B}[32m[NOTIFY ACTIVE]\u{001B}[0m"
                    }
                    if let cached = charValueCache[c.uuid] {
                        let hex = cached.map { String(format: "%02X", $0) }.joined(separator: " ")
                        let ascii = String(data: cached, encoding: .utf8) ?? ""
                        line += "\n        Value: [\(hex)]"
                        if !ascii.isEmpty && ascii.allSatisfy({ $0.isASCII && !$0.isNewline }) {
                            line += " \"\(ascii)\""
                        }
                    }
                    print(line)
                }
            }
            print("")
        }
    }
    
    private func findChar(query: String) -> CBCharacteristic? {
        let q = query.uppercased()
        if let match = activeCharacteristics.first(where: { $0.uuid.uuidString.uppercased() == q }) {
            return match
        }
        if let match = activeCharacteristics.first(where: { $0.uuid.uuidString.uppercased().contains(q) }) {
            return match
        }
        return nil
    }
    
    private func handleReadCommand(_ args: [String]) {
        guard let query = args.first else {
            print("\u{001B}[31mUsage: read <char_uuid>\u{001B}[0m (e.g. 'read 2B10' or 'read 2A00')")
            return
        }
        guard let p = activePeripheral else {
            print("\u{001B}[31m[-] Not connected.\u{001B}[0m")
            return
        }
        guard let c = findChar(query: query) else {
            print("\u{001B}[31m[-] Characteristic matching '\(query)' not found. Type 'chars' to see available UUIDs.\u{001B}[0m")
            return
        }
        guard c.properties.contains(.read) else {
            print("\u{001B}[33m[!] Characteristic \(c.uuid) does not have the 'read' property.\u{001B}[0m")
            return
        }
        
        print("[*] Reading value for \(c.uuid.uuidString)...")
        p.readValue(for: c)
    }
    
    private func handleWriteCommand(_ args: [String]) {
        guard args.count >= 2 else {
            print("""
            \u{001B}[31mUsage: write <char_uuid> <hex_data> [--response|-r] [--checksum|-c]\u{001B}[0m
            Example: write 2B11 3301010000000000000000000000000000000033 --response
            Example: write 2B11 330101 -c -r
            """)
            return
        }
        guard let p = activePeripheral else {
            print("\u{001B}[31m[-] Not connected.\u{001B}[0m")
            return
        }
        
        let charQuery = args[0]
        let rawHex = args[1].replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
        
        guard let c = findChar(query: charQuery) else {
            print("\u{001B}[31m[-] Characteristic '\(charQuery)' not found.\u{001B}[0m")
            return
        }
        
        let reqResponse = args.contains("-r") || args.contains("--response") || args.contains("-with-response")
        let calcChecksum = args.contains("-c") || args.contains("--checksum")
        
        var bytes: [UInt8] = []
        var idx = rawHex.startIndex
        while idx < rawHex.endIndex {
            let nextIdx = rawHex.index(idx, offsetBy: 2, limitedBy: rawHex.endIndex) ?? rawHex.endIndex
            let byteStr = String(rawHex[idx..<nextIdx])
            if let byte = UInt8(byteStr, radix: 16) {
                bytes.append(byte)
            } else {
                print("\u{001B}[31m[-] Invalid hex string: '\(byteStr)'\u{001B}[0m")
                return
            }
            idx = nextIdx
        }
        
        // Auto-calculate Govee checksum if requested or if user gave 19 bytes for Govee frame
        if calcChecksum || (bytes.count == 19 && (bytes[0] == 0x33 || bytes[0] == 0xAA)) {
            var cs: UInt8 = 0
            for b in bytes { cs ^= b }
            bytes.append(cs)
            print("Auto-calculated XOR checksum byte: 0x\(String(format: "%02X", cs)) (Total \(bytes.count) bytes)")
        } else if bytes.count < 20 && calcChecksum {
            // Pad to 19 bytes then XOR
            while bytes.count < 19 { bytes.append(0) }
            var cs: UInt8 = 0
            for b in bytes { cs ^= b }
            bytes.append(cs)
            print("Padded to 20 bytes with checksum: 0x\(String(format: "%02X", cs))")
        }
        
        let data = Data(bytes)
        let writeType: CBCharacteristicWriteType = (reqResponse || !c.properties.contains(.writeWithoutResponse)) ? .withResponse : .withoutResponse
        
        print("\u{001B}[32m[-> WRITE]\u{001B}[0m To \(c.uuid.uuidString) [\(data.map { String(format: "%02X", $0) }.joined(separator: " "))] (\(writeType == .withResponse ? "withResponse" : "withoutResponse"))...")
        p.writeValue(data, for: c, type: writeType)
        
        if writeType == .withoutResponse {
            print("[✓] Written without response.")
        }
    }
    
    private func handleNotifyCommand(_ args: [String]) {
        guard let query = args.first else {
            print("\u{001B}[31mUsage: notify <char_uuid> [on|off]\u{001B}[0m")
            return
        }
        guard let p = activePeripheral else {
            print("\u{001B}[31m[-] Not connected.\u{001B}[0m")
            return
        }
        guard let c = findChar(query: query) else {
            print("\u{001B}[31m[-] Characteristic '\(query)' not found.\u{001B}[0m")
            return
        }
        
        let enable = (args.count > 1) ? (args[1].lowercased() != "off" && args[1].lowercased() != "false") : !activeNotifications.contains(c.uuid)
        
        print("[*] Setting notify = \(enable) on \(c.uuid.uuidString)...")
        p.setNotifyValue(enable, for: c)
    }
    
    // MARK: - BLE GATT Mirror Proxy
    private func handleProxyCommand(_ args: [String]) {
        let action = args.first?.lowercased() ?? "start"
        if action == "stop" {
            if isProxyActive {
                proxyManager.stopAdvertising()
                proxyManager.removeAllServices()
                isProxyActive = false
                proxyServices.removeAll()
                proxyCharMap.removeAll()
                print("\u{001B}[33m[✓] BLE GATT Mirror Proxy stopped.\u{001B}[0m")
            } else {
                print("Proxy is not active.")
            }
            return
        }
        
        guard let p = activePeripheral, p.state == .connected else {
            print("\u{001B}[31m[-] To start a proxy, you must first be connected to a real peripheral.\u{001B}[0m")
            print("Tip: connect <device>, wait for services, then run 'proxy start [name]'.")
            return
        }
        guard proxyManager.state == .poweredOn else {
            print("\u{001B}[31m[-] CBPeripheralManager is not powered on (State: \(proxyManager.state.rawValue))\u{001B}[0m")
            return
        }
        
        if args.count > 1 {
            proxyName = args[1]
        } else {
            proxyName = "\(p.name ?? "BLE")_Proxy"
        }
        
        print("\n\u{001B}[1;35m[*] Initializing GATT Mirror Proxy for '\(p.name ?? "Device")' as '\(proxyName)'...\u{001B}[0m")
        proxyManager.stopAdvertising()
        proxyManager.removeAllServices()
        proxyServices.removeAll()
        proxyCharMap.removeAll()
        
        var primaryUUIDs: [CBUUID] = []
        
        for s in activeServices {
            let mutableService = CBMutableService(type: s.uuid, primary: s.isPrimary)
            var mutableChars: [CBMutableCharacteristic] = []
            
            for c in s.characteristics ?? [] {
                var props: CBCharacteristicProperties = []
                var perms: CBAttributePermissions = []
                
                if c.properties.contains(.read) {
                    props.insert(.read)
                    perms.insert(.readable)
                }
                if c.properties.contains(.write) {
                    props.insert(.write)
                    perms.insert(.writeable)
                }
                if c.properties.contains(.writeWithoutResponse) {
                    props.insert(.writeWithoutResponse)
                    perms.insert(.writeable)
                }
                if c.properties.contains(.notify) {
                    props.insert(.notify)
                }
                if c.properties.contains(.indicate) {
                    props.insert(.indicate)
                }
                
                let initialVal = charValueCache[c.uuid]
                let mChar = CBMutableCharacteristic(
                    type: c.uuid,
                    properties: props,
                    value: (props.contains(.read) && !props.contains(.write)) ? initialVal : nil,
                    permissions: perms
                )
                mutableChars.append(mChar)
                proxyCharMap[c.uuid] = mChar
            }
            
            mutableService.characteristics = mutableChars
            proxyServices.append(mutableService)
            proxyManager.add(mutableService)
            if s.isPrimary {
                primaryUUIDs.append(s.uuid)
            }
        }
        
        let advData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: proxyName,
            CBAdvertisementDataServiceUUIDsKey: primaryUUIDs
        ]
        
        proxyManager.startAdvertising(advData)
        isProxyActive = true
        
        print("\u{001B}[1;32m[✓] Proxy is now ADVERTISING as '\(proxyName)' with \(proxyServices.count) mirrored services!\u{001B}[0m")
        print("\u{001B}[37mOpen the official mobile app or a BLE scanner on your phone. Connect to '\(proxyName)'.")
        print("Any writes from the app will be intercepted, printed here, and forwarded to the real device!\u{001B}[0m\n")
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("\u{001B}[32m[i] Central Manager Ready.\u{001B}[0m")
            if pendingScan {
                pendingScan = false
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                isScanning = true
                print("\u{001B}[32m[+] Continuous BLE scan active. Type 'devices' to view found devices or 'scan stop' to pause.\u{001B}[0m")
            }
        } else {
            print("\u{001B}[31m[!] Central Manager State: \(central.state.rawValue)\u{001B}[0m")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let idStr = peripheral.identifier.uuidString
        let rawName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let isConn = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
        
        discoveredPeripherals[peripheral.identifier] = peripheral
        
        var mfgHex: String? = nil
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            mfgHex = mfg.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        
        // Identify family
        var family = "Standard"
        let lower = rawName.lowercased()
        if lower.contains("govee") { family = "Govee" }
        else if lower.contains("shelly") { family = "Shelly" }
        else if lower.contains("qingping") { family = "Qingping" }
        else if lower.contains("apple") || lower.contains("iphone") || lower.contains("mac") { family = "Apple" }
        
        if let existingIdx = discoveredDevices.firstIndex(where: { $0.id == idStr }) {
            discoveredDevices[existingIdx].rssi = RSSI.intValue
            discoveredDevices[existingIdx].isConnectable = isConn
            if !rawName.isEmpty {
                discoveredDevices[existingIdx].rawName = rawName
                discoveredDevices[existingIdx].resolvedName = rawName
            }
            if let m = mfgHex { discoveredDevices[existingIdx].manufacturerDataHex = m }
        } else {
            let dev = DiscoveredCLIDevice(
                id: idStr,
                rawName: rawName,
                resolvedName: rawName.isEmpty ? "Unknown (\(idStr.prefix(6)))" : rawName,
                family: family,
                vendor: nil,
                category: "BLE Device",
                rssi: RSSI.intValue,
                isConnectable: isConn,
                peripheral: peripheral,
                mac: nil,
                temperature: nil,
                humidity: nil,
                battery: nil,
                pressure: nil,
                manufacturerDataHex: mfgHex,
                serviceDataHex: [:],
                serviceUUIDs: [],
                packetCount: 1,
                firstSeen: Date(),
                lastSeen: Date()
            )
            discoveredDevices.append(dev)
        }

        if let target = pendingConnectTarget {
            let tLower = target.lowercased()
            let nameMatch = rawName.lowercased().contains(tLower) || (peripheral.name?.lowercased().contains(tLower) ?? false)
            let idMatch = idStr.lowercased() == tLower || (target.count >= 8 && idStr.lowercased().hasPrefix(tLower))
            if nameMatch || idMatch {
                pendingConnectTarget = nil
                print("\n\u{001B}[32m[+] Target '\(target)' detected (\(rawName.isEmpty ? idStr : rawName))! Connecting...\u{001B}[0m")
                handleConnectCommand([target])
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnecting = false
        print("\u{001B}[32m[✓] Connected to \(peripheral.name ?? peripheral.identifier.uuidString)!\u{001B}[0m Discovering all services...")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnecting = false
        activePeripheral = nil
        print("\u{001B}[31m[-] Failed to connect: \(error?.localizedDescription ?? "Unknown error")\u{001B}[0m")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("\n\u{001B}[33m[!] Disconnected from \(peripheral.name ?? peripheral.identifier.uuidString) (Reason: \(error?.localizedDescription ?? "Clean Disconnect"))\u{001B}[0m")
        if activePeripheral?.identifier == peripheral.identifier {
            activePeripheral = nil
            activeServices = []
            activeCharacteristics = []
            activeNotifications.removeAll()
            if isProxyActive {
                handleProxyCommand(["stop"])
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("\u{001B}[31m[-] Discover services error: \(error.localizedDescription)\u{001B}[0m")
            return
        }
        guard let services = peripheral.services else { return }
        activeServices = services
        print("[*] Discovered \(services.count) services. Discovering characteristics...")
        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if !activeCharacteristics.contains(where: { $0.uuid == c.uuid }) {
                activeCharacteristics.append(c)
            }
        }
        
        let allDone = activeServices.allSatisfy { $0.characteristics != nil }
        if allDone {
            print("\u{001B}[32m[✓] GATT Discovery complete: \(activeServices.count) services, \(activeCharacteristics.count) characteristics ready.\u{001B}[0m")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("\u{001B}[31m[-] Value update error on \(characteristic.uuid): \(error.localizedDescription)\u{001B}[0m")
            return
        }
        let data = characteristic.value ?? Data()
        charValueCache[characteristic.uuid] = data
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = String(data: data, encoding: .utf8) ?? ""
        
        var displayStr = "Hex: [\(hex)]"
        if !ascii.isEmpty && ascii.allSatisfy({ $0.isASCII && !$0.isNewline }) {
            displayStr += " ASCII: \"\(ascii)\""
        }
        
        if activeNotifications.contains(characteristic.uuid) {
            print("\n\u{001B}[1;36m[NOTIFY \(characteristic.uuid.uuidString)]\u{001B}[0m \(data.count) bytes: \(displayStr)")
        } else {
            print("\u{001B}[32m[READ \(characteristic.uuid.uuidString)]\u{001B}[0m \(data.count) bytes: \(displayStr)")
        }
        
        // If proxy is active, forward notification to connected centrals
        if isProxyActive, let mChar = proxyCharMap[characteristic.uuid] {
            proxyManager.updateValue(data, for: mChar, onSubscribedCentrals: nil)
            print("\u{001B}[1;35m[PROXY -> APP RELAY]\u{001B}[0m Forwarded notify for \(characteristic.uuid.uuidString) to app.")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("\u{001B}[31m[-] Write error on \(characteristic.uuid.uuidString): \(error.localizedDescription)\u{001B}[0m")
        } else {
            print("\u{001B}[32m[✓ VERIFIED] Write confirmed by peripheral for \(characteristic.uuid.uuidString)!\u{001B}[0m")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("\u{001B}[31m[-] Notification state error on \(characteristic.uuid.uuidString): \(error.localizedDescription)\u{001B}[0m")
            return
        }
        if characteristic.isNotifying {
            activeNotifications.insert(characteristic.uuid)
            print("\u{001B}[32m[✓] Subscribed to notifications for \(characteristic.uuid.uuidString).\u{001B}[0m")
        } else {
            activeNotifications.remove(characteristic.uuid)
            print("\u{001B}[33m[✓] Unsubscribed from notifications for \(characteristic.uuid.uuidString).\u{001B}[0m")
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate (Proxy)
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            // Ready for proxying
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            let data = req.value ?? Data()
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("\n\u{001B}[1;35m[PROXY <- APP WRITE]\u{001B}[0m Char: \(req.characteristic.uuid.uuidString), \(data.count) bytes: [\(hex)]")
            
            // Forward to real physical peripheral
            if let p = activePeripheral, p.state == .connected, let realChar = findChar(query: req.characteristic.uuid.uuidString) {
                let writeType: CBCharacteristicWriteType = realChar.properties.contains(.write) ? .withResponse : .withoutResponse
                print("\u{001B}[1;36m[PROXY -> DEVICE FORWARD]\u{001B}[0m Writing to real device (\(writeType == .withResponse ? "withResponse" : "withoutResponse"))...")
                p.writeValue(data, for: realChar, type: writeType)
            } else {
                print("\u{001B}[31m[PROXY] Real characteristic not available to forward write.\u{001B}[0m")
            }
            
            peripheral.respond(to: req, withResult: .success)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("\n\u{001B}[1;35m[PROXY <- APP READ]\u{001B}[0m Char: \(request.characteristic.uuid.uuidString)")
        if let cached = charValueCache[request.characteristic.uuid] {
            request.value = cached
            peripheral.respond(to: request, withResult: .success)
        } else {
            request.value = Data()
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("\u{001B}[31m[-] Proxy advertising failed: \(error.localizedDescription)\u{001B}[0m")
        } else {
            print("\u{001B}[32m[✓] Proxy advertising broadcasting successfully.\u{001B}[0m")
        }
    }
}

// MARK: - CLI Argument Parsing & Launch Mode
let args = CommandLine.arguments

if args.contains("-h") || args.contains("--help") {
    print("""
Usage: mHomeNodeCLI [options]

Modes:
  Interactive REPL (Default):
    mHomeNodeCLI                     Start interactive BLE terminal session
    mHomeNodeCLI -i / --repl         Explicitly start REPL

  Automated Batch Scan:
    mHomeNodeCLI --duration <sec>    Scan for N seconds, summarize, and exit
    mHomeNodeCLI --live              Continuous live packet streaming
    mHomeNodeCLI --probe <id|all>    Auto-connect and probe GATT services
    mHomeNodeCLI -v / --verbose      Verbose advertisement payload printing
""")
    exit(0)
}

let isExplicitRepl = args.contains("-i") || args.contains("--repl") || args.contains("--interactive")
let isExplicitBatch = args.contains("--probe") || args.contains("--duration") || args.contains("--live")

if isExplicitRepl || !isExplicitBatch {
    // Default interactive mode when run directly
    let repl = InteractiveBLERepl()
    repl.start()
} else {
    // Automated batch scan mode
    var duration: TimeInterval = 8.0
    var verbose = false
    var probeTarget: String? = nil

    if args.contains("--live") {
        duration = 0
    }
    if args.contains("-v") || args.contains("--verbose") {
        verbose = true
    }
    if let durIdx = args.firstIndex(of: "--duration"), durIdx + 1 < args.count {
        if let d = Double(args[durIdx + 1]) {
            duration = d
        }
    }
    if let probeIdx = args.firstIndex(of: "--probe"), probeIdx + 1 < args.count {
        probeTarget = args[probeIdx + 1]
    } else if args.contains("--probe") {
        probeTarget = "all"
    }

    _ = AdvancedCLIBleScanner(duration: duration, verbose: verbose, probeTarget: probeTarget)
    RunLoop.main.run()
}
