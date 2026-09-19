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

    func testIdentifyRuuviTagFormat5() {
        // Ruuvi Company ID: 0x0499 -> [0x99, 0x04]
        // Format: 0x05
        // Temp: 24.30 °C -> 24.30 / 0.005 = 4860 = 0x12FC
        // Hum: 53.40% -> 53.40 / 0.0025 = 21360 = 0x5370
        // Pressure: 1013.25 hPa -> (101325 - 50000) = 51325 = 0xC87D
        // Acceleration: X=0, Y=0, Z=1000 -> 6 bytes
        // Battery power info: 3000 mV -> (3000 - 1600) << 5 = 1400 << 5 = 44800 = 0xAF00
        // Movement counter + seq: 2 bytes
        // MAC: C1:22:33:44:55:66
        var mfg = Data([0x99, 0x04, 0x05, 0x12, 0xFC, 0x53, 0x70, 0xC8, 0x7D])
        mfg.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x03, 0xE8]) // accel
        mfg.append(contentsOf: [0xAF, 0x00]) // power info
        mfg.append(contentsOf: [0x01, 0x02]) // counter & seq
        mfg.append(contentsOf: [0xC1, 0x22, 0x33, 0x44, 0x55, 0x66]) // MAC

        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "Ruuvi 5566",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfg
        )
        XCTAssertEqual(res.family, .ruuvi)
        XCTAssertEqual(res.macAddress, "C1:22:33:44:55:66")
        XCTAssertNotNil(res.btHomeData)
        if let data = res.btHomeData {
            XCTAssertEqual(data.temperature ?? 0, 24.30, accuracy: 0.01)
            XCTAssertEqual(data.humidity ?? 0, 53.40, accuracy: 0.01)
            XCTAssertEqual(data.pressure ?? 0, 1013.25, accuracy: 0.1)
            XCTAssertEqual(data.battery, 100)
        }
    }

    func testIdentifyGoogleFastPair() {
        // Fast Pair Service UUID 0xFE2C
        let svc = CBUUID(string: "FE2C")
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "Pixel Buds Pro",
            serviceUUIDs: [svc],
            serviceData: nil,
            manufacturerData: nil
        )
        XCTAssertEqual(res.family, .google)
    }

    func testIdentifySonyAudio() {
        // Sony Company ID 0x0046 -> [0x46, 0x00]
        let mfgSony = Data([0x46, 0x00, 0x01, 0x02])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "WH-1000XM5",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgSony
        )
        XCTAssertEqual(res.family, .audio)
    }

    func testIdentifyBoseAudio() {
        // Bose Company ID 0x009E -> [0x9E, 0x00]
        let mfgBose = Data([0x9E, 0x00, 0x10, 0x20])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "Bose QC45",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgBose
        )
        XCTAssertEqual(res.family, .audio)
    }

    func testIdentifyGarmin() {
        // Garmin Company ID 0x0087 -> [0x87, 0x00]
        let mfgGarmin = Data([0x87, 0x00, 0x05])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "Forerunner 965",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgGarmin
        )
        XCTAssertEqual(res.family, .garmin)
    }

    func testIdentifyGoveeCompanyID() {
        // Govee Company ID 0xEC88 -> [0x88, 0xEC]
        let mfgGovee = Data([0x88, 0xEC, 0x01, 0x02, 0x03])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "ihoment_H6159",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgGovee
        )
        XCTAssertEqual(res.family, .govee)
    }

    func testIdentifyNordicDev() {
        // Nordic Company ID 0x0059 -> [0x59, 0x00]
        let mfgNordic = Data([0x59, 0x00, 0xAA, 0xBB])
        let res = DeviceFingerprinter.identifyDetails(
            advertisedName: "nRF52840_Beacon",
            serviceUUIDs: nil,
            serviceData: nil,
            manufacturerData: mfgNordic
        )
        XCTAssertEqual(res.family, .nordic)
    }
}
