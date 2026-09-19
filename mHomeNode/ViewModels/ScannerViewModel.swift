import Foundation
import SwiftUI

public enum DeviceSortOrder: String, CaseIterable, Identifiable {
    case rssi = "Signal Strength"
    case name = "Name"
    case lastSeen = "Recently Seen"

    public var id: String { rawValue }
}

@Observable
@MainActor
public final class ScannerViewModel {
    public let bleService: BLEScannerService
    public let ignoreService: IgnoreService
    public let discoveryService: HomeNodeDiscoveryService
    public let serverClient: HomeNodeServerClientProtocol
    public let locationService: LocationService
    public let savedScanStorage: SavedScanStorageService

    public var serverConfig: ServerConfig = ServerConfig()
    public var serverRooms: [ServerRoom] = []
    public var savedScans: [SavedScanSession] = []

    public var searchText: String = ""
    public var onlyKnownDevices: Bool = false
    public var showIgnoredDevices: Bool = false
    public var minRSSI: Double = -120
    public var sortOrder: DeviceSortOrder = .rssi

    public var isSyncing: Bool = false
    public var syncMessage: String?

    public init(
        bleService: BLEScannerService? = nil,
        ignoreService: IgnoreService? = nil,
        discoveryService: HomeNodeDiscoveryService? = nil,
        serverClient: HomeNodeServerClientProtocol = LiveHomeNodeServerClient(),
        locationService: LocationService? = nil,
        savedScanStorage: SavedScanStorageService? = nil
    ) {
        let ign = ignoreService ?? .shared
        self.ignoreService = ign
        let ble = bleService ?? BLEScannerService(ignoreService: ign)
        self.bleService = ble
        let disc = discoveryService ?? .shared
        self.discoveryService = disc
        self.serverClient = serverClient
        self.locationService = locationService ?? LocationService()
        let storage = savedScanStorage ?? .shared
        self.savedScanStorage = storage
        self.savedScans = storage.loadSessions()

        disc.onServerDiscovered = { [weak self] server in
            guard let self = self else { return }
            self.serverConfig.host = server.preferredHost
            self.serverConfig.port = server.port
            Task { @MainActor in
                await self.loadServerRooms()
            }
        }
        disc.startBrowsing()

        // Auto-start duty-cycled burst scanning on launch to discover devices while preserving battery
        ble.startBurstScan(activeDuration: 4.0, pauseDuration: 4.0)

        // Initial room load
        Task { [weak self] in
            await self?.loadServerRooms()
        }
    }

    public var isScanning: Bool {
        bleService.isScanning || bleService.isBurstScanning
    }

    public func pauseScanning() {
        bleService.pauseScan()
    }

    public func resumeScanning() {
        bleService.resumeScan()
    }

    public var bluetoothStateText: String {
        bleService.bluetoothState.description
    }

    public var activeDevicesCount: Int {
        bleService.devices.filter { !$0.isIgnored && $0.isCurrentlyActive }.count
    }

    public var totalDevicesCount: Int {
        bleService.devices.filter { !$0.isIgnored }.count
    }

