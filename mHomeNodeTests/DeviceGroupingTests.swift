import XCTest
@testable import mHomeNode

final class DeviceGroupingTests: XCTestCase {

    func testProximityTiering() {
        let devRoom = DiscoveredDevice(id: UUID(), name: "Sensor", rssi: -65)
        let devNearby = DiscoveredDevice(id: UUID(), name: "Light", rssi: -78)
        let devDistant = DiscoveredDevice(id: UUID(), name: "Neighbor TV", rssi: -92)

        XCTAssertEqual(DeviceGroupingHelper.proximityTier(for: devRoom), .inRoom)
        XCTAssertEqual(DeviceGroupingHelper.proximityTier(for: devNearby), .nearby)
        XCTAssertEqual(DeviceGroupingHelper.proximityTier(for: devDistant), .distant)
    }

    func testCategoryClassification() {
        let sensorWithBTHome = DiscoveredDevice(
            id: UUID(),
            name: "Living Room Climate",
            rssi: -60,
            btHomeData: BTHomeData(temperature: 21.5, humidity: 45.0)
        )
        XCTAssertEqual(DeviceGroupingHelper.category(for: sensorWithBTHome), .climateAndSensors)

        let shelly = DiscoveredDevice(id: UUID(), name: "Shelly BLU Door", rssi: -70, family: .shellyBlu)
        XCTAssertEqual(DeviceGroupingHelper.category(for: shelly), .climateAndSensors)

        let ruuvi = DiscoveredDevice(id: UUID(), name: "RuuviTag", rssi: -75, family: .ruuvi)
        XCTAssertEqual(DeviceGroupingHelper.category(for: ruuvi), .climateAndSensors)

        let light = DiscoveredDevice(id: UUID(), name: "RGB LED Strip", rssi: -70, family: .smartLight)
        XCTAssertEqual(DeviceGroupingHelper.category(for: light), .lighting)

        let govee = DiscoveredDevice(id: UUID(), name: "Govee H70B5", rssi: -72, family: .govee)
        XCTAssertEqual(DeviceGroupingHelper.category(for: govee), .lighting)

        let tv = DiscoveredDevice(id: UUID(), name: "Samsung 7 Series", rssi: -80, family: .samsung)
        XCTAssertEqual(DeviceGroupingHelper.category(for: tv), .appliancesAndTV)

        let macbook = DiscoveredDevice(id: UUID(), name: "MacBook Pro M2", rssi: -50, family: .apple)
        XCTAssertEqual(DeviceGroupingHelper.category(for: macbook), .computersAndPhones)

        let pc = DiscoveredDevice(id: UUID(), name: "Gaming Rig", rssi: -68, family: .microsoft)
        XCTAssertEqual(DeviceGroupingHelper.category(for: pc), .computersAndPhones)

        let audio = DiscoveredDevice(id: UUID(), name: "JBL Flip 6", rssi: -60, family: .audio)
        XCTAssertEqual(DeviceGroupingHelper.category(for: audio), .audio)

        let airpods = DiscoveredDevice(id: UUID(), name: "Stephan's AirPods Pro", rssi: -55, family: .apple)
        XCTAssertEqual(DeviceGroupingHelper.category(for: airpods), .audio)

        let raw = DiscoveredDevice(id: UUID(), name: "Unknown", rssi: -90, family: .standardBLE)
        XCTAssertEqual(DeviceGroupingHelper.category(for: raw), .other)
    }

    func testGroupingProximitySections() {
        let dev1 = DiscoveredDevice(id: UUID(), name: "Dev1", rssi: -50)
        let dev2 = DiscoveredDevice(id: UUID(), name: "Dev2", rssi: -75)
        let dev3 = DiscoveredDevice(id: UUID(), name: "Dev3", rssi: -95)

        let sections = DeviceGroupingHelper.group(devices: [dev1, dev2, dev3], mode: .proximity)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].title, ProximityTier.inRoom.rawValue)
        XCTAssertEqual(sections[0].devices.count, 1)
        XCTAssertEqual(sections[1].title, ProximityTier.nearby.rawValue)
        XCTAssertEqual(sections[1].devices.count, 1)
        XCTAssertEqual(sections[2].title, ProximityTier.distant.rawValue)
        XCTAssertEqual(sections[2].devices.count, 1)
    }

    func testGroupingCategorySections() {
        let sensor = DiscoveredDevice(id: UUID(), name: "Temp Sensor", rssi: -60, family: .shellyBlu)
        let light = DiscoveredDevice(id: UUID(), name: "Smart Bulb", rssi: -70, family: .smartLight)

        let sections = DeviceGroupingHelper.group(devices: [sensor, light], mode: .category)
        XCTAssertEqual(sections.count, 2)
        XCTAssertTrue(sections.contains(where: { $0.title == DeviceCategory.climateAndSensors.rawValue }))
        XCTAssertTrue(sections.contains(where: { $0.title == DeviceCategory.lighting.rawValue }))
    }

    func testGroupingNoneMode() {
        let dev1 = DiscoveredDevice(id: UUID(), name: "Dev1", rssi: -50)
        let dev2 = DiscoveredDevice(id: UUID(), name: "Dev2", rssi: -75)

        let sections = DeviceGroupingHelper.group(devices: [dev1, dev2], mode: .none)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].devices.count, 2)
    }
}
