import XCTest
@testable import mHomeNode

final class DeviceStorageServiceTests: XCTestCase {
    var tempDirectory: URL!
    var storageService: DeviceStorageService!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        storageService = DeviceStorageService(customDirectoryURL: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        storageService = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testSaveAndLoadDevices() {
        let dev1 = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Thermometer",
            rssi: -64,
            rssiHistory: [-70, -68, -64],
            serviceUUIDs: ["FDCD"],
            manufacturerDataHex: "4C00",
            btHomeData: BTHomeData(
                battery: 92,
                temperature: 21.8,
                humidity: 49.3,
                pressure: 1013.2
            ),
            family: .qingping,
            isConnectable: true,
            assignedRoom: "Wohnzimmer",
            isIgnored: false,
            macAddress: "58:2D:34:11:22:33"
        )

        let dev2 = DiscoveredDevice(
            id: UUID(),
            name: "Shelly BLU Door",
            rssi: -78,
            family: .shellyBlu,
            assignedRoom: "Eingang",
            isIgnored: false,
            macAddress: "E4:5F:01:AA:BB:CC"
        )

        // Save
        storageService.saveDevicesSync([dev1, dev2])

        // Load
        let loaded = storageService.loadDevices()
        XCTAssertEqual(loaded.count, 2)

        let loaded1 = loaded.first { $0.id == dev1.id }
        XCTAssertNotNil(loaded1)
        XCTAssertEqual(loaded1?.name, "Living Room Thermometer")
        XCTAssertEqual(loaded1?.family, .qingping)
        XCTAssertEqual(loaded1?.assignedRoom, "Wohnzimmer")
        XCTAssertEqual(loaded1?.macAddress, "58:2D:34:11:22:33")
        XCTAssertEqual(loaded1?.btHomeData?.temperature, 21.8)
        XCTAssertEqual(loaded1?.btHomeData?.humidity, 49.3)
        XCTAssertEqual(loaded1?.btHomeData?.battery, 92)

        let loaded2 = loaded.first { $0.id == dev2.id }
        XCTAssertNotNil(loaded2)
        XCTAssertEqual(loaded2?.name, "Shelly BLU Door")
        XCTAssertEqual(loaded2?.family, .shellyBlu)
        XCTAssertEqual(loaded2?.assignedRoom, "Eingang")
        XCTAssertEqual(loaded2?.macAddress, "E4:5F:01:AA:BB:CC")

        // Clear
        storageService.clear()
        let afterClear = storageService.loadDevices()
        XCTAssertTrue(afterClear.isEmpty)
    }
}
