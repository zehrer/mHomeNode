import Foundation

/// Decodes Qingping BLE advertisement payloads (Service Data UUID 0xFDCD)
/// Supports CGG1, CGDK2, CGD1, CGP1W, CGPR1 room thermometers and multi-sensors.
public struct QingpingData: Sendable, Equatable {
    public let productId: UInt8
    public let modelName: String
    public let macAddress: String
    public var temperature: Double?      // °C
    public var humidity: Double?         // %
    public var battery: UInt8?           // 0-100%
    public var pressure: Double?         // hPa
    public var illuminance: Double?      // lux

    public init(
        productId: UInt8,
        modelName: String,
        macAddress: String,
        temperature: Double? = nil,
        humidity: Double? = nil,
        battery: UInt8? = nil,
        pressure: Double? = nil,
        illuminance: Double? = nil
    ) {
        self.productId = productId
        self.modelName = modelName
        self.macAddress = macAddress
        self.temperature = temperature
        self.humidity = humidity
        self.battery = battery
        self.pressure = pressure
        self.illuminance = illuminance
    }

    /// Converts Qingping telemetry into standard BTHomeData for unified rendering
    public func toBTHomeData() -> BTHomeData {
        var raw: [String: Double] = [:]
        if let t = temperature { raw["temperature"] = t }
        if let h = humidity { raw["humidity"] = h }
        if let b = battery { raw["battery"] = Double(b) }
        if let p = pressure { raw["pressure"] = p }
        if let l = illuminance { raw["illuminance"] = l }

        return BTHomeData(
            version: 2,
            isEncrypted: false,
            battery: battery,
            temperature: temperature,
            humidity: humidity,
            pressure: pressure,
            illuminance: illuminance,
            rawMeasurements: raw
        )
    }
}

public enum QingpingParser {
    public static let serviceUUID = "FDCD"

    public static func modelName(for productId: UInt8) -> String {
        switch productId {
        case 0x01: return "Qingping Temp & RH (CGG1)"
        case 0x07: return "Qingping Temp & RH E-Ink (CGG1-M)"
        case 0x09: return "Qingping Temp, RH & Pressure (CGP1W)"
        case 0x0C: return "Qingping Alarm Clock (CGD1)"
        case 0x10: return "Qingping Temp & RH Lite (CGDK2)"
        case 0x12: return "Qingping Motion & Light (CGPR1)"
        default: return "Qingping Sensor (0x\(String(format: "%02X", productId)))"
        }
    }

    /// Parses Service Data payload for 0xFDCD
    public static func parse(data: Data) -> QingpingData? {
        // Minimum header: Frame control (1), Product ID (1), MAC Address (6) = 8 bytes
        guard data.count >= 8 else { return nil }

        let productId = data[1]
        let model = modelName(for: productId)

        // MAC address is stored in reverse byte order at bytes 2...7
        let macSlice = Array(data[2...7].reversed())
        let macStr = macSlice.map { String(format: "%02X", $0) }.joined(separator: ":")

        var parsed = QingpingData(
            productId: productId,
            modelName: model,
            macAddress: macStr
        )

        // Attempt TLV parsing starting at offset 8
        var offset = 8

        while offset + 1 < data.count {
            let tag = data[offset]
            let len = Int(data[offset + 1])
            offset += 2

            guard offset + len <= data.count else { break }
            let chunk = data.subdata(in: offset..<(offset + len))
            offset += len

            switch tag {
            case 0x01: // Temperature (2 bytes sint16 LE, 0.1°C) & Humidity (2 bytes uint16 LE, 0.1%)
                if chunk.count >= 4 {
                    let rawTemp = Int16(bitPattern: UInt16(chunk[0]) | (UInt16(chunk[1]) << 8))
                    parsed.temperature = Double(rawTemp) / 10.0
                    let rawHum = UInt16(chunk[2]) | (UInt16(chunk[3]) << 8)
                    parsed.humidity = Double(rawHum) / 10.0
                }
            case 0x02: // Battery percentage (1 byte, 0-100%)
                if chunk.count >= 1 && chunk[0] <= 100 {
                    parsed.battery = chunk[0]
                }
            case 0x07: // Pressure (2 bytes uint16 LE, 0.1 hPa)
                if chunk.count >= 2 {
                    let rawPress = UInt16(chunk[0]) | (UInt16(chunk[1]) << 8)
                    parsed.pressure = Double(rawPress) / 10.0
                }
            case 0x08: // Motion & Light (4 bytes)
                if chunk.count >= 4 {
                    let rawLux = UInt16(chunk[2]) | (UInt16(chunk[3]) << 8)
                    parsed.illuminance = Double(rawLux)
                }
            case 0x11: // Secondary battery tag (1 byte, 0-100%)
                if chunk.count >= 1 && chunk[0] <= 100 {
                    parsed.battery = chunk[0]
                }
            default:
                break
            }
        }

        // Fallback for fixed format packets without TLV header (e.g. standard 14..17 bytes broadcast)
        if parsed.temperature == nil && data.count >= 14 {
            let rawTemp = Int16(bitPattern: UInt16(data[10]) | (UInt16(data[11]) << 8))
            // Sanity check: valid room temperature (-40°C to +85°C)
            if rawTemp >= -400 && rawTemp <= 850 {
                parsed.temperature = Double(rawTemp) / 10.0
            }

            let rawHum = UInt16(data[12]) | (UInt16(data[13]) << 8)
            // Sanity check: humidity 0..100%
            if rawHum <= 1000 {
                parsed.humidity = Double(rawHum) / 10.0
            }

            if data.count >= 17 && data[16] <= 100 {
                parsed.battery = data[16]
            } else if data.count >= 15 && data[14] <= 100 {
                parsed.battery = data[14]
            }
        }

        return parsed
    }
}
