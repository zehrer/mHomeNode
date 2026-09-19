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
}
