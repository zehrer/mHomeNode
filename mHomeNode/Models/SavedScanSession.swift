import Foundation

/// Geographic location associated with a saved BLE scan snapshot
public struct ScanLocation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let horizontalAccuracy: Double?
    public let placeName: String?

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        placeName: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.placeName = placeName
    }

    /// Formatted coordinates (e.g. "48.1371° N, 11.5754° E")
    public var formattedCoordinates: String {
        let latDirection = latitude >= 0 ? "N" : "S"
        let lonDirection = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", abs(latitude), latDirection, abs(longitude), lonDirection)
    }

    /// Formatted accuracy (e.g. "±5m")
    public var formattedAccuracy: String? {
        guard let acc = horizontalAccuracy, acc >= 0 else { return nil }
        return String(format: "±%.0fm", acc)
    }

    /// Display title: Placename if available, otherwise coordinates
    public var displayTitle: String {
        if let place = placeName, !place.isEmpty {
            return place
        }
        return formattedCoordinates
    }
}

/// A captured snapshot of discovered BLE devices and sensor telemetry at a specific point in time and location
public struct SavedScanSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var timestamp: Date
    public var location: ScanLocation?
    public var note: String?
    public var devices: [DiscoveredDevice]
    public var scoutName: String

    public init(
        id: UUID = UUID(),
        title: String,
        timestamp: Date = Date(),
        location: ScanLocation? = nil,
        note: String? = nil,
        devices: [DiscoveredDevice],
        scoutName: String = "iPhone (mHomeNode)"
    ) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.location = location
        self.note = note
        self.devices = devices
        self.scoutName = scoutName
    }

    public var deviceCount: Int {
        devices.count
    }

    public var activeDeviceCount: Int {
        devices.filter { $0.isCurrentlyActive }.count
    }

    /// Exports the scan session as a human-readable text report
    public func exportSummary() -> String {
        var lines: [String] = []
        lines.append("mHomeNode BLE Scan Report")
        lines.append("Title: \(title)")
        lines.append("Date: \(timestamp.formatted(date: .abbreviated, time: .standard))")
        if let loc = location {
            lines.append("Location: \(loc.displayTitle)")
            lines.append("Coordinates: \(loc.formattedCoordinates)\(loc.formattedAccuracy.map { " (\($0))" } ?? "")")
        }
        if let n = note, !n.isEmpty {
            lines.append("Notes: \(n)")
        }
        lines.append("Total Devices: \(devices.count) (\(activeDeviceCount) active)")
        lines.append(String(repeating: "-", count: 60))

        for dev in devices {
            var devLine = "- \(dev.displayTitle) [\(dev.family.rawValue)] | RSSI: \(dev.rssi) dBm"
            if let mac = dev.macAddress {
                devLine += " | MAC: \(mac)"
            }
            if let t = dev.btHomeData?.temperature {
                devLine += String(format: " | Temp: %.1f°C", t)
            }
            if let h = dev.btHomeData?.humidity {
                devLine += String(format: " | Hum: %.0f%%", h)
            }
            if let bat = dev.btHomeData?.battery {
                devLine += " | Battery: \(bat)%"
            }
            lines.append(devLine)
        }

        return lines.joined(separator: "\n")
    }

    /// Serializes session to formatted JSON Data
    public func exportJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }
}
