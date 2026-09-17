import XCTest
@testable import mHomeNode

final class GoveeCommandTests: XCTestCase {
    func testPowerOnPacket() {
        let packet = GoveeCommand.power(isOn: true)
        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet[0], 0x33)
        XCTAssertEqual(packet[1], 0x01)
        XCTAssertEqual(packet[2], 0x01)
        for i in 3..<19 {
            XCTAssertEqual(packet[i], 0x00)
        }
        // 0x33 ^ 0x01 ^ 0x01 = 0x33
        XCTAssertEqual(packet[19], 0x33)
    }

    func testPowerOffPacket() {
        let packet = GoveeCommand.power(isOn: false)
        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet[0], 0x33)
        XCTAssertEqual(packet[1], 0x01)
        XCTAssertEqual(packet[2], 0x00)
        for i in 3..<19 {
            XCTAssertEqual(packet[i], 0x00)
        }
        // 0x33 ^ 0x01 ^ 0x00 = 0x32
        XCTAssertEqual(packet[19], 0x32)
    }

    func testBrightnessPacket() {
        let packet = GoveeCommand.brightness(percent: 100)
        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet[0], 0x33)
        XCTAssertEqual(packet[1], 0x04)
        XCTAssertEqual(packet[2], 100) // 0x64
        // 0x33 ^ 0x04 ^ 0x64
        let expectedChecksum: UInt8 = 0x33 ^ 0x04 ^ 100
        XCTAssertEqual(packet[19], expectedChecksum)
    }

    func testColorPacket() {
        let packet = GoveeCommand.color(red: 255, green: 128, blue: 64)
        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet[0], 0x33)
        XCTAssertEqual(packet[1], 0x05)
        XCTAssertEqual(packet[2], 0x02)
        XCTAssertEqual(packet[3], 255)
        XCTAssertEqual(packet[4], 128)
        XCTAssertEqual(packet[5], 64)
        let expectedChecksum: UInt8 = 0x33 ^ 0x05 ^ 0x02 ^ 255 ^ 128 ^ 64
        XCTAssertEqual(packet[19], expectedChecksum)
    }
}
