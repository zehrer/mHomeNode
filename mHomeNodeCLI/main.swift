import Foundation
import CoreBluetooth

// MARK: - mHomeNode CLI - Native macOS BLE Scanner & Decoder
// Scans for nearby BLE devices, decodes Qingping & BTHome sensors, and reports to stdout.

struct DiscoveredCLIItem {
    let identifier: String
    var name: String
    var family: String
    var rssi: Int
    var mac: String?
    var temperature: Double?
    var humidity: Double?
    var battery: UInt8?
    var pressure: Double?
    var lastSeen: Date
    var packetCount: Int
}

final class CLIBleScanner: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager!
    private var devices: [String: DiscoveredCLIItem] = [:]
    private let serverURL = URL(string: "http://127.0.0.1:8080/api/v1/mobile/ble")
    private var lastRenderTime = Date()

    override init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("\u{001B}[32m[+] Bluetooth Powered On. Starting continuous BLE scan...\u{001B}[0m")
            print("Listening for BTHome (0xFCD2), Qingping (0xFDCD), and standard BLE broadcasts...")
            print("Press Ctrl+C to exit.\n")
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        case .unauthorized:
            print("\u{001B}[31m[-] Bluetooth Permission Denied. Please allow Terminal/IDE Bluetooth access in macOS System Settings.\u{001B}[0m")
            exit(1)
        case .poweredOff:
            print("\u{001B}[33m[!] Bluetooth is turned off. Please turn it on in macOS Control Center.\u{001B}[0m")
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

        var family = "BLE"
        var temp: Double?
        var hum: Double?
        var bat: UInt8?
        var press: Double?
        var hardwareMac: String?
        var resolvedName = rawName.isEmpty ? "Unknown" : rawName

        // 1. Decode Qingping (0xFDCD)
        if let serviceData = serviceData {
            for (uuid, data) in serviceData {
                let u = uuid.uuidString.uppercased()
                if u.contains("FDCD") && data.count >= 8 {
                    family = "Qingping"
                    let prodId = data[1]
                    switch prodId {
                    case 0x01: resolvedName = "Qingping CGG1"
                    case 0x07: resolvedName = "Qingping CGG1-M"
                    case 0x0C: resolvedName = "Qingping CGD1"
                    case 0x10: resolvedName = "Qingping CGDK2"
                    case 0x09: resolvedName = "Qingping CGP1W"
                    default: resolvedName = "Qingping (0x\(String(format: "%02X", prodId)))"
                    }

                    let macSlice = Array(data[2...7].reversed())
                    hardwareMac = macSlice.map { String(format: "%02X", $0) }.joined(separator: ":")

                    // Parse TLV
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

                    // Fallback fixed format
                    if temp == nil && data.count >= 14 {
                        let rT = Int16(bitPattern: UInt16(data[10]) | (UInt16(data[11]) << 8))
                        if rT >= -400 && rT <= 850 { temp = Double(rT) / 10.0 }
                        let rH = UInt16(data[12]) | (UInt16(data[13]) << 8)
                        if rH <= 1000 { hum = Double(rH) / 10.0 }
                        if data.count >= 17 { bat = data[16] }
                        else if data.count >= 15 { bat = data[14] }
                    }
                } else if u.contains("FCD2") && data.count >= 3 {
                    // 2. Decode BTHome V2
                    family = "BTHome"
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
                }
            }
        }

        let lowName = rawName.lowercased()
        if lowName.starts(with: "shelly") || lowName.contains("blu") {
            family = "Shelly BLU"
        }

        let key = hardwareMac ?? uuidStr
        if var existing = devices[key] {
            existing.rssi = rssiVal
            existing.packetCount += 1
            existing.lastSeen = Date()
            if resolvedName != "Unknown" && (existing.name == "Unknown" || existing.name.isEmpty) {
                existing.name = resolvedName
            }
            if family != "BLE" { existing.family = family }
            if let t = temp { existing.temperature = t }
            if let h = hum { existing.humidity = h }
            if let b = bat { existing.battery = b }
            if let p = press { existing.pressure = p }
            devices[key] = existing
        } else {
            let item = DiscoveredCLIItem(
                identifier: key,
                name: resolvedName,
                family: family,
                rssi: rssiVal,
                mac: hardwareMac,
                temperature: temp,
                humidity: hum,
                battery: bat,
                pressure: press,
                lastSeen: Date(),
                packetCount: 1
            )
            devices[key] = item
        }

        // Throttle rendering to at most twice per second
        if Date().timeIntervalSince(lastRenderTime) > 0.5 {
            renderTable()
            lastRenderTime = Date()
        }
    }

    private func pad(_ str: String, _ length: Int) -> String {
        if str.count >= length {
            return String(str.prefix(length))
        }
        return str + String(repeating: " ", count: length - str.count)
    }

    private func renderTable() {
        // Clear terminal screen and reset cursor
        print("\u{001B}[2J\u{001B}[H", terminator: "")

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())

        print("==================================================================================================")
        print(" mHomeNode CLI - Local BLE Environment Monitor (\(timeStr)) - Total Devices: \(devices.count)")
        print("==================================================================================================")
        print(pad("Identifier / MAC", 19) + " | " + pad("Device Name", 24) + " | " + pad("Family", 12) + " | " + pad("RSSI", 8) + " | " + pad("Temp", 7) + " | " + pad("Hum", 6) + " | " + pad("Bat", 5) + " | Packets")
        print("--------------------------------------------------------------------------------------------------")

        // Sort by RSSI descending
        let sorted = devices.values.sorted {
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.identifier < $1.identifier
        }

        for d in sorted {
            let tempStr = d.temperature.map { String(format: "%.1f°C", $0) } ?? "--"
            let humStr = d.humidity.map { String(format: "%.0f%%", $0) } ?? "--"
            let batStr = d.battery.map { "\($0)%" } ?? "--"
            let rssiStr = pad("\(d.rssi) dBm", 8)
            let pktStr = pad("\(d.packetCount)", 7)

            let row = pad(d.identifier, 19) + " | " +
                      pad(d.name, 24) + " | " +
                      pad(d.family, 12) + " | " +
                      rssiStr + " | " +
                      pad(tempStr, 7) + " | " +
                      pad(humStr, 6) + " | " +
                      pad(batStr, 5) + " | " +
                      pktStr
            print(row)
        }
        print("==================================================================================================")
        print("Listening... (Press Ctrl+C to terminate)")
    }
}

let scanner = CLIBleScanner()
RunLoop.main.run()
