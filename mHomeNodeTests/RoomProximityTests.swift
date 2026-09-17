import XCTest
@testable import mHomeNode

final class RoomProximityTests: XCTestCase {
    @MainActor
    func testNearestRoomDetectionPicksStrongestDeviceRoom() {
        let scanner = BLEScannerService()
        scanner.clear()

        let now = Date()

        // Device in Living Room with weak RSSI
        let livingRoomDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Thermometer",
            rssi: -82,
            family: .qingping,
            assignedRoom: "Living Room",
            firstSeen: now,
            lastSeen: now
        )

        // Device in Office with strong RSSI
        let officeDevice = DiscoveredDevice(
            id: UUID(),
            name: "Office Govee Light",
            rssi: -54,
            family: .govee,
            assignedRoom: "Office",
            firstSeen: now,
            lastSeen: now
        )

        // Device in Kitchen with moderate RSSI
        let kitchenDevice = DiscoveredDevice(
            id: UUID(),
            name: "Kitchen Sensor",
            rssi: -72,
            family: .shellyBlu,
            assignedRoom: "Kitchen",
            firstSeen: now,
            lastSeen: now
        )

        scanner.devices = [livingRoomDevice, officeDevice, kitchenDevice]

        let vm = ScannerViewModel(bleService: scanner)
        let detected = vm.detectNearestRoom()

        XCTAssertNotNil(detected)
        XCTAssertEqual(detected?.roomName, "Office")
        XCTAssertEqual(detected?.rssi, -54)
        XCTAssertEqual(detected?.strongestDevice.id, officeDevice.id)
    }

    @MainActor
    func testNearestRoomIgnoresIgnoredAndUnassignedDevices() {
        let scanner = BLEScannerService()
        scanner.clear()

        let now = Date()

        // Very strong RSSI but unassigned
        let unassigned = DiscoveredDevice(
            id: UUID(),
            name: "Unassigned Beacon",
            rssi: -40,
            assignedRoom: nil,
            firstSeen: now,
            lastSeen: now
        )

        // Very strong RSSI but ignored
        let neighbor = DiscoveredDevice(
            id: UUID(),
            name: "Neighbor Device",
            rssi: -45,
            assignedRoom: "Neighbor Room",
            isIgnored: true,
            firstSeen: now,
            lastSeen: now
        )

        // Legitimate device in Bedroom
        let bedroom = DiscoveredDevice(
            id: UUID(),
            name: "Bedroom Lamp",
            rssi: -65,
            family: .govee,
            assignedRoom: "Bedroom",
            firstSeen: now,
            lastSeen: now
        )

        scanner.devices = [unassigned, neighbor, bedroom]

        let vm = ScannerViewModel(bleService: scanner)
        let detected = vm.detectNearestRoom()

        XCTAssertNotNil(detected)
        XCTAssertEqual(detected?.roomName, "Bedroom")
        XCTAssertEqual(detected?.rssi, -65)
    }
}
