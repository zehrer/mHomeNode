import XCTest
@testable import mHomeNode

final class ShellyPlugTests: XCTestCase {

    @MainActor
    func testShellyPlugDetection() {
        let shellySG3 = DiscoveredDevice(id: UUID(), name: "ShellyPlugSG3-543204689994", rssi: -60, family: .shellyBlu)
        XCTAssertTrue(shellySG3.isSwitchablePlug)

        let shellyPlus1 = DiscoveredDevice(id: UUID(), name: "ShellyPlus1-441793A8302C", rssi: -62, family: .shellyBlu)
        XCTAssertTrue(shellyPlus1.isSwitchablePlug)

        let genericPlug = DiscoveredDevice(id: UUID(), name: "Living Room Plug", rssi: -70, family: .standardBLE)
        XCTAssertTrue(genericPlug.isSwitchablePlug)

        let sensor = DiscoveredDevice(id: UUID(), name: "Qingping Temp", rssi: -75, family: .qingping)
        XCTAssertFalse(sensor.isSwitchablePlug)

        let tv = DiscoveredDevice(id: UUID(), name: "[TV] Samsung Q7 Series (55)", rssi: -80, family: .samsung)
        XCTAssertFalse(tv.isSwitchablePlug)
    }

    @MainActor
    func testShellyPlugControllerPowerToggle() {
        let controller = ShellyPlugController()
        let deviceId = UUID()

        XCTAssertFalse(controller.isPowerOn(for: deviceId))

        controller.setPower(for: deviceId, isOn: true)
        XCTAssertTrue(controller.isPowerOn(for: deviceId))

        controller.togglePower(for: deviceId)
        XCTAssertFalse(controller.isPowerOn(for: deviceId))

        controller.togglePower(for: deviceId)
        XCTAssertTrue(controller.isPowerOn(for: deviceId))
    }
}
