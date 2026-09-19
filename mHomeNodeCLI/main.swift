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

            // Samsung Appliance Easy Setup decoding
            if compId == 0x0075 && mfg.count >= 6 {
                let proto = mfg[2]
                let subtype = mfg[3]
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

// MARK: - CLI Argument Parsing
var duration: TimeInterval = 8.0
var verbose = false
var probeTarget: String? = nil

let args = CommandLine.arguments
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

let scanner = AdvancedCLIBleScanner(duration: duration, verbose: verbose, probeTarget: probeTarget)
RunLoop.main.run()
