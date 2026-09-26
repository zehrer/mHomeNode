import XCTest
@testable import mHomeNode

final class BLEInspectorTests: XCTestCase {

    func testAppearanceCategoryMapping() {
        // Thermometer: 768 (0x0300) -> category 12
        let catThermo = DeviceInspectionInfo.category(for: 768)
        XCTAssertTrue(catThermo.contains("Thermometer"))

        // Light Fixture: 1408 (0x0580) -> category 22
        let catLight = DeviceInspectionInfo.category(for: 1408)
        XCTAssertTrue(catLight.contains("Light"))

        // Watch: 192 (0x00C0) -> category 3
        let catWatch = DeviceInspectionInfo.category(for: 192)
        XCTAssertEqual(catWatch, "Watch")

        // Computer: 128 (0x0080) -> category 2
        let catComp = DeviceInspectionInfo.category(for: 128)
        XCTAssertEqual(catComp, "Computer")

        // Heart Rate Sensor: 832 (0x0340) -> category 13
        let catHR = DeviceInspectionInfo.category(for: 832)
        XCTAssertEqual(catHR, "Heart Rate Sensor")

        // Keyring: 576 (0x0240) -> category 9
        let catKey = DeviceInspectionInfo.category(for: 576)
        XCTAssertTrue(catKey.contains("Keyring"))
    }

    func testInspectionInfoJSONRoundtrip() throws {
        let info = DeviceInspectionInfo(
            deviceName: "Philips Hue Go",
            manufacturerName: "Signify Netherlands B.V.",
            modelNumber: "7602031P7",
            serialNumber: "SN123456",
            firmwareRevision: "1.104.2",
            hardwareRevision: "HW2.0",
            softwareRevision: "SW3.4.1",
            appearance: 1408,
            appearanceCategory: "Light Fixture",
            batteryLevel: 85
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(info)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DeviceInspectionInfo.self, from: data)

        XCTAssertEqual(decoded.deviceName, "Philips Hue Go")
        XCTAssertEqual(decoded.manufacturerName, "Signify Netherlands B.V.")
        XCTAssertEqual(decoded.modelNumber, "7602031P7")
        XCTAssertEqual(decoded.firmwareRevision, "1.104.2")
        XCTAssertEqual(decoded.hardwareRevision, "HW2.0")
        XCTAssertEqual(decoded.softwareRevision, "SW3.4.1")
        XCTAssertEqual(decoded.appearance, 1408)
        XCTAssertEqual(decoded.batteryLevel, 85)
    }

    func testApplyInspectionInfoUpdatesDeviceNameAndFamily() {
        var dev = DiscoveredDevice(
            id: UUID(),
            name: "Unknown",
            rssi: -60,
            family: .standardBLE
        )

        let info = DeviceInspectionInfo(
            deviceName: "Smart Washer Ultra",
            manufacturerName: "Samsung Electronics",
            modelNumber: "WW90T",
            batteryLevel: 100
        )

        dev.applyInspectionInfo(info)

        XCTAssertEqual(dev.name, "Smart Washer Ultra")
        XCTAssertEqual(dev.family, .samsung)
        XCTAssertEqual(dev.btHomeData?.battery, 100)
    }

    func testApplyInspectionInfoFallbacksToModelWhenNameEmpty() {
        var dev = DiscoveredDevice(
            id: UUID(),
            name: "",
            rssi: -72,
            family: .standardBLE
        )

        let info = DeviceInspectionInfo(
            deviceName: nil,
            manufacturerName: "Apple Inc.",
            modelNumber: "MacBookPro18,1"
        )

        dev.applyInspectionInfo(info)

        XCTAssertEqual(dev.name, "MacBookPro18,1")
        XCTAssertEqual(dev.family, .apple)
    }

    func testGoveeIdentificationPreservesSuffix() {
        let h70b3_6190 = DeviceFingerprinter.identifyDetails(
            advertisedName: "Govee_H70B3_6190",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: Data([0x43, 0x88, 0xEC, 0x00, 0x02, 0x02, 0x00])
        )
        XCTAssertEqual(h70b3_6190.resolvedName, "Govee Outdoor String Lights (H70B3 6190)")
        XCTAssertEqual(h70b3_6190.family, .govee)
        XCTAssertEqual(h70b3_6190.goveePowerState, false)

        let h70b3_2b93 = DeviceFingerprinter.identifyDetails(
            advertisedName: "Govee_H70B3_2B93",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: Data([0x03, 0x88, 0xEC, 0x00, 0x01, 0x02, 0x01])
        )
        XCTAssertEqual(h70b3_2b93.resolvedName, "Govee Outdoor String Lights (H70B3 2B93)")
        XCTAssertEqual(h70b3_2b93.family, .govee)
        XCTAssertEqual(h70b3_2b93.goveePowerState, true)

        let h70b5_5870 = DeviceFingerprinter.identifyDetails(
            advertisedName: "Govee_H70B5_5870",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: Data([0x43, 0x88, 0xEC, 0x00, 0x02, 0x01, 0x00])
        )
        XCTAssertEqual(h70b5_5870.resolvedName, "Govee Curtain Lights 2 (H70B5 5870)")
        XCTAssertEqual(h70b5_5870.family, .govee)
        XCTAssertEqual(h70b5_5870.goveePowerState, false)
    }

    func testGoveePowerStateParsingFromHex() {
        XCTAssertEqual(DeviceFingerprinter.parseGoveePowerStateFromHex("0388EC00010201"), true)
        XCTAssertEqual(DeviceFingerprinter.parseGoveePowerStateFromHex("4388EC00020200"), false)
        XCTAssertEqual(DeviceFingerprinter.parseGoveePowerStateFromHex("4388EC00020100"), false)
        XCTAssertEqual(DeviceFingerprinter.parseGoveePowerStateFromHex("88EC00010201"), true)
        XCTAssertEqual(DeviceFingerprinter.parseGoveePowerStateFromHex("88EC00010200"), false)
        XCTAssertNil(DeviceFingerprinter.parseGoveePowerStateFromHex("1234"))
    }
}
