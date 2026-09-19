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

    func testIdentifySamsungWasherAndTV() {
        // Samsung Company ID: 0x0075 -> [0x75, 0x00]
        let mfgWasher = Data([0x75, 0x00, 0x42, 0x0C, 0x83, 0x05])
        let resWasher = DeviceFingerprinter.identifyDetails(
            advertisedName: "Washer",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgWasher
        )
        XCTAssertEqual(resWasher.family, .samsung)
        XCTAssertEqual(resWasher.resolvedName, "Samsung Smart Washer")

        let mfgTV = Data([0x75, 0x00, 0x42, 0x04, 0x01, 0x20])
        let resTV = DeviceFingerprinter.identifyDetails(
            advertisedName: "[TV] Samsung 7 Series (55)",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgTV
        )
        XCTAssertEqual(resTV.family, .samsung)
    }

    func testIdentifyMicrosoftSwiftPair() {
        // Microsoft Company ID: 0x0006 -> [0x06, 0x00] + Swift Pair prefix [0x01, 0x09]
        let mfgMsft = Data([0x06, 0x00, 0x01, 0x09, 0x20, 0x22])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "Unknown",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgMsft
        )
        XCTAssertEqual(res.family, .microsoft)
        XCTAssertEqual(res.resolvedName, "Windows PC (Swift Pair)")
    }

    func testIdentifyAppleMacBookAndFindMy() {
        let resMac = DeviceFingerprinter.identifyDetails(
            advertisedName: "MacBook Pro M2",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: nil
        )
        XCTAssertEqual(resMac.family, .apple)
        XCTAssertEqual(resMac.resolvedName, "MacBook Pro M2")

        let resFindMy = DeviceFingerprinter.identifyDetails(
            advertisedName: "Find My Accessory",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: nil
        )
        XCTAssertEqual(resFindMy.family, .apple)
    }

    func testIdentifySmartLight() {
        // ELK-BLEDDM Company ID: 0x0642 -> [0x42, 0x06]
        let mfgElk = Data([0x42, 0x06])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "ELK-BLEDDM",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgElk
        )
        XCTAssertEqual(res.family, .smartLight)
    }

    func testIdentifyTuyaTelink() {
        let mfgTuya = Data([0xA4, 0xC1, 0x38, 0x67, 0x18, 0x23])
        let svcFFF0 = CBUUID(string: "FFF0")
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "Unknown",
            serviceUUIDs: [svcFFF0],
            serviceData: nil,
            manufacturerData: mfgTuya
        )
        XCTAssertEqual(res.family, .tuya)
        XCTAssertEqual(res.macAddress, "A4:C1:38:67:18:23")
    }

    func testIdentifyJBLAudio() {
        // JBL Company ID: 0x2982 -> [0x82, 0x29]
        let mfgJBL = Data([0x82, 0x29, 0xE3, 0xDF])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "JBL Quantum 950-LE",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgJBL
        )
        XCTAssertEqual(res.family, .audio)
    }
}
