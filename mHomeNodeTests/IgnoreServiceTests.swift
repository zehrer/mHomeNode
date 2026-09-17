import XCTest
@testable import mHomeNode

@MainActor
final class IgnoreServiceTests: XCTestCase {

    func testIgnoreAndUnignoreDevice() {
        let service = IgnoreService()
        let testId = "11:22:33:44:55:66"
        let testName = "Neighbor Shelly H&T"

        service.unignore(id: testId)
        XCTAssertFalse(service.isIgnored(id: testId, name: testName))

        service.ignore(id: testId, name: testName, reason: "Nachbar")
        XCTAssertTrue(service.isIgnored(id: testId, name: testName))
        // Test normalized without colons
        XCTAssertTrue(service.isIgnored(id: "112233445566"))

        service.unignore(id: testId)
        XCTAssertFalse(service.isIgnored(id: testId, name: testName))
    }

    func testDiscoveredDeviceToMobileBleScanItem() {
        let device = DiscoveredDevice(
            id: UUID(),
            name: "Shelly BLU Door",
            rssi: -65,
            family: .shellyBlu,
            assignedRoom: "Wohnzimmer"
        )
        let item = device.toMobileBleScanItem(scoutName: "iPhone 16 Pro")
        XCTAssertEqual(item.name, "Shelly BLU Door")
        XCTAssertEqual(item.rssi, -65)
        XCTAssertEqual(item.family, "Shelly BLU")
        XCTAssertEqual(item.assignedRoom, "Wohnzimmer")
        XCTAssertEqual(item.scoutName, "iPhone 16 Pro")
    }
}
