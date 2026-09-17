import XCTest
@testable import mHomeNode

final class ServerConnectionIntegrationTests: XCTestCase {

    /// Tests live health endpoint connectivity against the locally running HomeNode Server
    func testLiveServerHealthCheck() async throws {
        let client = LiveHomeNodeServerClient()
        let config = ServerConfig(host: "127.0.0.1", port: 8080, useTLS: false)

        do {
            let status = try await client.checkHealth(config: config)
            print("Successfully connected to HomeNode Server: version=\(status.version), uptime=\(status.uptimeSeconds)s, matterNodes=\(status.activeMatterNodes), bleGateways=\(status.activeBLEGateways), devices=\(status.activeDevices ?? 0)")

            XCTAssertFalse(status.version.isEmpty, "Server version should not be empty")
            XCTAssertGreaterThan(status.uptimeSeconds, 0, "Uptime should be positive")
            XCTAssertGreaterThanOrEqual(status.activeBLEGateways, 0, "activeBLEGateways should be parsed correctly")
        } catch {
            XCTFail("Failed to connect to local HomeNode Server on 127.0.0.1:8080. Is the server running? Error: \(error)")
        }
    }

    /// Tests mobile BLE advertisement ingestion against the locally running HomeNode Server
    func testLiveMobileBleIngest() async throws {
        let client = LiveHomeNodeServerClient()
        let config = ServerConfig(host: "127.0.0.1", port: 8080, useTLS: false)

        let testItem = MobileBleScanItem(
            id: "E4:5F:01:FE:DC:BA",
            name: "Integration Test Sensor",
            rssi: -65,
            manufacturerDataHex: "4C000215",
            family: "Shelly BLU",
            assignedRoom: "Living Room",
            scoutName: "MacBook Test Runner",
            bthomeVersion: 2,
            battery: 98,
            temperatureC: 22.4,
            humidityPct: 46.5
        )

        do {
            let (ingested, ignored) = try await client.sendMobileBleScan(config: config, items: [testItem])
            print("Live ingest result: ingested=\(ingested), ignored=\(ignored)")
            XCTAssertGreaterThanOrEqual(ingested, 1, "Expected at least 1 ingested scan item")
        } catch {
            XCTFail("Failed to ingest mobile BLE scan item to 127.0.0.1:8080: \(error)")
        }
    }
}
