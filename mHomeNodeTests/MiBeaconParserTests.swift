import XCTest
@testable import mHomeNode

final class MiBeaconParserTests: XCTestCase {
    func testLYWSDCGQTemperatureAndHumidity() {
        // Frame Control: mac_include (bit 4), object_include (bit 6), version 2 -> 0b0010_0000_0101_0000 = 0x2050 -> LE: 50 20
        // Product ID: 0x01AA -> LE: AA 01
        // Counter: 0x1A
        // MAC: A4:C1:38:D1:D2:D3 (reversed: D3 D2 D1 38 C1 A4)
        // Object: 0x100D, len 4: Temp 22.4°C (224 = 0x00E0), Humidity 55.2% (552 = 0x0228)
        let rawBytes: [UInt8] = [
            0x50, 0x20,             // Frame Control
            0xAA, 0x01,             // Product ID: LYWSDCGQ
            0x1A,                   // Counter
            0xD3, 0xD2, 0xD1, 0x38, 0xC1, 0xA4, // MAC reversed
            0x0D, 0x10, 0x04,       // Object type 0x100D, len 4
            0xE0, 0x00,             // Temp = 224 (22.4°C)
            0x28, 0x02              // Humidity = 552 (55.2%)
        ]

        let data = Data(rawBytes)
        let parsed = MiBeaconParser.parse(data: data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.productId, 0x01AA)
        XCTAssertEqual(parsed?.modelName, "Xiaomi Mijia Temp & RH (LYWSDCGQ)")
        XCTAssertEqual(parsed?.macAddress, "A4:C1:38:D1:D2:D3")
        XCTAssertEqual(parsed?.temperature, 22.4)
        XCTAssertEqual(parsed?.humidity, 55.2)

        let btHome = parsed?.toBTHomeData()
        XCTAssertEqual(btHome?.temperature, 22.4)
        XCTAssertEqual(btHome?.humidity, 55.2)
    }

    func testLYWSDCGQBattery() {
        // Frame Control: mac_include, object_include -> 50 20
        // Product ID: 0x01AA
        // Counter: 0x2B
        // MAC: A4:C1:38:D1:D2:D3
        // Object: 0x100A, len 1: Battery 87% (0x57)
        let rawBytes: [UInt8] = [
            0x50, 0x20,
            0xAA, 0x01,
            0x2B,
            0xD3, 0xD2, 0xD1, 0x38, 0xC1, 0xA4,
            0x0A, 0x10, 0x01,
            0x57 // 87%
        ]

        let data = Data(rawBytes)
        let parsed = MiBeaconParser.parse(data: data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.productId, 0x01AA)
        XCTAssertEqual(parsed?.battery, 87)
    }

    func testCGDK2DiscoveryPacketWithoutObject() {
        // Real packet captured in environment: 30586F06022D5287342D5808
        // Product ID 0x066F = CGDK2, MAC: 58:2D:34:87:52:2D
        let rawBytes: [UInt8] = [
            0x30, 0x58,             // Frame Control (version 5, mac_include, capability_include, no object)
            0x6F, 0x06,             // Product ID 0x066F
            0x02,                   // Counter
            0x2D, 0x52, 0x87, 0x34, 0x2D, 0x58, // MAC reversed: 58:2D:34:87:52:2D
            0x08                    // Capability byte
        ]

        let data = Data(rawBytes)
        let parsed = MiBeaconParser.parse(data: data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.productId, 0x066F)
        XCTAssertEqual(parsed?.modelName, "Qingping Temp & RH Lite (CGDK2)")
        XCTAssertEqual(parsed?.macAddress, "58:2D:34:87:52:2D")
        XCTAssertNil(parsed?.temperature)
    }
}
