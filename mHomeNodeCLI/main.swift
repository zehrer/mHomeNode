import Foundation
import CoreBluetooth

// MARK: - mHomeNode CLI - Advanced BLE Analyzer & Device Identifier
// Scans for nearby BLE devices, identifies vendor families, decodes sensor telemetry,
// and outputs both a live dashboard and full payload inspection.

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

struct DiscoveredCLIDevice {
    let id: String
    var rawName: String
    var resolvedName: String
    var family: String
    var vendor: String?
    var category: String
    var rssi: Int
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

final class AdvancedCLIBleScanner: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager!
    private var devices: [String: DiscoveredCLIDevice] = [:]
    private var scanDuration: TimeInterval = 0
    private var verbose: Bool = false
    private var startTime = Date()
    private var timer: Timer?

    init(duration: TimeInterval = 0, verbose: Bool = false) {
        self.scanDuration = duration
        self.verbose = verbose
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("\u{001B}[32m[+] Bluetooth Powered On.\u{001B}[0m")
            print("Starting continuous BLE Scan on macOS...")
            if scanDuration > 0 {
                print("Running for \(Int(scanDuration)) seconds, then generating report...\n")
                Timer.scheduledTimer(withTimeInterval: scanDuration, repeats: false) { [weak self] _ in
                    self?.finishAndPrintReport()
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
                case 0x02:
                    resolvedName = "iBeacon"
                    vendorCategory = "Proximity Beacon"
                case 0x07:
                    resolvedName = "AirPods / Audio Accessory"
                    vendorCategory = "Audio"
                case 0x09:
                    resolvedName = "AirPlay / HomeKit Device"
                    vendorCategory = "Smart Home"
                case 0x10:
                    if rawName.isEmpty { resolvedName = "Apple Device (Nearby)" }
                    vendorCategory = "Continuity / Nearby"
                case 0x12:
                    resolvedName = "Find My / AirTag"
                    vendorCategory = "Tracker"
                default:
                    if rawName.isEmpty { resolvedName = "Apple Device" }
                }
            }

            // Govee Manufacturer Data Decoding (e.g. H5074, H5075, H5101, H70B3, H70B5)
            if compId == 0xEC88 || compId == 0x0001 || rawName.lowercased().starts(with: "govee") {
                family = "Govee"
                vendorName = "Govee (Intellirocks)"
                vendorCategory = "Smart Lighting / Sensor"

                // Govee Thermometers often broadcast 3 bytes: 24-bit encoded temp & hum
                if mfg.count >= 7 {
                    // Check standard Govee thermometer format
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
                            if mfg.count >= 7 { bat = mfg[6] }
                        }
                    }
                }
            }

            // Qingping Manufacturer ID (0x088B)
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

        // 2. Service Data Parsing (Qingping 0xFDCD, BTHome 0xFCD2, Xiaomi 0xFE95, SwitchBot 0xFD3D)
        if let sData = serviceData {
            for (uuid, data) in sData {
                let uStr = uuid.uuidString.uppercased()
                serviceDataMap[uStr] = data.map { String(format: "%02X", $0) }.joined()

                // Qingping
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

                    // Decode TLV
                    var offset = 8
                    while offset + 1 < data.count {
                        let tag = data[offset]
                        let len = Int(data[offset + 1])
                        offset += 2
                        guard offset + len <= data.count else { break }
                        let chunk = data.subdata(in: offset..<(offset + len))
                        offset += len

                        if tag == 0x01 && chunk.count >= 4 {
                            let rT = Int16(bitPattern: UInt16(chunk[0]) | (UInt16(chunk[1]) << 8))
                            temp = Double(rT) / 10.0
                            let rH = UInt16(chunk[2]) | (UInt16(chunk[3]) << 8)
                            hum = Double(rH) / 10.0
                        } else if (tag == 0x02 || tag == 0x11) && chunk.count >= 1 {
                            bat = chunk[0]
                        } else if tag == 0x07 && chunk.count >= 2 {
                            let rP = UInt16(chunk[0]) | (UInt16(chunk[1]) << 8)
                            press = Double(rP) / 10.0
                        }
                    }
                } else if uStr.contains("FCD2") && data.count >= 3 {
                    // BTHome V2
                    family = "BTHome"
                    vendorCategory = "Smart Sensor (BTHome)"
                    var off = 1
                    while off < data.count {
                        let objId = data[off]
                        off += 1
                        switch objId {
                        case 0x01:
                            if off < data.count { bat = data[off]; off += 1 }
                        case 0x02:
                            if off + 1 < data.count {
                                let r = Int16(bitPattern: UInt16(data[off]) | (UInt16(data[off + 1]) << 8))
                                temp = Double(r) * 0.01
                                off += 2
                            }
                        case 0x03:
                            if off + 1 < data.count {
                                let r = UInt16(data[off]) | (UInt16(data[off + 1]) << 8)
                                hum = Double(r) * 0.01
                                off += 2
                            }
                        case 0x04:
                            if off + 2 < data.count {
                                let r = UInt32(data[off]) | (UInt32(data[off + 1]) << 8) | (UInt32(data[off + 2]) << 16)
                                press = Double(r) * 0.01
                                off += 3
                            }
                        default:
                            off += 1
                        }
                    }
                } else if uStr.contains("FE95") {
                    // Xiaomi MiBeacon
                    family = "Xiaomi Mijia"
                    vendorName = "Xiaomi"
                    vendorCategory = "Smart Home Sensor"
                    if rawName.isEmpty { resolvedName = "Xiaomi Sensor" }
                } else if uStr.contains("FD3D") {
                    // SwitchBot
                    family = "SwitchBot"
                    vendorName = "SwitchBot"
                    vendorCategory = "Smart Home Automation"
                }
            }
        }

        // 3. Name-based heuristics for popular IoT ecosystems
        let lowName = rawName.lowercased()
        if lowName.starts(with: "shelly") || lowName.contains("blu") {
            family = "Shelly"
            vendorName = "Allterco (Shelly)"
            if lowName.contains("plug") {
                vendorCategory = "Smart Plug / Meter"
            } else if lowName.contains("plus1") || lowName.contains("plus") {
                vendorCategory = "Smart Relay / Switch"
            } else {
                vendorCategory = "Smart Home / BLU"
            }
        } else if lowName.starts(with: "nuki_") || lowName.contains("nuki") {
            family = "Nuki"
            vendorName = "Nuki Home Solutions"
            vendorCategory = "Smart Lock"
            resolvedName = "Nuki Smart Lock (\(rawName))"
        } else if lowName.starts(with: "ef-") || lowName.contains("ecoflow") {
            family = "EcoFlow"
            vendorName = "EcoFlow Inc."
            vendorCategory = "Power Station / Inverter"
            resolvedName = "EcoFlow Device (\(rawName))"
        } else if lowName.starts(with: "govee_h70b5") {
            resolvedName = "Govee Permanent Outdoor Lights (H70B5)"
        } else if lowName.starts(with: "govee_h70b3") {
            resolvedName = "Govee Outdoor String Lights (H70B3)"
        } else if lowName.starts(with: "homepod") {
            family = "Apple"
            vendorName = "Apple Inc."
            vendorCategory = "Smart Speaker / Thread Border Router"
        }

        let deviceKey = hardwareMac ?? uuidStr
        let isNewDevice = devices[deviceKey] == nil

        if var existing = devices[deviceKey] {
            existing.rssi = rssiVal
            existing.packetCount += 1
            existing.lastSeen = Date()
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

    func finishAndPrintReport() {
        manager.stopScan()
        print("\n\u{001B}[32m[✓] Scan finished. Generating Environment Analysis Report...\u{001B}[0m\n")

        print("=========================================================================================================")
        print("                     mHomeNode BLE ENVIRONMENT ANALYSIS REPORT (macOS)                                   ")
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

                print("  • \(idStr.padding(toLength: 22, withPad: " ", startingAt: 0)) | \(nameStr.padding(toLength: 35, withPad: " ", startingAt: 0)) | \(String(format: "%4d dBm", d.rssi)) | \(metrics)")

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

        print("=========================================================================================================")
        exit(0)
    }
}

// Parse command line arguments
var duration: TimeInterval = 12.0 // Default to 12s scan for report
var verbose = false

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

let scanner = AdvancedCLIBleScanner(duration: duration, verbose: verbose)
RunLoop.main.run()
