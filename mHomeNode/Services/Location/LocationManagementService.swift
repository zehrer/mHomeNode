import Foundation
import CoreLocation
import OSLog

/// Service responsible for managing locations ("Home", "Office", etc.),
/// evaluating live presence (via HomeNode server & GPS), and persisting device-to-room registries.
@Observable
@MainActor
public final class LocationManagementService {
    public static let shared = LocationManagementService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "LocationManagementService")
    private let fileURL: URL

    public var locations: [ManagedLocation] = []
    public var activeLocationState: ActiveLocationState = .unknown

    public init(customFileURL: URL? = nil) {
        if let custom = customFileURL {
            self.fileURL = custom
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("mHomeNode", isDirectory: true)
            if !fileManager.fileExists(atPath: appFolder.path) {
                try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }
            self.fileURL = appFolder.appendingPathComponent("managed_locations.json")
        }

        self.locations = loadLocationsFromDisk()
        if self.locations.isEmpty {
            let def = ManagedLocation.defaultHome
            self.locations = [def]
            saveLocationsToDisk()
        }
        recalculateActiveState(currentLocation: nil, activeServerHost: nil)
    }

    // MARK: - Active Location Resolution

    /// Returns the currently active location (or the default location if away/unknown)
    public var activeLocation: ManagedLocation {
        switch activeLocationState {
        case .detected(let loc, _):
            return loc
        case .away(let nearest, _):
            return nearest ?? defaultLocation
        case .unknown:
            return defaultLocation
        }
    }

    public var defaultLocation: ManagedLocation {
        locations.first(where: { $0.isDefault }) ?? locations.first ?? ManagedLocation.defaultHome
    }

    /// Evaluates current presence against all locations using discovered server host and current GPS
    public func recalculateActiveState(currentLocation: ScanLocation?, activeServerHost: String?) {
        let cleanServer = activeServerHost?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check for combined Server & GPS matches
        for loc in locations {
            let hasServer = (cleanServer != nil && !cleanServer!.isEmpty && loc.matchesServer(host: cleanServer!))
            var hasGps = false
            if let gps = currentLocation {
                hasGps = loc.containsCoordinate(lat: gps.latitude, lon: gps.longitude)
            }

            if hasServer && hasGps {
                self.activeLocationState = .detected(location: loc, method: .serverAndGps)
                logger.info("Detected location '\(loc.name)' via Server & GPS")
                return
            }
        }

        // 2. Check for Server match (strong local network presence)
        if let srv = cleanServer, !srv.isEmpty {
            for loc in locations {
                if loc.matchesServer(host: srv) {
                    self.activeLocationState = .detected(location: loc, method: .serverOnly)
                    logger.info("Detected location '\(loc.name)' via Server in LAN (\(srv))")
                    return
                }
            }
        }

        // 3. Check for GPS match
        if let gps = currentLocation {
            for loc in locations {
                if loc.containsCoordinate(lat: gps.latitude, lon: gps.longitude) {
                    self.activeLocationState = .detected(location: loc, method: .gpsOnly)
                    logger.info("Detected location '\(loc.name)' via GPS coordinates")
                    return
                }
            }

            // Outside all geofences -> Away
            var nearestLoc: ManagedLocation?
            var shortestDist: Double = .infinity

            for loc in locations {
                if let d = loc.distanceFrom(lat: gps.latitude, lon: gps.longitude), d < shortestDist {
                    shortestDist = d
                    nearestLoc = loc
                }
            }

            if shortestDist < .infinity {
                self.activeLocationState = .away(nearestLocation: nearestLoc, distanceMeters: shortestDist)
                return
            }
        }

        // 4. Fallback to default location if neither server nor GPS available
        if let def = locations.first(where: { $0.isDefault }) {
            self.activeLocationState = .detected(location: def, method: .manualDefault)
        } else {
            self.activeLocationState = .unknown
        }
    }

    // MARK: - Device Registry Operations

    /// Registers or updates a device record at the active or specified location
    public func registerDevice(
        locationId: UUID? = nil,
        deviceId: String,
        customName: String?,
        room: String?,
        family: String
    ) {
        let targetId = locationId ?? activeLocation.id
        guard let idx = locations.firstIndex(where: { $0.id == targetId }) else { return }

        let normId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let devIdx = locations[idx].devices.firstIndex(where: { $0.id.uppercased() == normId }) {
            locations[idx].devices[devIdx].customName = customName ?? locations[idx].devices[devIdx].customName
            locations[idx].devices[devIdx].assignedRoom = room ?? locations[idx].devices[devIdx].assignedRoom
            locations[idx].devices[devIdx].vendorFamily = family
            locations[idx].devices[devIdx].lastSeenAt = Date()
        } else {
            let record = LocationDeviceRecord(
                id: normId,
                customName: customName,
                assignedRoom: room,
                vendorFamily: family,
                firstRegistered: Date(),
                lastSeenAt: Date()
            )
            locations[idx].devices.append(record)
        }

        saveLocationsToDisk()
        logger.info("Registered/updated device \(normId) in location '\(self.locations[idx].name)'")
    }

    /// Looks up a registered device in the active location (or across all locations if not found in active)
    public func lookupDevice(deviceId: String) -> LocationDeviceRecord? {
        let norm = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // First check active location
        if let found = activeLocation.devices.first(where: { $0.id.uppercased() == norm }) {
            return found
        }

        // Fallback to any location
        for loc in locations {
            if let found = loc.devices.first(where: { $0.id.uppercased() == norm }) {
                return found
            }
        }
        return nil
    }

    /// Updates last-seen timestamp of a device without mutating name or room
    public func markDeviceSeen(deviceId: String) {
        let norm = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for lIdx in 0..<locations.count {
            if let dIdx = locations[lIdx].devices.firstIndex(where: { $0.id.uppercased() == norm }) {
                locations[lIdx].devices[dIdx].lastSeenAt = Date()
                saveLocationsToDisk()
                return
            }
        }
    }

    /// Removes a device from a location's registry
    public func unregisterDevice(locationId: UUID, deviceId: String) {
        guard let idx = locations.firstIndex(where: { $0.id == locationId }) else { return }
        let norm = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        locations[idx].devices.removeAll(where: { $0.id.uppercased() == norm })
        saveLocationsToDisk()
        logger.info("Removed device \(norm) from location '\(self.locations[idx].name)'")
    }

    /// Migrates a registered device from an old identifier to a new identifier (e.g. after BLE RPA rotation)
    public func migrateDeviceId(oldDeviceId: String, newDeviceId: String) {
        let oldNorm = oldDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let newNorm = newDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !oldNorm.isEmpty && !newNorm.isEmpty && oldNorm != newNorm else { return }

        var didChange = false
        for lIdx in 0..<locations.count {
            if let oldIdx = locations[lIdx].devices.firstIndex(where: { $0.id.uppercased() == oldNorm }) {
                if let newIdx = locations[lIdx].devices.firstIndex(where: { $0.id.uppercased() == newNorm }) {
                    if locations[lIdx].devices[newIdx].assignedRoom == nil {
                        locations[lIdx].devices[newIdx].assignedRoom = locations[lIdx].devices[oldIdx].assignedRoom
                    }
                    if locations[lIdx].devices[newIdx].customName == nil {
                        locations[lIdx].devices[newIdx].customName = locations[lIdx].devices[oldIdx].customName
                    }
                    locations[lIdx].devices.remove(at: oldIdx)
                } else {
                    let oldRec = locations[lIdx].devices[oldIdx]
                    locations[lIdx].devices[oldIdx] = LocationDeviceRecord(
                        id: newNorm,
                        customName: oldRec.customName,
                        assignedRoom: oldRec.assignedRoom,
                        vendorFamily: oldRec.vendorFamily,
                        firstRegistered: oldRec.firstRegistered,
                        lastSeenAt: Date()
                    )
                }
                didChange = true
                logger.info("Migrated device record in location '\(self.locations[lIdx].name)' from \(oldNorm) to \(newNorm)")
            }
        }
        if didChange {
            saveLocationsToDisk()
        }
    }

    // MARK: - Location CRUD

    public func saveLocation(_ location: ManagedLocation) {
        if let idx = locations.firstIndex(where: { $0.id == location.id }) {
            locations[idx] = location
        } else {
            locations.append(location)
        }
        saveLocationsToDisk()
    }

    public func deleteLocation(id: UUID) {
        guard locations.count > 1 else { return } // Keep at least one location
        locations.removeAll(where: { $0.id == id })
        if !locations.contains(where: { $0.isDefault }) {
            locations[0].isDefault = true
        }
        saveLocationsToDisk()
    }

    public func setDefault(id: UUID) {
        for idx in 0..<locations.count {
            locations[idx].isDefault = (locations[idx].id == id)
        }
        saveLocationsToDisk()
    }

    public func updateCoordinates(locationId: UUID, latitude: Double, longitude: Double, radius: Double? = nil) {
        guard let idx = locations.firstIndex(where: { $0.id == locationId }) else { return }
        locations[idx].latitude = latitude
        locations[idx].longitude = longitude
        if let r = radius {
            locations[idx].radiusMeters = r
        }
        saveLocationsToDisk()
    }

    public func updateAssociatedServer(locationId: UUID, host: String, port: Int? = 8080) {
        guard let idx = locations.firstIndex(where: { $0.id == locationId }) else { return }
        locations[idx].associatedServerHost = host
        locations[idx].associatedServerPort = port
        saveLocationsToDisk()
    }

    // MARK: - Disk Persistence

    private func loadLocationsFromDisk() -> [ManagedLocation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ManagedLocation].self, from: data)
        } catch {
            logger.error("Failed to load managed locations from disk: \(error.localizedDescription)")
            return []
        }
    }

    private func saveLocationsToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(locations)
            try data.write(to: fileURL, options: [.atomicWrite])
        } catch {
            logger.error("Failed to save managed locations to disk: \(error.localizedDescription)")
        }
    }
}
