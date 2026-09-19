import XCTest
@testable import mHomeNode

final class ScanExportTests: XCTestCase {

    func testCSVHeaderFormat() {
        let header = ScanExportService.csvHeader
        XCTAssertTrue(header.contains("Session_ID"))
        XCTAssertTrue(header.contains("Session_Title"))
        XCTAssertTrue(header.contains("Timestamp"))
        XCTAssertTrue(header.contains("Latitude"))
        XCTAssertTrue(header.contains("Device_Name"))
        XCTAssertTrue(header.contains("Temperature_C"))
        XCTAssertTrue(header.contains("Humidity_pct"))
    }

    func testSingleSessionCSVExport() {
        let dev = DiscoveredDevice(
            id: UUID(),
            name: "Mijia Temp, Sensor",
            rssi: -65,
            btHomeData: BTHomeData(battery: 92, temperature: 21.5, humidity: 55.0),
            family: .xiaomi,
            macAddress: "A4:C1:38:12:34:56"
        )

        let loc = ScanLocation(
            latitude: 48.1371,
            longitude: 11.5754,
            horizontalAccuracy: 5.0,
            placeName: "Munich, Germany"
        )

        let session = SavedScanSession(
            title: "Test Office Scan",
            timestamp: Date(),
            location: loc,
            note: "Testing CSV, quotes & commas",
            devices: [dev]
        )

        let csv = session.exportCSV()
        let lines = csv.components(separatedBy: "\n")

        // Should have header + 1 device line
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].starts(with: "Session_ID"))

        let row = lines[1]
        // Should contain escaped place name and device name
        XCTAssertTrue(row.contains("\"Munich, Germany\""))
        XCTAssertTrue(row.contains("\"Mijia Temp, Sensor\""))
        XCTAssertTrue(row.contains("21.50"))
        XCTAssertTrue(row.contains("55.0"))
        XCTAssertTrue(row.contains("92"))
        XCTAssertTrue(row.contains("Xiaomi Mijia"))
        XCTAssertTrue(row.contains("A4:C1:38:12:34:56"))
    }

    func testBulkCSVExport() {
        let dev1 = DiscoveredDevice(id: UUID(), name: "Device 1", rssi: -70, family: .govee)
        let dev2 = DiscoveredDevice(id: UUID(), name: "Device 2", rssi: -80, family: .shellyBlu)

        let session1 = SavedScanSession(title: "Session 1", devices: [dev1])
        let session2 = SavedScanSession(title: "Session 2", devices: [dev2])

        let bulkCSV = ScanExportService.shared.exportAllCSV(sessions: [session1, session2])
        let lines = bulkCSV.components(separatedBy: "\n")

        // 1 header + 2 device rows
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].contains("Session 1"))
        XCTAssertTrue(lines[1].contains("Device 1"))
        XCTAssertTrue(lines[2].contains("Session 2"))
        XCTAssertTrue(lines[2].contains("Device 2"))
    }

    func testJSONExportAndIntegrity() {
        let dev = DiscoveredDevice(id: UUID(), name: "Test Dev", rssi: -60, family: .standardBLE)
        let session = SavedScanSession(title: "JSON Test", devices: [dev])

        guard let data = ScanExportService.shared.exportAllJSONData(sessions: [session]) else {
            XCTFail("Failed to serialize sessions to JSON")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([SavedScanSession].self, from: data)
            XCTAssertEqual(decoded.count, 1)
            XCTAssertEqual(decoded[0].title, "JSON Test")
            XCTAssertEqual(decoded[0].devices.count, 1)
            XCTAssertEqual(decoded[0].devices[0].name, "Test Dev")
        } catch {
            XCTFail("Failed to decode serialized JSON: \(error)")
        }
    }

    func testSummaryExportFormatting() {
        let dev = DiscoveredDevice(id: UUID(), name: "Sensor", rssi: -50, family: .xiaomi)
        let session = SavedScanSession(title: "Summary Session", devices: [dev])

        let summary = ScanExportService.shared.exportAllSummary(sessions: [session])
        XCTAssertTrue(summary.contains("mHomeNode BLE Scan Archive Summary"))
        XCTAssertTrue(summary.contains("Total Sessions: 1"))
        XCTAssertTrue(summary.contains("Total Devices Logged: 1"))
        XCTAssertTrue(summary.contains("Summary Session"))
    }
}

