import XCTest
@testable import mHomeNode

final class SavedScanTests: XCTestCase {

    func testScanLocationFormatting() {
        let loc = ScanLocation(
            latitude: 48.137154,
            longitude: 11.575498,
            altitude: 519.0,
            horizontalAccuracy: 8.5,
            placeName: "Marienplatz, München"
        )

        XCTAssertEqual(loc.placeName, "Marienplatz, München")
        XCTAssertEqual(loc.displayTitle, "Marienplatz, München")
        XCTAssertTrue(loc.formattedCoordinates.contains("48.1372° N"))
        XCTAssertTrue(loc.formattedCoordinates.contains("11.5755° E"))
        XCTAssertEqual(loc.formattedAccuracy, "±9m")

        let fallbackLoc = ScanLocation(
            latitude: -33.8688,
            longitude: 151.2093,
            placeName: nil
        )
        XCTAssertTrue(fallbackLoc.displayTitle.contains("33.8688° S"))
        XCTAssertTrue(fallbackLoc.displayTitle.contains("151.2093° E"))
    }

    func testSavedScanSessionSerializationAndSummary() {
        let testDevice = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Sensor",
            rssi: -62,
            btHomeData: BTHomeData(battery: 92, temperature: 21.8, humidity: 48.0),
            family: .xiaomi,
            macAddress: "A4:C1:38:12:34:56"
        )

        let location = ScanLocation(
            latitude: 48.1371,
            longitude: 11.5754,
            placeName: "Office München"
        )

        let session = SavedScanSession(
            title: "Site Survey 1",
            location: location,
            note: "Testing corner reception",
            devices: [testDevice]
        )

        XCTAssertEqual(session.deviceCount, 1)
        XCTAssertEqual(session.title, "Site Survey 1")

        // Test export summary
        let summary = session.exportSummary()
        XCTAssertTrue(summary.contains("Site Survey 1"))
        XCTAssertTrue(summary.contains("Office München"))
        XCTAssertTrue(summary.contains("Living Room Sensor"))
        XCTAssertTrue(summary.contains("21.8°C"))
        XCTAssertTrue(summary.contains("48%"))
        XCTAssertTrue(summary.contains("92%"))

        // Test JSON roundtrip
        guard let jsonData = session.exportJSONData() else {
            XCTFail("Failed to encode JSON")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode(SavedScanSession.self, from: jsonData)
            XCTAssertEqual(decoded.id, session.id)
            XCTAssertEqual(decoded.title, session.title)
            XCTAssertEqual(decoded.location?.placeName, "Office München")
            XCTAssertEqual(decoded.devices.count, 1)
            XCTAssertEqual(decoded.devices.first?.btHomeData?.temperature, 21.8)
        } catch {
            XCTFail("JSON decode failed: \(error)")
        }
    }

    func testSavedScanStorageServicePersistence() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = SavedScanStorageService(customDirectoryURL: tempDir)

        // Initially empty
        XCTAssertEqual(storage.loadSessions().count, 0)

        // Save session 1
        let session1 = SavedScanSession(
            title: "Survey Alpha",
            devices: []
        )
        storage.saveSession(session1)

        let loaded1 = storage.loadSessions()
        XCTAssertEqual(loaded1.count, 1)
        XCTAssertEqual(loaded1.first?.title, "Survey Alpha")

        // Save session 2
        let session2 = SavedScanSession(
            title: "Survey Beta",
            devices: []
        )
        storage.saveSession(session2)

        let loaded2 = storage.loadSessions()
        XCTAssertEqual(loaded2.count, 2)

        // Delete session 1
        storage.deleteSession(id: session1.id)
        let loaded3 = storage.loadSessions()
        XCTAssertEqual(loaded3.count, 1)
        XCTAssertEqual(loaded3.first?.id, session2.id)

        // Clear all
        storage.clearAll()
        XCTAssertEqual(storage.loadSessions().count, 0)
    }
}
