import XCTest
@testable import mHomeNode

final class ShellyMultiPathTests: XCTestCase {

    func testShellyLANStatusInitialization() {
        let status = ShellySwitchStatus(
            isOn: true,
            activePowerW: 24.5,
            voltageV: 230.1,
            currentA: 0.106,
            totalEnergyKWh: 1.25
        )

        XCTAssertTrue(status.isOn)
        XCTAssertEqual(status.activePowerW, 24.5)
        XCTAssertEqual(status.voltageV, 230.1)
        XCTAssertEqual(status.currentA, 0.106)
        XCTAssertEqual(status.totalEnergyKWh, 1.25)
    }

    @MainActor
    func testShellyMultiPathPrioritizesServerWhenConnected() async {
        let mockLAN = MockShellyLANClient(shouldSucceed: true)
        let mockServer = MockHomeNodeServerClient(shouldSucceed: true)
        let controller = ShellyPlugController(lanClient: mockLAN)

        controller.serverClient = mockServer
        controller.serverConfigProvider = {
            (config: ServerConfig(host: "192.168.1.100", port: 8080), isConnected: true)
        }

        let deviceId = UUID()
        let device = DiscoveredDevice(
            id: deviceId,
            name: "ShellyPlusPlugS-A0A3B3112233",
            rssi: -65,
            family: .shellyBlu,
            lanAddress: "192.168.1.50"
        )

        controller.setPower(for: device, isOn: true)

        // Allow any async task spawned by setPower to run
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Should use Server interface
        XCTAssertEqual(controller.getActiveInterface(for: deviceId), .server)
        XCTAssertTrue(controller.isPowerOn(for: deviceId))
        // LAN should not have been called because Server had top priority
        XCTAssertNil(mockLAN.lastSetHost)
    }

    @MainActor
    func testShellyMultiPathFallsBackToLANWhenServerDisconnected() async {
        let mockLAN = MockShellyLANClient(shouldSucceed: true)
        let mockServer = MockHomeNodeServerClient(shouldSucceed: true)
        let controller = ShellyPlugController(lanClient: mockLAN)

        controller.serverClient = mockServer
        controller.serverConfigProvider = {
            (config: ServerConfig(host: "192.168.1.100", port: 8080), isConnected: false)
        }

        let deviceId = UUID()
        let device = DiscoveredDevice(
            id: deviceId,
            name: "ShellyPlusPlugS-A0A3B3112233",
            rssi: -65,
            family: .shellyBlu,
            lanAddress: "192.168.1.50"
        )

        controller.setPower(for: device, isOn: true)

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Should use LAN interface
        XCTAssertEqual(controller.getActiveInterface(for: deviceId), .lan)
        XCTAssertTrue(controller.isPowerOn(for: deviceId))
        XCTAssertEqual(mockLAN.lastSetHost, "192.168.1.50")
        XCTAssertEqual(mockLAN.lastSetPower, true)
    }

    @MainActor
    func testShellyMultiPathFallsBackToBLEWhenLANFails() async {
        let mockLAN = MockShellyLANClient(shouldSucceed: false)
        let controller = ShellyPlugController(lanClient: mockLAN)

        // No server
        controller.serverConfigProvider = {
            (config: ServerConfig(host: "192.168.1.100", port: 8080), isConnected: false)
        }

        let deviceId = UUID()
        let device = DiscoveredDevice(
            id: deviceId,
            name: "ShellyPlusPlugS-A0A3B3112233",
            rssi: -65,
            family: .shellyBlu,
            lanAddress: "192.168.1.50"
        )

        controller.setPower(for: device, isOn: true)

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Because LAN failed, it falls back to BLE
        // In this unit test environment without actual CBPeripheral, activeInterface transitions to BLE
        XCTAssertEqual(controller.getActiveInterface(for: deviceId), .ble)
    }

    @MainActor
    func testShellyLANDeviceDiscoveryMatching() {
        let discovery = ShellyLANDiscoveryService()

        let record = ShellyLANRecord(
            id: "shellyplusplugs-a0a3b3112233._http._tcp.local.",
            name: "shellyplusplugs-a0a3b3112233",
            hostName: "shellyplusplugs-a0a3b3112233.local.",
            ipAddresses: ["192.168.1.85"],
            macSuffix: "A0A3B3112233"
        )
        discovery.discoveredShellys = [record]

        // 1. Test lookup by matching MAC
        let matchedHostByMAC = discovery.lookupHost(macAddress: "A0:A3:B3:11:22:33", name: nil)
        XCTAssertEqual(matchedHostByMAC, "192.168.1.85")

        // 2. Test lookup by matching name suffix
        let matchedHostByName = discovery.lookupHost(macAddress: nil, name: "ShellyPlugS-a0a3b3112233")
        XCTAssertEqual(matchedHostByName, "192.168.1.85")

        // 3. Test lookup unmatched returns nil
        let unmatched = discovery.lookupHost(macAddress: "FF:FF:FF:00:00:00", name: "OtherPlug")
        XCTAssertNil(unmatched)
    }
}
