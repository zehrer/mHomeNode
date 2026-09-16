import Foundation

/// Decoder for BTHome V1 & V2 BLE advertisement payloads
/// Standard reference: https://bthome.io/format/
public enum BTHomeParser {
    public static let bthomeV2ServiceUUID = "FCD2"
    public static let bthomeV1TempUUID = "181C"
    public static let bthomeV1BondUUID = "181E"

    /// Parses BTHome V2 advertisement payload (Service Data for UUID 0xFCD2)
    public static func parseV2(data: Data) -> BTHomeData? {
        guard data.count >= 1 else { return nil }

        let header = data[0]
        let isEncrypted = (header & 0x01) != 0
        let version = Int((header >> 5) & 0x07)

        var result = BTHomeData(
            version: version == 0 ? 2 : version,
            isEncrypted: isEncrypted
        )

        // Encrypted payloads require AES-CCM decryption with pre-shared bind key
        if isEncrypted {
            return result
        }

        var offset = 1
        while offset < data.count {
            let objectId = data[offset]
            offset += 1

            switch objectId {
            case 0x00: // Packet ID (1 byte)
                guard offset < data.count else { break }
                result.packetId = data[offset]
                offset += 1

            case 0x01: // Battery % (1 byte, factor 1)
                guard offset < data.count else { break }
                result.battery = data[offset]
                result.rawMeasurements["battery"] = Double(data[offset])
                offset += 1

            case 0x02: // Temperature (2 bytes sint16 LE, factor 0.01)
                guard offset + 1 < data.count else { break }
                let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                let temp = Double(raw) * 0.01
                result.temperature = temp
                result.rawMeasurements["temperature"] = temp
                offset += 2

            case 0x03: // Humidity (2 bytes uint16 LE, factor 0.01)
                guard offset + 1 < data.count else { break }
                let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                let hum = Double(raw) * 0.01
                result.humidity = hum
                result.rawMeasurements["humidity"] = hum
                offset += 2

            case 0x04: // Pressure (3 bytes uint24 LE, factor 0.01 hPa)
                guard offset + 2 < data.count else { break }
                let raw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
                let press = Double(raw) * 0.01
                result.pressure = press
                result.rawMeasurements["pressure"] = press
                offset += 3

            case 0x05: // Illuminance (3 bytes uint24 LE, factor 0.01 lux)
                guard offset + 2 < data.count else { break }
                let raw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
                let lux = Double(raw) * 0.01
                result.illuminance = lux
                result.rawMeasurements["illuminance"] = lux
                offset += 3

            case 0x0F: // Generic Boolean (1 byte)
                guard offset < data.count else { break }
                let val = data[offset] != 0
                result.genericBoolean = val
                result.rawMeasurements["generic"] = val ? 1.0 : 0.0
                offset += 1

            case 0x1A: // Door / Window Sensor (1 byte, 0 = closed, 1 = open)
                guard offset < data.count else { break }
                let isOpen = data[offset] == 1
                result.isDoorOpen = isOpen
                result.rawMeasurements["door_open"] = isOpen ? 1.0 : 0.0
                offset += 1

            case 0x21: // Motion (1 byte, 0 = clear, 1 = motion detected)
                guard offset < data.count else { break }
                let motion = data[offset] == 1
                result.isMotionDetected = motion
                result.rawMeasurements["motion"] = motion ? 1.0 : 0.0
                offset += 1

            case 0x2E: // Humidity (1 byte uint8, factor 1 %)
                guard offset < data.count else { break }
                let hum = Double(data[offset])
                result.humidity = hum
                result.rawMeasurements["humidity"] = hum
                offset += 1

            case 0x3A: // Button press event (1 byte)
                guard offset < data.count else { break }
                let code = data[offset]
                result.buttonEvent = ButtonPressEvent.from(code: code)
                result.rawMeasurements["button_event"] = Double(code)
                offset += 1

            case 0x3F: // Rotation (2 bytes sint16 LE, factor 0.1 deg)
                guard offset + 1 < data.count else { break }
                let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                let rot = Double(raw) * 0.1
                result.rotation = rot
                result.rawMeasurements["rotation"] = rot
                offset += 2

            case 0x45: // Temperature (2 bytes sint16 LE, factor 0.1 °C)
                guard offset + 1 < data.count else { break }
                let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                let temp = Double(raw) * 0.1
                result.temperature = temp
                result.rawMeasurements["temperature"] = temp
                offset += 2

            default:
                // Unknown object ID - cannot reliably determine length without schema
                return result
            }
        }

        return result
    }
}
