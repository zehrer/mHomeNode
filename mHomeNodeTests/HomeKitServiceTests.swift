import XCTest
@testable import mHomeNode

final class HomeKitServiceTests: XCTestCase {

    private var tempFileURL: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("test_hk_rooms_\(UUID().uuidString).json")
    }

    @MainActor
    override func tearDown() {
        if let url = tempFileURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    // MARK: - 1. HomeKitAccessoryData Model Tests

    func testHomeKitAccessoryDataInitialization() {
        let accId = UUID()
        let now = Date()
        let data = HomeKitAccessoryData(
            id: accId,
            name: "Living Room Qingping",
            roomName: "Living Room",
            floorName: "Ground Floor",
            model: "CGG1T",
            manufacturer: "Qingping",
            isReachable: true,
            temperature: 21.5,
            humidity: 48.0,
            batteryLevel: 95,
            isSwitchable: false,
            isPowerOn: nil,
            isLight: false,
            brightness: nil,
            lastUpdated: now
        )

        XCTAssertEqual(data.id, accId)
        XCTAssertEqual(data.name, "Living Room Qingping")
        XCTAssertEqual(data.roomName, "Living Room")
        XCTAssertEqual(data.floorName, "Ground Floor")
        XCTAssertEqual(data.model, "CGG1T")
        XCTAssertEqual(data.manufacturer, "Qingping")
        XCTAssertTrue(data.isReachable)
        XCTAssertEqual(data.temperature, 21.5)
        XCTAssertEqual(data.humidity, 48.0)
        XCTAssertEqual(data.batteryLevel, 95)
        XCTAssertFalse(data.isSwitchable)
        XCTAssertNil(data.isPowerOn)
        XCTAssertFalse(data.isLight)
    }

    func testHomeKitAccessoryDataSwitchableLight() {
        let accId = UUID()
        let light = HomeKitAccessoryData(
            id: accId,
            name: "Desk Lamp",
            roomName: "Office",
            floorName: "1st Floor",
            model: "Hue Lamp",
            manufacturer: "Philips",
            isReachable: true,
            temperature: nil,
            humidity: nil,
            batteryLevel: nil,
            isSwitchable: true,
            isPowerOn: true,
            isLight: true,
            brightness: 75
        )

        XCTAssertTrue(light.isSwitchable)
        XCTAssertEqual(light.isPowerOn, true)
        XCTAssertTrue(light.isLight)
        XCTAssertEqual(light.brightness, 75)
    }

    // MARK: - 2. Device Matching Tests

    @MainActor
    func testDeviceMatchingByName() {
        let service = HomeKitService()
        let accId = UUID()
        let testAcc = HomeKitAccessoryData(
            id: accId,
            name: "Qingping Temp & RH Lite",
            roomName: "Living Room",
            model: "CGG1T",
            manufacturer: "Qingping",
            temperature: 22.1,
            humidity: 50.0
        )
        service.accessories = [testAcc]

        // Discovered device matching by direct name
        let dev1 = DiscoveredDevice(
            id: UUID(),
            name: "Qingping Temp & RH Lite",
            rssi: -65,
            family: .qingping,
            firstSeen: Date(),
            lastSeen: Date()
        )

        let match1 = service.findMatchingAccessory(for: dev1)
        XCTAssertNotNil(match1)
        XCTAssertEqual(match1?.id, accId)
        XCTAssertEqual(match1?.temperature, 22.1)

        // Discovered device matching by custom name
        var dev2 = DiscoveredDevice(
            id: UUID(),
            name: "BLE_UNKNOWN_1234",
            rssi: -70,
            family: .standardBLE,
            firstSeen: Date(),
            lastSeen: Date()
        )
        dev2.customName = "Qingping Temp & RH Lite"

        let match2 = service.findMatchingAccessory(for: dev2)
        XCTAssertNotNil(match2)
        XCTAssertEqual(match2?.id, accId)
    }

    @MainActor
    func testDeviceMatchingByQingpingFamilyFallback() {
        let service = HomeKitService()
        let accId = UUID()
        let testAcc = HomeKitAccessoryData(
            id: accId,
            name: "Living Room Sensor",
            roomName: "Living Room",
            model: "CGG1T",
            manufacturer: "Qingping",
            temperature: 20.4,
            humidity: 55.0
        )
        service.accessories = [testAcc]

        // Device with family .qingping but generic broadcast name
        let dev = DiscoveredDevice(
            id: UUID(),
            name: "Qingping BT 903D",
            rssi: -60,
            family: .qingping,
            firstSeen: Date(),
            lastSeen: Date()
        )

        let match = service.findMatchingAccessory(for: dev)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.id, accId)
        XCTAssertEqual(match?.temperature, 20.4)
    }

    // MARK: - 3. Apple Home Room & Floor (Zone) Sync Tests

    @MainActor
    func testAppleHomeRoomAndFloorSync() {
        let roomService = RoomManagementService(customFileURL: tempFileURL)

        // Sync with Apple Home rooms and floors (zones)
        let hkRooms: [(id: String, name: String, floor: String?)] = [
            (id: "hk-1", name: "Living Room", floor: "Ground Floor"),
            (id: "hk-2", name: "Master Bedroom", floor: "Upper Floor"),
            (id: "hk-3", name: "Basement Workshop", floor: "Basement")
        ]

        roomService.syncWithAppleHome(homeKitRoomsWithFloor: hkRooms)

        // Verify Living Room was matched or updated with floor
        let lr = roomService.room(named: "Living Room")
        XCTAssertNotNil(lr)
        XCTAssertEqual(lr?.floor, "Ground Floor")
        XCTAssertEqual(lr?.externalId, "hk-1")

        // Verify Master Bedroom was added
        let mbr = roomService.room(named: "Master Bedroom")
        XCTAssertNotNil(mbr)
        XCTAssertEqual(mbr?.floor, "Upper Floor")
        XCTAssertEqual(mbr?.externalId, "hk-2")

        // Verify distinct floors
        let floors = roomService.distinctFloors
        XCTAssertTrue(floors.contains("Ground Floor"))
        XCTAssertTrue(floors.contains("Upper Floor"))
        XCTAssertTrue(floors.contains("Basement"))
    }
}
