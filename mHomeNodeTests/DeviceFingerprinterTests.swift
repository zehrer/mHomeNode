import XCTest
import CoreBluetooth
@testable import mHomeNode

final class DeviceFingerprinterTests: XCTestCase {

    func testIdentifyShellyBlu() {
        let (family, _) = DeviceFingerprinter.identify(
            advertisedName: "Shelly BLU Door/Window",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: nil
        )
        XCTAssertEqual(family, .shellyBlu)
    }

    func testIdentifyQingping() {
        let (family, _) = DeviceFingerprinter.identify(
            advertisedName: "Qingping Temp RH Baro",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: nil
        )
        XCTAssertEqual(family, .qingping)
    }

    func testIdentifyBTHomeByServiceUUID() {
        let bthomeUUID = CBUUID(string: "FCD2")
        let (family, _) = DeviceFingerprinter.identify(
            advertisedName: "Unknown Sensor",
            serviceUUIDs: [bthomeUUID],
            serviceData: nil,
            manufacturerData: nil
        )
        XCTAssertEqual(family, .btHomeGeneric)
    }
}
