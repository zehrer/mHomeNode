import Foundation
import SwiftUI

public enum DeviceGroupingMode: String, CaseIterable, Sendable, Identifiable, Codable {
    case none = "None"
    case proximity = "By Distance"
    case category = "By Category"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .none: return "list.bullet"
        case .proximity: return "location.circle"
        case .category: return "square.grid.2x2"
        }
    }
}

public enum DeviceCategory: String, CaseIterable, Sendable, Identifiable {
    case climateAndSensors = "Climate & Sensors"
    case lighting = "Lighting & Switches"
    case appliancesAndTV = "Home Appliances & TVs"
    case computersAndPhones = "Computers & Mobile"
    case audio = "Audio & Accessories"
    case other = "Other BLE Devices"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .climateAndSensors: return "thermometer.medium"
        case .lighting: return "lightbulb.fill"
        case .appliancesAndTV: return "tv.fill"
        case .computersAndPhones: return "laptopcomputer.and.iphone"
        case .audio: return "headphones"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

public enum ProximityTier: String, CaseIterable, Sendable, Identifiable {
    case inRoom = "In Room (> -70 dBm)"
    case nearby = "Nearby (-70 to -85 dBm)"
    case distant = "Distant / Weak (< -85 dBm)"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .inRoom: return "antenna.radiowaves.left.and.right"
        case .nearby: return "wave.3.forward"
        case .distant: return "dot.radiowaves.forward"
        }
    }
}

public struct DeviceGroupSection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let iconName: String
    public let devices: [DiscoveredDevice]

    public init(id: String, title: String, iconName: String, devices: [DiscoveredDevice]) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.devices = devices
    }
}

public enum DeviceGroupingHelper {
    public static func proximityTier(for device: DiscoveredDevice) -> ProximityTier {
        if device.rssi >= -70 {
            return .inRoom
        } else if device.rssi >= -85 {
            return .nearby
        } else {
            return .distant
        }
    }

    public static func category(for device: DiscoveredDevice) -> DeviceCategory {
        // If device has decoded BTHome sensor telemetry, it is a climate/sensor
        if device.btHomeData != nil {
            return .climateAndSensors
        }

        let lowName = (device.displayTitle + " " + device.name).lowercased()

        // Audio devices (including AirPods, headphones, speakers)
        if device.family == .audio || device.family == .sony || device.family == .bose ||
            lowName.contains("airpod") || lowName.contains("earbuds") || lowName.contains("headphone") ||
            lowName.contains("speaker") || lowName.contains("sound") {
            return .audio
        }

        // Climate & environmental sensors
        if device.family == .shellyBlu || device.family == .qingping || device.family == .xiaomi ||
            device.family == .btHomeGeneric || device.family == .ruuvi ||
            lowName.contains("temp") || lowName.contains("hygro") || lowName.contains("climate") ||
            lowName.contains("sensor") || lowName.contains("weather") || lowName.contains("baro") {
            return .climateAndSensors
        }

        // Lighting & switches
        if device.family == .smartLight || device.family == .switchBot || device.isLightingDevice ||
            lowName.contains("strip") || lowName.contains("lamp") || lowName.contains("bulb") || lowName.contains("light") {
            return .lighting
        }

        // Home Appliances, TVs, Locks & Power
        if device.family == .samsung || device.family == .nuki || device.family == .ecoflow ||
            lowName.contains("tv") || lowName.contains("washer") || lowName.contains("dryer") ||
            lowName.contains("refrigerator") || lowName.contains("fridge") || lowName.contains("lock") {
            return .appliancesAndTV
        }

        // Computers, Tablets, Phones, Smartwatches
        if device.family == .apple || device.family == .microsoft || device.family == .google || device.family == .garmin ||
            lowName.contains("macbook") || lowName.contains("imac") || lowName.contains("windows") ||
            lowName.contains("pc") || lowName.contains("phone") || lowName.contains("ipad") || lowName.contains("watch") {
            return .computersAndPhones
        }

        // Tuya / Telink
        if device.family == .tuya {
            return .appliancesAndTV
        }

        if device.family == .govee {
            return .lighting
        }

        return .other
    }

    public static func group(
        devices: [DiscoveredDevice],
        mode: DeviceGroupingMode
    ) -> [DeviceGroupSection] {
        switch mode {
        case .none:
            return [
                DeviceGroupSection(
                    id: "all",
                    title: "Devices",
                    iconName: "antenna.radiowaves.left.and.right",
                    devices: devices
                )
            ]

        case .proximity:
            var sections: [DeviceGroupSection] = []
            for tier in ProximityTier.allCases {
                let matches = devices.filter { proximityTier(for: $0) == tier }
                if !matches.isEmpty {
                    sections.append(
                        DeviceGroupSection(
                            id: tier.rawValue,
                            title: tier.rawValue,
                            iconName: tier.systemImage,
                            devices: matches
                        )
                    )
                }
            }
            return sections

        case .category:
            var sections: [DeviceGroupSection] = []
            for cat in DeviceCategory.allCases {
                let matches = devices.filter { category(for: $0) == cat }
                if !matches.isEmpty {
                    sections.append(
                        DeviceGroupSection(
                            id: cat.rawValue,
                            title: cat.rawValue,
                            iconName: cat.systemImage,
                            devices: matches
                        )
                    )
                }
            }
            return sections
        }
    }
}