    public var filteredDevices: [DiscoveredDevice] {
        let list = bleService.devices.filter { device in
            // Filter out ignored devices unless user explicitly enabled showIgnoredDevices
            if !showIgnoredDevices && device.isIgnored {
                return false
            }
            if onlyKnownDevices && device.family == .standardBLE {
                return false
            }
            if Double(device.rssi) < minRSSI {
                return false
            }
            if !searchText.isEmpty {
                let matchesName = device.displayTitle.localizedCaseInsensitiveContains(searchText)
                let matchesUUID = device.id.uuidString.localizedCaseInsensitiveContains(searchText)
                let matchesMac = (device.macAddress ?? "").localizedCaseInsensitiveContains(searchText)
                let matchesRoom = (device.assignedRoom ?? "").localizedCaseInsensitiveContains(searchText)
                return matchesName || matchesUUID || matchesMac || matchesRoom
            }
            return true
        }

        // Stable sorting with secondary UUID tie-breaker to prevent UI flickering
        switch sortOrder {
        case .rssi:
            return list.sorted {
                if $0.rssi != $1.rssi {
                    return $0.rssi > $1.rssi
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .name:
            return list.sorted {
                let cmp = $0.displayTitle.localizedCompare($1.displayTitle)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .lastSeen:
            return list.sorted {
                if $0.lastSeen != $1.lastSeen {
                    return $0.lastSeen > $1.lastSeen
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    public func toggleScan() {
        if isScanning {
            bleService.stopScan()
        } else {
            bleService.startScan()
        }
    }

    public func clear() {
        bleService.clear()
    }

    public func selectDiscoveredServer(_ server: DiscoveredHomeNodeServer) {
        discoveryService.activeServer = server
        serverConfig.host = server.preferredHost
        serverConfig.port = server.port
        Task {
            await loadServerRooms()
        }
    }

    public func loadServerRooms() async {
        do {
            let rooms = try await serverClient.fetchRooms(config: serverConfig)
            self.serverRooms = rooms
        } catch {
            // Server may be unavailable, keep existing or fallback
        }
    }

    public func renameAndClaimDevice(_ device: DiscoveredDevice, newName: String?, newRoom: String?) async -> Bool {
        bleService.updateDeviceName(id: device.id, customName: newName)
        bleService.updateRoom(for: device.id, room: newRoom)

        let identifier = device.macAddress ?? device.id.uuidString
        do {
            let success = try await serverClient.claimDevice(
                config: serverConfig,
                id: identifier,
                name: newName,
                room: newRoom,
                family: device.family.rawValue
            )
            return success
        } catch {
            return false
        }
    }

    public func ignoreDevice(_ device: DiscoveredDevice, reason: String = "User Ignored") {
        let identifier = device.macAddress ?? device.id.uuidString
        ignoreService.ignore(id: identifier, name: device.name, reason: reason)
        bleService.setDeviceIgnored(id: device.id, isIgnored: true)

        Task {
            let _ = try? await serverClient.ignoreDeviceOnServer(
                config: serverConfig,
                id: identifier,
                name: device.name,
                reason: reason
            )
        }
    }

    public func unignoreDevice(_ device: DiscoveredDevice) {
        let identifier = device.macAddress ?? device.id.uuidString
        ignoreService.unignore(id: identifier)
        bleService.setDeviceIgnored(id: device.id, isIgnored: false)

        Task {
            let _ = try? await serverClient.unignoreDeviceOnServer(
                config: serverConfig,
                id: identifier
            )
        }
    }

    public func syncDevicesToServer() async {
        isSyncing = true
        syncMessage = nil

        let activeItems = bleService.devices
            .filter { !$0.isIgnored }
            .map { $0.toMobileBleScanItem() }

        guard !activeItems.isEmpty else {
            syncMessage = "No active devices to transfer."
            isSyncing = false
            return
        }

        do {
            let res = try await serverClient.sendMobileBleScan(config: serverConfig, items: activeItems)
            syncMessage = "\(res.ingested) device(s) synced to HomeNode Server"
        } catch {
            syncMessage = "Sync error: \(error.localizedDescription)"
        }
        isSyncing = false
    }

    // MARK: - Light Control

    public var lightController: GoveeLightController {
        bleService.goveeController
    }

    public func toggleLightPower(for device: DiscoveredDevice) {
        lightController.togglePower(for: device.id)
    }

    public func setLightPower(for device: DiscoveredDevice, isOn: Bool) {
        lightController.setPower(for: device.id, isOn: isOn)
    }

    public func setLightBrightness(for device: DiscoveredDevice, percent: Int) {
        lightController.setBrightness(for: device.id, percent: percent)
    }

    public func setLightColor(for device: DiscoveredDevice, red: UInt8, green: UInt8, blue: UInt8) {
        lightController.setColor(for: device.id, red: red, green: green, blue: blue)
    }

    // MARK: - Proximity-Based Room Detection

    /// Detects the user's current room based on the strongest BLE signal of assigned devices
    public func detectNearestRoom() -> (roomName: String, strongestDevice: DiscoveredDevice, rssi: Int)? {
        let candidates = bleService.devices.filter { dev in
            guard let room = dev.assignedRoom, !room.isEmpty, room != "Not Assigned", room != "Nicht zugeordnet" else {
                return false
            }
            guard !dev.isIgnored, dev.isCurrentlyActive else {
                return false
            }
            return dev.rssi > -95
        }

        guard !candidates.isEmpty else { return nil }

        // Group by room
        let byRoom = Dictionary(grouping: candidates) { $0.assignedRoom! }

        var bestRoom: String?
        var bestDevice: DiscoveredDevice?
        var maxRssi: Int = -999

        for (room, devs) in byRoom {
            if let topDev = devs.max(by: { $0.rssi < $1.rssi }) {
                if topDev.rssi > maxRssi {
                    maxRssi = topDev.rssi
                    bestRoom = room
                    bestDevice = topDev
                }
            }
        }

        guard let room = bestRoom, let dev = bestDevice else { return nil }
        return (roomName: room, strongestDevice: dev, rssi: maxRssi)
    }

    // MARK: - Saved Scan Sessions

    @discardableResult
    public func saveCurrentScan(title: String, note: String? = nil, location: ScanLocation? = nil) -> SavedScanSession {
        let snapshotDevices = filteredDevices.isEmpty ? bleService.devices.filter { !$0.isIgnored } : filteredDevices
        let session = SavedScanSession(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Scan (\(Date().formatted(date: .abbreviated, time: .shortened)))"
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            location: location,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? note : nil,
            devices: snapshotDevices
        )

        savedScanStorage.saveSession(session)
        savedScans.insert(session, at: 0)
        return session
    }

    public func deleteSavedScan(id: UUID) {
        savedScans.removeAll { $0.id == id }
        savedScanStorage.deleteSession(id: id)
    }

    public func reloadSavedScans() {
        savedScans = savedScanStorage.loadSessions()
    }

    public func syncSavedScanToServer(_ session: SavedScanSession) async -> (ingested: Int, ignored: Int)? {
        isSyncing = true
        syncMessage = nil

        let scoutTag: String
        if let place = session.location?.placeName, !place.isEmpty {
            scoutTag = "iPhone (mHomeNode - \(place))"
        } else {
            scoutTag = "iPhone (mHomeNode - \(session.title))"
        }

        let items = session.devices.map { $0.toMobileBleScanItem(scoutName: scoutTag) }
        guard !items.isEmpty else {
            syncMessage = "No devices in this snapshot to transfer."
            isSyncing = false
            return nil
        }

        do {
            let res = try await serverClient.sendMobileBleScan(config: serverConfig, items: items)
            syncMessage = "\(res.ingested) device(s) from snapshot synced to Server"
            isSyncing = false
            return (ingested: res.ingested, ignored: res.ignored)
        } catch {
            syncMessage = "Sync error: \(error.localizedDescription)"
            isSyncing = false
            return nil
        }
    }
}
