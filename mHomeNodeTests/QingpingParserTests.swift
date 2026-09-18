import XCTest
@testable import mHomeNode

final class QingpingParserTests: XCTestCase {

    func testParseTLVPayload() {
        // Sample Qingping TLV packet
        // Byte 0: 0x08 (flags)
        // Byte 1: 0x01 (Product: CGG1)
        // Bytes 2..7: MAC address (reverse order: 12 34 56 78 9A BC) -> BC:9A:78:56:34:12
        // TLV 1: Tag 0x01 (Temp & Humidity), Len 4, Temp 215 (21.5 °C: 0xD7, 0x00), Humidity 482 (48.2 %: 0xE2, 0x01)
        // TLV 2: Tag 0x02 (Battery), Len 1, Value 85% (0x55)
        let bytes: [UInt8] = [
            0x08, 0x01,
            0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC,
            0x01, 0x04, 0xD7, 0x00, 0xE2, 0x01,
            0x02, 0x01, 0x55
        ]
        let data = Data(bytes)

        let parsed = QingpingParser.parse(data: data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.productId, 0x01)
        XCTAssertEqual(parsed?.modelName, "Qingping Temp & RH (CGG1)")
        XCTAssertEqual(parsed?.macAddress, "BC:9A:78:56:34:12")
        XCTAssertEqual(parsed?.temperature, 21.5)
        XCTAssertEqual(parsed?.humidity, 48.2)
        XCTAssertEqual(parsed?.battery, 85)

        let btHome = parsed?.toBTHomeData()
        XCTAssertNotNil(btHome)
        XCTAssertEqual(btHome?.temperature, 21.5)
        XCTAssertEqual(btHome?.humidity, 48.2)
        XCTAssertEqual(btHome?.battery, 85)
    }

    func testParseFixedFormatPayload() {
        // 17-byte fixed format broadcast for CGDK2 (Product ID 0x10)
        // Bytes 0-1: 0x04, 0x10 (CGDK2)
        // Bytes 2-7: MAC: 11 22 33 44 55 66 -> 66:55:44:33:22:11
        // Bytes 8-9: 0x00, 0x00
        // Bytes 10-11: Temp 23.4 °C (234 = 0xEA, 0x00)
        // Bytes 12-13: Humidity 55.0 % (550 = 0x26, 0x02)
        // Bytes 14-15: 0x00, 0x00
        // Byte 16: Battery 92% (0x5C)
        let bytes: [UInt8] = [
            0x04, 0x10,
            0x11, 0x22, 0x33, 0x44, 0x55, 0x66,
            0x00, 0x00,
            0xEA, 0x00,
            0x26, 0x02,
            0x00, 0x00,
            0x5C
        ]
        let data = Data(bytes)

        let parsed = QingpingParser.parse(data: data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.productId, 0x10)
        XCTAssertEqual(parsed?.modelName, "Qingping Temp & RH Lite (CGDK2)")
        XCTAssertEqual(parsed?.macAddress, "66:55:44:33:22:11")
        XCTAssertEqual(parsed?.temperature, 23.4)
        XCTAssertEqual(parsed?.humidity, 55.0)
        XCTAssertEqual(parsed?.battery, 92)
    }

    func testParseInsufficientDataReturnsNil() {
        let shortData = Data([0x08, 0x01, 0x02])
        XCTAssertNil(QingpingParser.parse(data: shortData))
    }
}
