import XCTest
@testable import mHomeNode

@MainActor
final class LocationManagementTests: XCTestCase {

    func testManagedLocationGeofence() {
        let home = ManagedLocation(
            id: UUID(),
            name: "Home",
            latitude: 48.137154,
            longitude: 11.576124,
            radiusMeters: 150.0,
            associatedServerHost: "homenode.local"
        )

        // Point 50 meters away (inside)
        let insideLat = 48.137450
        let insideLon = 11.576124
        XCTAssertTrue(home.containsCoordinate(lat: insideLat, lon: insideLon))

        // Point 500 meters away (outside)
        let outsideLat = 48.141500
        let outsideLon = 11.576124
        XCTAssertFalse(home.containsCoordinate(lat: outsideLat, lon: outsideLon))
    }

    func testManagedLocationServerMatching() {
        let home = ManagedLocation(
            id: UUID(),
            name: "Home",
            associatedServerHost: "homenode.local"
        )

        XCTAssertTrue(home.matchesServer(host: "homenode.local"))
        XCTAssertTrue(home.matchesServer(host: "http://homenode.local:8080"))
        XCTAssertFalse(home.matchesServer(host: "other-server.local"))
    }

    func testPresenceDetectionViaServerAndGPS() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let service = LocationManagementService(customFileURL: tempDir.appendingPathComponent("loc.json"))

        let testHome = ManagedLocation(
            id: UUID(),
            name: "My Home",
            latitude: 48.137154,
            longitude: 11.576124,
            radiusMeters: 200.0,
            associatedServerHost: "192.168.1.100",
            isDefault: true
        )
        service.saveLocation(testHome)

        // 1. Neither available -> default fallback
        service.recalculateActiveState(currentLocation: nil, activeServerHost: nil)
        if case .detected(let loc, let method) = service.activeLocationState {
            XCTAssertEqual(loc.name, "My Home")
            XCTAssertEqual(method, .manualDefault)
        } else {
            XCTFail("Expected manualDefault")
        }

        // 2. Server discovered in LAN -> serverOnly
        service.recalculateActiveState(currentLocation: nil, activeServerHost: "192.168.1.100")
        if case .detected(let loc, let method) = service.activeLocationState {
            XCTAssertEqual(loc.name, "My Home")
            XCTAssertEqual(method, .serverOnly)
        } else {
            XCTFail("Expected serverOnly")
        }

        // 3. GPS nearby + Server -> serverAndGps
        let nearGPS = ScanLocation(latitude: 48.137200, longitude: 11.576150)
        service.recalculateActiveState(currentLocation: nearGPS, activeServerHost: "192.168.1.100")
        if case .detected(let loc, let method) = service.activeLocationState {
            XCTAssertEqual(loc.name, "My Home")
            XCTAssertEqual(method, .serverAndGps)
        } else {
            XCTFail("Expected serverAndGps")
        }

        // 4. GPS far away (Munich to Berlin) & no server -> away
        let farGPS = ScanLocation(latitude: 52.520008, longitude: 13.404954)
        service.recalculateActiveState(currentLocation: farGPS, activeServerHost: nil)
        if case .away(let nearest, let dist) = service.activeLocationState {
            XCTAssertEqual(nearest?.name, "My Home")
            XCTAssertNotNil(dist)
            XCTAssertGreaterThan(dist!, 100000)
        } else {
            XCTFail("Expected away")
        }
    }

    func testDeviceRegistryPersistenceAcrossClears() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("loc_devices.json")
        let service = LocationManagementService(customFileURL: fileURL)

        // Register Washer and assign to Laundry Room
        service.registerDevice(
            deviceId: "AA:BB:CC:11:22:33",
            customName: "Samsung Washer",
            room: "Laundry Room",
            family: "Samsung"
        )

        let lookup = service.lookupDevice(deviceId: "aa:bb:cc:11:22:33")
        XCTAssertNotNil(lookup)
        XCTAssertEqual(lookup?.customName, "Samsung Washer")
        XCTAssertEqual(lookup?.assignedRoom, "Laundry Room")

        // Reload service from disk to verify persistence
        let reloadedService = LocationManagementService(customFileURL: fileURL)
        let reloadedLookup = reloadedService.lookupDevice(deviceId: "AA:BB:CC:11:22:33")
        XCTAssertNotNil(reloadedLookup)
        XCTAssertEqual(reloadedLookup?.customName, "Samsung Washer")
        XCTAssertEqual(reloadedLookup?.assignedRoom, "Laundry Room")
    }
}
