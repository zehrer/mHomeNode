import Foundation
import CoreLocation

/// Detection method determining why a location is currently active
public enum LocationDetectionMethod: String, Codable, Sendable {
    case serverAndGps = "Server & GPS"
    case serverOnly = "Server in LAN"
    case gpsOnly = "GPS Position"
    case manualDefault = "Default Location"

    public var iconName: String {
        switch self {
        case .serverAndGps: return "house.and.flag.fill"
        case .serverOnly: return "network"
        case .gpsOnly: return "location.fill"
        case .manualDefault: return "house.fill"
        }
    }
}

/// Overall live detection state for presence
public enum ActiveLocationState: Equatable, Sendable {
    case detected(location: ManagedLocation, method: LocationDetectionMethod)
    case away(nearestLocation: ManagedLocation?, distanceMeters: Double?)
    case unknown

    public var title: String {
        switch self {
        case .detected(let loc, let method):
            return "\(loc.name) (\(method.rawValue))"
        case .away(let nearest, let dist):
            if let n = nearest, let d = dist {
                return "Away (~\(Int(d))m from \(n.name))"
            }
            return "Away from Home"
        case .unknown:
            return "Detecting Location..."
        }
    }

    public var iconName: String {
        switch self {
        case .detected(_, let method):
            return method.iconName
        case .away:
            return "figure.walk"
        case .unknown:
            return "location.slash"
        }
    }

    public var isAtHome: Bool {
        if case .detected = self { return true }
        return false
    }
}

/// Represents a configured site/place (e.g. "Home" / "Zuhause")
public struct ManagedLocation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Double
    public var associatedServerHost: String?
    public var associatedServerPort: Int?
    public var isDefault: Bool
    public var createdAt: Date
    public var devices: [LocationDeviceRecord]

    public init(
        id: UUID = UUID(),
        name: String = "Home",
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double = 150.0,
        associatedServerHost: String? = nil,
        associatedServerPort: Int? = 8080,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        devices: [LocationDeviceRecord] = []
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.associatedServerHost = associatedServerHost
        self.associatedServerPort = associatedServerPort
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.devices = devices
    }

    /// Checks if a given coordinate lies within this location's geofence
    public func containsCoordinate(lat: Double, lon: Double) -> Bool {
        guard let myLat = latitude, let myLon = longitude else { return false }
        let myLoc = CLLocation(latitude: myLat, longitude: myLon)
        let otherLoc = CLLocation(latitude: lat, longitude: lon)
        return myLoc.distance(from: otherLoc) <= radiusMeters
    }

    /// Distance in meters from a given coordinate, if coordinates are set
    public func distanceFrom(lat: Double, lon: Double) -> Double? {
        guard let myLat = latitude, let myLon = longitude else { return nil }
        let myLoc = CLLocation(latitude: myLat, longitude: myLon)
        let otherLoc = CLLocation(latitude: lat, longitude: lon)
        return myLoc.distance(from: otherLoc)
    }

    /// Checks if a discovered server host or IP matches this location
    public func matchesServer(host: String) -> Bool {
        guard let assoc = associatedServerHost, !assoc.isEmpty else { return false }
        let cleanAssoc = assoc.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanAssoc == cleanHost { return true }
        if cleanHost.contains(cleanAssoc) || cleanAssoc.contains(cleanHost) { return true }
        return false
    }

    /// Returns default initial Home location
    public static var defaultHome: ManagedLocation {
        ManagedLocation(
            id: UUID(),
            name: "Home",
            latitude: nil,
            longitude: nil,
            radiusMeters: 150.0,
            associatedServerHost: nil,
            associatedServerPort: 8080,
            isDefault: true,
            createdAt: Date(),
            devices: []
        )
    }
}
