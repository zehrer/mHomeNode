import XCTest
@testable import mHomeNode
import CoreBluetooth

final class BLEScannerServiceTests: XCTestCase {

    @MainActor
    func testInitialStateDoesNotShowErrorMessage() {
        let scanner = BLEScannerService()
        // On initialization before CoreBluetooth daemon reports state, state is .unknown
        XCTAssertNil(scanner.errorMessage, "ErrorMessage must be nil on initial startup even if state is unknown")
    }

    @MainActor
    func testStartScanWhileUnknownDoesNotShowErrorBanner() {
        let scanner = BLEScannerService()
        // Calling startScan while state is unknown (such as on app launch) must not produce an error message
        scanner.startScan()
        XCTAssertNil(scanner.errorMessage, "startScan() during initial .unknown state must not show an error banner")
    }

    @MainActor
    func testClearRetainsAssignedRoomDevices() {
        let scanner = BLEScannerService()
        let now = Date()

        let roomDevice = DiscoveredDevice(
            id: UUID(),
            name: "Bedroom Sensor",
            rssi: -60,
            family: .shellyBlu,
            assignedRoom: "Bedroom",
            firstSeen: now,
            lastSeen: now
        )

        let unassignedDevice = DiscoveredDevice(
            id: UUID(),
            name: "Unknown Beacon",
            rssi: -90,
            family: .standardBLE,
            assignedRoom: nil,
            firstSeen: now,
            lastSeen: now
        )

        scanner.devices = [roomDevice, unassignedDevice]
        scanner.clear()

        // Devices with an assigned room should be preserved; unassigned should be removed
        XCTAssertTrue(scanner.devices.contains(where: { $0.id == roomDevice.id }))
        XCTAssertFalse(scanner.devices.contains(where: { $0.id == unassignedDevice.id }))
    }

    @MainActor
    func testUpdateDeviceCustomNameAndRoom() {
        let scanner = BLEScannerService()
        let devId = UUID()
        let device = DiscoveredDevice(
            id: devId,
            name: "Original Name",
            rssi: -70
        )
        scanner.devices = [device]

        scanner.updateDeviceName(id: devId, customName: "My Custom Plug")
        XCTAssertEqual(scanner.devices.first?.customName, "My Custom Plug")

        scanner.updateRoom(for: devId, room: "Living Room")
        XCTAssertEqual(scanner.devices.first?.assignedRoom, "Living Room")
    }
}
