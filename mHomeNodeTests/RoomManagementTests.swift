import XCTest
@testable import mHomeNode

final class RoomManagementTests: XCTestCase {

    private var tempFileURL: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("test_rooms_\(UUID().uuidString).json")
    }

    @MainActor
    override func tearDown() {
        if let url = tempFileURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    @MainActor
    func testDefaultRoomsInitialization() {
        let service = RoomManagementService(customFileURL: tempFileURL)
        XCTAssertFalse(service.rooms.isEmpty)
        XCTAssertTrue(service.rooms.contains(where: { $0.name == "Living Room" }))
        XCTAssertTrue(service.rooms.contains(where: { $0.name == "Kitchen" }))
        XCTAssertTrue(service.rooms.contains(where: { $0.name == "Bedroom" }))
    }

    @MainActor
    func testAddUpdateDeleteRoom() {
        let service = RoomManagementService(customFileURL: tempFileURL)
        let initialCount = service.rooms.count

        // 1. Add Room
        let added = service.addRoom(name: "Garden", icon: "tree.fill", colorHex: "#34C759", source: .local)
        XCTAssertEqual(service.rooms.count, initialCount + 1)
        XCTAssertEqual(added.name, "Garden")
        XCTAssertEqual(added.icon, "tree.fill")

        // 2. Duplicate Add should return existing
        let dup = service.addRoom(name: "garden")
        XCTAssertEqual(dup.id, added.id)
        XCTAssertEqual(service.rooms.count, initialCount + 1)

        // 3. Update Room
        service.updateRoom(id: added.id, name: "Backyard Garden", icon: "sun.max.fill", colorHex: "#FF9500")
        let updated = service.room(named: "Backyard Garden")
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.icon, "sun.max.fill")
        XCTAssertEqual(updated?.colorHex, "#FF9500")

        // 4. Delete Room
        service.deleteRoom(id: added.id)
        XCTAssertEqual(service.rooms.count, initialCount)
        XCTAssertNil(service.room(named: "Backyard Garden"))
    }

    @MainActor
    func testDiskPersistence() {
        let service1 = RoomManagementService(customFileURL: tempFileURL)
        service1.addRoom(name: "Terrace", icon: "sun.max.fill", colorHex: "#FFCC00")

        // Re-instantiate service from same file URL
        let service2 = RoomManagementService(customFileURL: tempFileURL)
        let terrace = service2.room(named: "Terrace")
        XCTAssertNotNil(terrace)
        XCTAssertEqual(terrace?.icon, "sun.max.fill")
        XCTAssertEqual(terrace?.colorHex, "#FFCC00")
    }

    @MainActor
    func testSyncWithServerRooms() {
        let service = RoomManagementService(customFileURL: tempFileURL)

        let serverRooms = [
            ServerRoom(id: "srv-living", name: "Living Room", icon: "sofa.fill"),
            ServerRoom(id: "srv-wine", name: "Wine Cellar", icon: "cup.and.saucer.fill")
        ]

        service.syncWithServerRooms(serverRooms)

        // Existing Living Room should now have serverRoomId linked
        let living = service.room(named: "Living Room")
        XCTAssertEqual(living?.serverRoomId, "srv-living")

        // New room from server should be added as homeNodeServer source
        let wine = service.room(named: "Wine Cellar")
        XCTAssertNotNil(wine)
        XCTAssertEqual(wine?.source, .homeNodeServer)
        XCTAssertEqual(wine?.serverRoomId, "srv-wine")
        XCTAssertNotNil(service.lastSyncedDate)
    }

    @MainActor
    func testHueAndAppleHomeSync() {
        let service = RoomManagementService(customFileURL: tempFileURL)

        // Philips Hue sync
        service.syncWithHue(hueRooms: [
            (id: "hue-123", name: "Hue Entertainment Area", icon: "sparkles")
        ])
        let hueRoom = service.room(named: "Hue Entertainment Area")
        XCTAssertNotNil(hueRoom)
        XCTAssertEqual(hueRoom?.source, .philipsHue)
        XCTAssertEqual(hueRoom?.externalId, "hue-123")

        // Apple Home sync
        service.syncWithAppleHome(homeKitRooms: [
            (id: "hk-456", name: "Front Porch")
        ])
        let hkRoom = service.room(named: "Front Porch")
        XCTAssertNotNil(hkRoom)
        XCTAssertEqual(hkRoom?.source, .appleHome)
        XCTAssertEqual(hkRoom?.externalId, "hk-456")
    }
}
