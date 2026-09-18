import Foundation

/// Decodes Xiaomi MiBeacon BLE advertisement payloads (Service Data UUID 0xFE95).
/// Supports classic Xiaomi Mijia sensors (e.g. LYWSDCGQ/01ZM, LYWSD02, LYWSD03MMC, Flower Care, CGDK2, CGD1).
public struct MiBeaconData: Sendable, Equatable {
    public let productId: UInt16
    public let modelName: String
    public let macAddress: String?
    public var temperature: Double?      // °C
    public var humidity: Double?         // %
    public var battery: UInt8?           // 0-100%
    public var illuminance: Double?      // lux
    public var soilMoisture: UInt8?      // %
    public var soilConductivity: UInt16? // µS/cm
    public var isEncrypted: Bool

    public init(
        productId: UInt16,
        modelName: String,
        macAddress: String?,
        temperature: Double? = nil,
        humidity: Double? = nil,
        battery: UInt8? = nil,
        illuminance: Double? = nil,
        soilMoisture: UInt8? = nil,
        soilConductivity: UInt16? = nil,
        isEncrypted: Bool = false
    ) {
        self.productId = productId
        self.modelName = modelName
        self.macAddress = macAddress
        self.temperature = temperature
        self.humidity = humidity
        self.battery = battery
        self.illuminance = illuminance
        self.soilMoisture = soilMoisture
        self.soilConductivity = soilConductivity
        self.isEncrypted = isEncrypted
    }

    /// Converts MiBeacon telemetry into standard BTHomeData for unified rendering across Climate & Room views
    public func toBTHomeData() -> BTHomeData {
        var raw: [String: Double] = [:]
        if let t = temperature { raw["temperature"] = t }
        if let h = humidity { raw["humidity"] = h }
        if let b = battery { raw["battery"] = Double(b) }
        if let l = illuminance { raw["illuminance"] = l }
        if let sm = soilMoisture { raw["moisture"] = Double(sm) }
        if let sc = soilConductivity { raw["conductivity"] = Double(sc) }

        return BTHomeData(
            version: 2,
            isEncrypted: isEncrypted,
            battery: battery,
            temperature: temperature,
            humidity: humidity,
            pressure: nil,
            illuminance: illuminance,
            rawMeasurements: raw
        )
    }
}

public enum MiBeaconParser {
    public static let serviceUUID = "FE95"

    public static func modelName(for productId: UInt16) -> String {
        switch productId {
        case 0x01AA: return "Xiaomi Mijia Temp & RH (LYWSDCGQ)"
        case 0x045B: return "Xiaomi E-Ink Clock (LYWSD02)"
        case 0x055B: return "Xiaomi Mijia Square Temp & RH (LYWSD03MMC)"
        case 0x0347: return "Qingping Temp & RH (CGG1)"
        case 0x0576: return "Qingping Alarm Clock (CGD1)"
        case 0x066F: return "Qingping Temp & RH Lite (CGDK2)"
        case 0x0387: return "Miaomiaoce E-Ink Temp & RH (MHO-C401)"
        case 0x0098: return "Xiaomi Flower Care (HHCCJCY01)"
        case 0x015D: return "Xiaomi Flower Pot (HHCCPOT002)"
        case 0x02DF: return "Xiaomi Air Quality Monitor (JQJCY01YM)"
        case 0x00DB: return "Xiaomi MMC-T201-1 Thermometer"
        case 0x07F6: return "Xiaomi Night Light 2 (MJYD02YL)"
        default: return "Xiaomi Mijia Device (0x\(String(format: "%04X", productId)))"
        }
    }

