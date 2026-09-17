import XCTest
@testable import mHomeNode

final class BTHomeParserTests: XCTestCase {

    func testParseBTHomeV2TemperatureAndHumidity() {
        let bytes: [UInt8] = [
            0x40,               // Header (V2, Plaintext)
            0x02, 0x66, 0x08,   // Temp = 21.50 °C
            0x03, 0x18, 0x15,   // Humidity = 54.00 %
            0x01, 0x62          // Battery = 98%
        ]
        let data = Data(bytes)

        let parsed = BTHomeParser.parseV2(data: data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.version, 2)
        XCTAssertFalse(parsed?.isEncrypted ?? true)
        XCTAssertEqual(parsed?.battery, 98)

        if let temp = parsed?.temperature {
            XCTAssertEqual(temp, 21.50, accuracy: 0.01)
        } else {
            XCTFail("Temperature should not be nil")
        }

        if let hum = parsed?.humidity {
            XCTAssertEqual(hum, 54.00, accuracy: 0.01)
        } else {
            XCTFail("Humidity should not be nil")
        }
    }

    func testParseBTHomeV2DoorAndButtonEvent() {
        let bytes: [UInt8] = [
            0x40,
            0x1A, 0x01,
            0x3A, 0x01
        ]
        let data = Data(bytes)

        let parsed = BTHomeParser.parseV2(data: data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.isDoorOpen, true)
        XCTAssertEqual(parsed?.buttonEvent, .press)
    }

    func testParseBTHomeEncryptedFlag() {
        let bytes: [UInt8] = [0x41, 0x00, 0x01, 0x02]
        let data = Data(bytes)

        let parsed = BTHomeParser.parseV2(data: data)
        XCTAssertNotNil(parsed)
        XCTAssertTrue(parsed?.isEncrypted ?? false)
    }
}
