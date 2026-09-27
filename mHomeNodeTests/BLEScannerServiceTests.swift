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

    @MainActor
    func testAutoGATTDefaultsAndConfiguration() {
        let scanner = BLEScannerService()
        XCTAssertFalse(scanner.isAutoGATTEnabled)
        XCTAssertEqual(scanner.autoGATTRSSIThreshold, -70)
        XCTAssertNil(scanner.activeAutoInspectDeviceName)

        scanner.autoGATTRSSIThreshold = -60
        XCTAssertEqual(scanner.autoGATTRSSIThreshold, -60)

        scanner.isAutoGATTEnabled = true
        XCTAssertTrue(scanner.isAutoGATTEnabled)
    }

    @MainActor
    func testAutoGATTCheckDoesNotRunWhenNotScanning() {
        let scanner = BLEScannerService()
        scanner.isAutoGATTEnabled = true
        let devId = UUID()
        let device = DiscoveredDevice(
            id: devId,
            name: "Connectable Bulb",
            rssi: -50,
            isConnectable: true
        )
        scanner.devices = [device]

        // When not scanning or not powered on, triggerAutoGATTCheck should do nothing
        scanner.triggerAutoGATTCheck()
        XCTAssertNil(scanner.activeAutoInspectDeviceName)
    }

    @MainActor
    func testPeriodicSyncConfiguration() {
        let vm = ScannerViewModel()
        XCTAssertTrue(vm.isPeriodicSyncEnabled)
        XCTAssertEqual(vm.periodicSyncInterval, 180.0)

        vm.isPeriodicSyncEnabled = false
        XCTAssertFalse(vm.isPeriodicSyncEnabled)
    }

    func testSpecificAppleNameDetection() {
        XCTAssertTrue(DeviceFingerprinter.isSpecificAppleName("MacBook Pro"))
        XCTAssertTrue(DeviceFingerprinter.isSpecificAppleName("Stephan's MacBook Pro"))
        XCTAssertTrue(DeviceFingerprinter.isSpecificAppleName("iPhone von Stephan"))
        XCTAssertTrue(DeviceFingerprinter.isSpecificAppleName("Apple Watch"))
        XCTAssertTrue(DeviceFingerprinter.isSpecificAppleName("Mac mini"))

        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("Apple Device"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("apple device"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("Find My / AirTag"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("Find My Accessory"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("Unknown"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("HomeKit Accessory"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("HomeKit Device (Unpaired)"))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName("   "))
        XCTAssertFalse(DeviceFingerprinter.isSpecificAppleName(""))
    }

    @MainActor
    func testPruneEphemeralDevices() {
        let scanner = BLEScannerService()
        let now = Date()
        let staleDate = now.addingTimeInterval(-7200) // 2 hours ago

        // 1. Ephemeral Apple device (unassigned room, no custom name, stale) -> SHOULD BE PRUNED
        let staleAppleDevice = DiscoveredDevice(
            id: UUID(),
            name: "Apple Device",
            rssi: -85,
            family: .apple,
            assignedRoom: nil,
            customName: nil,
            firstSeen: staleDate,
            lastSeen: staleDate
        )

        // 2. Apple device with assigned room (stale) -> MUST NOT BE PRUNED
        let assignedAppleDevice = DiscoveredDevice(
            id: UUID(),
            name: "MacBook Pro",
            rssi: -70,
            family: .apple,
            assignedRoom: "Office",
            customName: nil,
            firstSeen: staleDate,
            lastSeen: staleDate
        )

        // 3. Apple device with custom name (stale) -> MUST NOT BE PRUNED
        let customNamedAppleDevice = DiscoveredDevice(
            id: UUID(),
            name: "Stephan's Laptop",
            rssi: -65,
            family: .apple,
            assignedRoom: nil,
            customName: "Stephan's Laptop",
            firstSeen: staleDate,
            lastSeen: staleDate
        )

        // 4. Recently seen Apple device (< 60m old) -> MUST NOT BE PRUNED
        let activeAppleDevice = DiscoveredDevice(
            id: UUID(),
            name: "Apple Device",
            rssi: -60,
            family: .apple,
            assignedRoom: nil,
            customName: nil,
            firstSeen: now,
            lastSeen: now
        )

        // 5. Non-Apple stale device -> MUST NOT BE PRUNED by pruneEphemeralDevices
        let nonAppleStaleDevice = DiscoveredDevice(
            id: UUID(),
            name: "Govee Bulb",
            rssi: -80,
            family: .govee,
            assignedRoom: nil,
            customName: nil,
            firstSeen: staleDate,
            lastSeen: staleDate
        )

        scanner.devices = [
            staleAppleDevice,
            assignedAppleDevice,
            customNamedAppleDevice,
            activeAppleDevice,
            nonAppleStaleDevice
        ]

        let prunedCount = scanner.pruneEphemeralDevices(maxAge: 3600)
        XCTAssertEqual(prunedCount, 1, "Only the stale unassigned Apple device should be pruned")

        XCTAssertFalse(scanner.devices.contains(where: { $0.id == staleAppleDevice.id }))
        XCTAssertTrue(scanner.devices.contains(where: { $0.id == assignedAppleDevice.id }))
        XCTAssertTrue(scanner.devices.contains(where: { $0.id == customNamedAppleDevice.id }))
        XCTAssertTrue(scanner.devices.contains(where: { $0.id == activeAppleDevice.id }))
        XCTAssertTrue(scanner.devices.contains(where: { $0.id == nonAppleStaleDevice.id }))
    }

    @MainActor
    func testAppleDeviceLocationMigration() {
        let locService = LocationManagementService.shared
        let oldUUID = UUID()
        let newUUID = UUID()

        locService.registerDevice(
            deviceId: oldUUID.uuidString,
            customName: "Stephan MacBook",
            room: "Office",
            family: "Apple"
        )

        XCTAssertNotNil(locService.lookupDevice(deviceId: oldUUID.uuidString))

        locService.migrateDeviceId(
            oldDeviceId: oldUUID.uuidString,
            newDeviceId: newUUID.uuidString
        )

        XCTAssertNil(locService.lookupDevice(deviceId: oldUUID.uuidString), "Old UUID should no longer exist")
        let migrated = locService.lookupDevice(deviceId: newUUID.uuidString)
        XCTAssertNotNil(migrated, "New UUID should be registered")
        XCTAssertEqual(migrated?.customName, "Stephan MacBook")
        XCTAssertEqual(migrated?.assignedRoom, "Office")

        // Cleanup
        locService.unregisterDevice(
            locationId: locService.activeLocation.id,
            deviceId: newUUID.uuidString
        )
    }
}

