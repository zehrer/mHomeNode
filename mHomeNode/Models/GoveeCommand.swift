import Foundation
import CoreBluetooth

/// Represents commands and GATT constants for Govee Bluetooth Low Energy smart lights.
public enum GoveeCommand: Sendable {
    /// Standard Govee Service UUID
    public static let serviceUUID = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D1910")

    /// Standard Govee Write Characteristic UUID
    public static let writeCharacteristicUUID = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D2B11")

    /// Standard Govee Notify Characteristic UUID
    public static let notifyCharacteristicUUID = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D2B10")

    /// Command header byte used by Govee for control packets
    public static let commandHeader: UInt8 = 0x33

    /// Calculates a 20-byte packet with the final byte set to the XOR checksum of bytes 0..18
    public static func buildPacket(opcode: UInt8, payload: [UInt8] = []) -> Data {
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = commandHeader
        packet[1] = opcode

        for (index, byte) in payload.enumerated() {
            let targetIdx = 2 + index
            if targetIdx < 19 {
                packet[targetIdx] = byte
            }
        }

        // Checksum: XOR of bytes 0 through 18
        var checksum: UInt8 = 0
        for i in 0..<19 {
            checksum ^= packet[i]
        }
        packet[19] = checksum

        return Data(packet)
    }

    /// Power ON or OFF packet
    /// On: [0x33, 0x01, 0x01, 0x00, ..., 0x33]
    /// Off: [0x33, 0x01, 0x00, 0x00, ..., 0x32]
    public static func power(isOn: Bool) -> Data {
        buildPacket(opcode: 0x01, payload: [isOn ? 0x01 : 0x00])
    }

    /// Brightness packet (0 to 100 percent)
    /// [0x33, 0x04, <percent>, 0x00, ..., <checksum>]
    public static func brightness(percent: Int) -> Data {
        let clamped = UInt8(clamping: max(0, min(100, percent)))
        return buildPacket(opcode: 0x04, payload: [clamped])
    }

    /// RGB Color packet
    /// [0x33, 0x05, 0x02, R, G, B, 0x00, ..., <checksum>]
    public static func color(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        buildPacket(opcode: 0x05, payload: [0x02, red, green, blue])
    }
}
