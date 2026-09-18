import XCTest
@testable import mHomeNode

final class SensorTelemetryAndDutyCycleTests: XCTestCase {

    func testBTHomeDataMergePreservesMeasurements() {
        // Initial reading: Temperature & Humidity
        var base = BTHomeData(
            temperature: 22.5,
            humidity: 45.0,
            rawMeasurements: ["temperature": 22.5, "humidity": 45.0]
        )

        // Incoming packet: Battery only (e.g. from Xiaomi or BTHome periodic broadcast)
        let batteryUpdate = BTHomeData(
            battery: 85,
            rawMeasurements: ["battery": 85.0]
        )

        base.merge(with: batteryUpdate)

        // Verify temperature & humidity are preserved, and battery is updated
        XCTAssertEqual(base.temperature, 22.5)
        XCTAssertEqual(base.humidity, 45.0)
        XCTAssertEqual(base.battery, 85)
        XCTAssertEqual(base.rawMeasurements["temperature"], 22.5)
        XCTAssertEqual(base.rawMeasurements["battery"], 85.0)

        // Incoming packet: Updated temperature
        let tempUpdate = BTHomeData(
            temperature: 23.1,
            rawMeasurements: ["temperature": 23.1]
        )

        base.merge(with: tempUpdate)

        XCTAssertEqual(base.temperature, 23.1)
        XCTAssertEqual(base.humidity, 45.0)
        XCTAssertEqual(base.battery, 85)
    }

    func testMeasurementAgeLevelsAndSignalLoss() {
        let now = Date()

        // 1. Fresh measurement (15s ago) -> "now", active signal
        let freshDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Sensor",
            rssi: -65,
            lastMeasurementDate: now.addingTimeInterval(-15)
        )
        XCTAssertEqual(freshDevice.measurementAgeText, "now")
        XCTAssertFalse(freshDevice.isSignalLost)

        // 2. 3 minutes ago -> "3 min", active signal
        let threeMinDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Sensor",
            rssi: -65,
            lastMeasurementDate: now.addingTimeInterval(-185)
        )
        XCTAssertEqual(threeMinDevice.measurementAgeText, "3 min")
        XCTAssertFalse(threeMinDevice.isSignalLost)

        // 3. 25 minutes ago -> "25 min", still within 30 min window
        let twentyFiveMinDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Sensor",
            rssi: -65,
            lastMeasurementDate: now.addingTimeInterval(-1500)
        )
        XCTAssertEqual(twentyFiveMinDevice.measurementAgeText, "25 min")
        XCTAssertFalse(twentyFiveMinDevice.isSignalLost)

        // 4. 45 minutes ago (> 30 min) -> "No signal", lost signal
        let staleDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Sensor",
            rssi: -65,
            lastMeasurementDate: now.addingTimeInterval(-2700)
        )
        XCTAssertEqual(staleDevice.measurementAgeText, "No signal")
        XCTAssertTrue(staleDevice.isSignalLost)

        // 5. No measurement ever recorded -> "No signal", lost signal
        let unmeasuredDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Sensor",
            rssi: -65,
            lastMeasurementDate: nil
        )
        XCTAssertEqual(unmeasuredDevice.measurementAgeText, "No signal")
        XCTAssertTrue(unmeasuredDevice.isSignalLost)
    }

    @MainActor
    func testGenericFamilyNamesDoNotTriggerIgnoreCollision() {
        let service = IgnoreService()
        // Simulate an ignored record with a generic family name
        service.ignoredRecords = [
            IgnoredDeviceRecord(id: "AA:BB:CC:DD:EE:FF", name: "Xiaomi Mijia", reason: "Neighbor")
        ]

        // Another device with different ID but same generic name
        let isIgnored = service.isIgnored(id: "11:22:33:44:55:66", name: "Xiaomi Mijia")
        XCTAssertFalse(isIgnored, "Generic family names must not cause unrelated sensors to be ignored")

        // Exact ID must still be ignored
        let isExactIgnored = service.isIgnored(id: "AA:BB:CC:DD:EE:FF", name: "Xiaomi Mijia")
        XCTAssertTrue(isExactIgnored)
    }
}