    /// Parses Xiaomi MiBeacon advertisement Service Data for 0xFE95
    public static func parse(data: Data) -> MiBeaconData? {
        // Minimum header: Frame Control (2), Product ID (2), Counter (1) = 5 bytes
        guard data.count >= 5 else { return nil }

        let frctrl = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let isEncrypted = ((frctrl >> 3) & 1) != 0
        let macInclude = ((frctrl >> 4) & 1) != 0
        let capabilityInclude = ((frctrl >> 5) & 1) != 0
        let objectInclude = ((frctrl >> 6) & 1) != 0

        let productId = UInt16(data[2]) | (UInt16(data[3]) << 8)
        let model = modelName(for: productId)

        var offset = 5
        var macStr: String?

        // Extract 6-byte MAC address if present (stored in reverse byte order)
        if macInclude {
            guard data.count >= offset + 6 else { return nil }
            let macSlice = Array(data[offset..<(offset + 6)].reversed())
            macStr = macSlice.map { String(format: "%02X", $0) }.joined(separator: ":")
            offset += 6
        }

        // Skip capability bytes if present
        if capabilityInclude {
            guard data.count >= offset + 1 else { return nil }
            let cap = data[offset]
            offset += 1
            if (cap & 0x20) != 0 {
                // Extended capability byte
                guard data.count >= offset + 1 else { return nil }
                offset += 1
            }
        }

        var temperature: Double?
        var humidity: Double?
        var battery: UInt8?
        var illuminance: Double?
        var moisture: UInt8?
        var conductivity: UInt16?

        // Parse sensor telemetry objects if unencrypted payload is present
        if objectInclude && !isEncrypted {
            while offset + 3 <= data.count {
                let objType = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                let objLen = Int(data[offset + 2])
                offset += 3

                guard offset + objLen <= data.count else { break }
                let chunk = data.subdata(in: offset..<(offset + objLen))
                offset += objLen

                switch objType {
                case 0x1004: // Temperature: 2 bytes signed Int16 LE / 10.0 (°C)
                    if chunk.count >= 2 {
                        let raw = Int16(bitPattern: UInt16(chunk[0]) | (UInt16(chunk[1]) << 8))
                        temperature = Double(raw) / 10.0
                    }

                case 0x1006: // Humidity: 2 bytes unsigned UInt16 LE / 10.0 (%)
                    if chunk.count >= 2 {
                        let raw = UInt16(chunk[0]) | (UInt16(chunk[1]) << 8)
                        humidity = Double(raw) / 10.0
                    }

                case 0x100A: // Battery percentage: 1 byte UInt8 (0-100%)
                    if chunk.count >= 1 && chunk[0] <= 100 {
                        battery = chunk[0]
                    }

                case 0x100D: // Temperature and Humidity combined (4 bytes)
                    if chunk.count >= 4 {
                        let rawTemp = Int16(bitPattern: UInt16(chunk[0]) | (UInt16(chunk[1]) << 8))
                        let rawHum = UInt16(chunk[2]) | (UInt16(chunk[3]) << 8)
                        temperature = Double(rawTemp) / 10.0
                        humidity = Double(rawHum) / 10.0
                    }

                case 0x1007: // Illuminance: 3 bytes unsigned LE (lux)
                    if chunk.count >= 3 {
                        let rawLux = UInt32(chunk[0]) | (UInt32(chunk[1]) << 8) | (UInt32(chunk[2]) << 16)
                        illuminance = Double(rawLux)
                    }

                case 0x1008: // Soil moisture: 1 byte (0-100%)
                    if chunk.count >= 1 {
                        moisture = chunk[0]
                    }

                case 0x1009: // Soil conductivity: 2 bytes UInt16 LE (µS/cm)
                    if chunk.count >= 2 {
                        conductivity = UInt16(chunk[0]) | (UInt16(chunk[1]) << 8)
                    }

                default:
                    break
                }
            }
        }

        return MiBeaconData(
            productId: productId,
            modelName: model,
            macAddress: macStr,
            temperature: temperature,
            humidity: humidity,
            battery: battery,
            illuminance: illuminance,
            soilMoisture: moisture,
            soilConductivity: conductivity,
            isEncrypted: isEncrypted
        )
    }
}
