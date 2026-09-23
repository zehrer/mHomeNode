import Foundation
import SwiftUI

public enum ProximityFilter: Double, CaseIterable, Identifiable, Sendable {
    case all = -120.0
    case distant = -90.0
    case nearby = -85.0
    case inRoom = -70.0
    case immediate = -60.0

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .all: return "All Signals"
        case .distant: return "Distant (≥ -90 dBm)"
        case .nearby: return "Nearby (≥ -85 dBm)"
        case .inRoom: return "In Room (≥ -70 dBm)"
        case .immediate: return "Immediate (≥ -60 dBm)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .all: return "All"
        case .distant: return "< 15m"
        case .nearby: return "Nearby"
        case .inRoom: return "Room"
        case .immediate: return "< 1m"
        }
    }

    public var iconName: String {
        switch self {
        case .all: return "dot.radiowaves.left.and.right"
        case .distant: return "wave.3.forward"
        case .nearby: return "antenna.radiowaves.left.and.right"
        case .inRoom: return "house"
        case .immediate: return "location.fill"
        }
    }
}

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
    public let locationManagementService: LocationManagementService
    public let roomManagementService: RoomManagementService
    public let homeKitService: HomeKitService

    public var serverConfig: ServerConfig = ServerConfig.load()
    public var serverRooms: [ServerRoom] = []
    public var savedScans: [SavedScanSession] = []

    public var searchText: String = ""
    public var onlyKnownDevices: Bool = false
    public var showIgnoredDevices: Bool = false
    public var proximityFilter: ProximityFilter = .nearby {
        didSet {
            UserDefaults.standard.set(proximityFilter.rawValue, forKey: "proximityFilter")
        }
    }
    public var minRSSI: Double = -120
    public var sortOrder: DeviceSortOrder = .rssi
    public var groupingMode: DeviceGroupingMode = .category {
        didSet {
            UserDefaults.standard.set(groupingMode.rawValue, forKey: "deviceGroupingMode")
        }
    }

    public var expandedSectionIds: Set<String> = []

    public func isSectionExpanded(_ id: String) -> Bool {
        expandedSectionIds.contains(id)
    }

    public func toggleSectionExpanded(_ id: String) {
        if expandedSectionIds.contains(id) {
            expandedSectionIds.remove(id)
        } else {
            expandedSectionIds.insert(id)
        }
    }

    public func expandAllSections() {
        expandedSectionIds = Set(groupedSections.map(\.id))
    }

    public func collapseAllSections() {
        expandedSectionIds.removeAll()
    }

    public var isSyncing: Bool = false
    public var syncMessage: String?

    // MARK: - Auto-Location Scan Settings & State
    public var isAutoLocationScanEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoLocationScanEnabled, forKey: "isAutoLocationScanEnabled")
            if isAutoLocationScanEnabled {
                locationService.startAutoTracking(distanceThreshold: autoScanDistanceThreshold)
            } else {
                locationService.stopAutoTracking()
            }
        }
    }

    public var autoScanDistanceThreshold: Double {
        didSet {
            UserDefaults.standard.set(autoScanDistanceThreshold, forKey: "autoScanDistanceThreshold")
            if isAutoLocationScanEnabled {
                locationService.startAutoTracking(distanceThreshold: autoScanDistanceThreshold)
            }
        }
    }

    public var autoScanBanner: String?
    public var lastAutoScanLocation: ScanLocation?

    public var isAutoGATTEnabled: Bool {
        get { bleService.isAutoGATTEnabled }
        set {
            bleService.isAutoGATTEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "isAutoGATTEnabled")
        }
    }

    public var autoGATTRSSIThreshold: Int {
        get { bleService.autoGATTRSSIThreshold }
        set {
            bleService.autoGATTRSSIThreshold = newValue
            UserDefaults.standard.set(newValue, forKey: "autoGATTRSSIThreshold")
        }
    }

    public init(
        bleService: BLEScannerService? = nil,
        ignoreService: IgnoreService? = nil,
        discoveryService: HomeNodeDiscoveryService? = nil,
        serverClient: HomeNodeServerClientProtocol = LiveHomeNodeServerClient(),
        locationService: LocationService? = nil,
        savedScanStorage: SavedScanStorageService? = nil,
        locationManagementService: LocationManagementService? = nil,
        roomManagementService: RoomManagementService? = nil,
        homeKitService: HomeKitService? = nil
    ) {
        let ign = ignoreService ?? .shared
        self.ignoreService = ign
        let ble = bleService ?? BLEScannerService(ignoreService: ign)
        self.bleService = ble
        let disc = discoveryService ?? .shared
        self.discoveryService = disc
        self.serverClient = serverClient
        let loc = locationService ?? LocationService()
        self.locationService = loc
        let storage = savedScanStorage ?? .shared
        self.savedScanStorage = storage
        self.savedScans = storage.loadSessions()
        let locMgr = locationManagementService ?? .shared
        self.locationManagementService = locMgr
        let roomMgr = roomManagementService ?? .shared
        self.roomManagementService = roomMgr
        let hk = homeKitService ?? .shared
        self.homeKitService = hk
        hk.syncWithRoomManagementService(roomMgr)

        // Import any existing device rooms to room management
        for reg in locMgr.activeLocation.devices {
            if let assigned = reg.assignedRoom, !assigned.isEmpty, assigned != "Not Assigned", assigned != "Nicht zugeordnet" {
                roomMgr.addRoom(name: assigned)
            }
        }

        // Load persisted auto-scan settings
        let storedAuto = UserDefaults.standard.bool(forKey: "isAutoLocationScanEnabled")
        let storedDist = UserDefaults.standard.double(forKey: "autoScanDistanceThreshold")
        self.isAutoLocationScanEnabled = storedAuto
        self.autoScanDistanceThreshold = storedDist > 0 ? storedDist : 100.0

        if let storedGroup = UserDefaults.standard.string(forKey: "deviceGroupingMode"),
           let mode = DeviceGroupingMode(rawValue: storedGroup) {
            self.groupingMode = mode
        } else {
            self.groupingMode = .category
        }

        let storedProximity = UserDefaults.standard.double(forKey: "proximityFilter")
        if storedProximity != 0, let filter = ProximityFilter(rawValue: storedProximity) {
            self.proximityFilter = filter
        } else {
            self.proximityFilter = .nearby
        }

        if UserDefaults.standard.object(forKey: "isAutoGATTEnabled") != nil {
            self.bleService.isAutoGATTEnabled = UserDefaults.standard.bool(forKey: "isAutoGATTEnabled")
        }
        let storedThreshold = UserDefaults.standard.integer(forKey: "autoGATTRSSIThreshold")
        if storedThreshold != 0 {
            self.bleService.autoGATTRSSIThreshold = storedThreshold
        }

        disc.onServerDiscovered = { [weak self] server in
            guard let self = self else { return }
            self.serverConfig.host = server.preferredHost
            self.serverConfig.port = server.port
            self.serverConfig.save()
            self.locationManagementService.recalculateActiveState(
                currentLocation: self.locationService.currentLocation,
                activeServerHost: server.preferredHost
            )
            Task { @MainActor in
                await self.loadServerRooms()
            }
        }
        disc.startBrowsing()

        // Setup auto-location scan callback
        loc.onSignificantLocationChange = { [weak self] newLocation, distance in
            Task { @MainActor in
                guard let self = self else { return }
                self.locationManagementService.recalculateActiveState(
                    currentLocation: newLocation,
                    activeServerHost: self.serverConfig.host
                )
                self.handleAutoLocationChange(newLocation: newLocation, distance: distance)
            }
        }

        if storedAuto {
            loc.startAutoTracking(distanceThreshold: self.autoScanDistanceThreshold)
        }

        // Wire Shelly Plug Multi-Path Server & LAN Client
        ble.shellyController.serverClient = serverClient
        ble.shellyController.serverConfigProvider = { [weak self] in
            guard let self = self else { return (ServerConfig(), false) }
            let isConnected = self.discoveryService.activeServer != nil || !self.serverRooms.isEmpty
            return (self.serverConfig, isConnected)
        }
        ble.shellyController.lanDiscovery.startBrowsing()

        // Auto-start duty-cycled burst scanning on launch to discover devices while preserving battery
        ble.startBurstScan(activeDuration: 4.0, pauseDuration: 4.0)

        // Initial room load only if a real server host is configured/remembered
        if !self.serverConfig.isLocalhost {
            Task { [weak self] in
                await self?.loadServerRooms()
            }
        }
    }

    private func handleAutoLocationChange(newLocation: ScanLocation, distance: CLLocationDistance) {
        guard isAutoLocationScanEnabled else { return }

        // If there are discovered devices from previous location, snapshot them
        let activeCount = bleService.devices.filter { !$0.isIgnored }.count
        if activeCount > 0 {
            let prevLoc = lastAutoScanLocation ?? newLocation
            let title = "Auto: \(prevLoc.displayTitle)"
            let note = "Automatically saved upon moving \(Int(distance))m"
            _ = saveCurrentScan(title: title, note: note, location: prevLoc)
            // Clear device buffer for new location
            bleService.clear()
        }

        lastAutoScanLocation = newLocation
        if !isScanning {
            bleService.resumeScan()
        }

        autoScanBanner = "📍 New location: \(newLocation.displayTitle). Started fresh scan."
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
            if Double(device.rssi) < proximityFilter.rawValue || Double(device.rssi) < minRSSI {
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

    public var groupedSections: [DeviceGroupSection] {
        DeviceGroupingHelper.group(devices: filteredDevices, mode: groupingMode)
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
        serverConfig.save()
        Task {
            await loadServerRooms()
        }
    }

    public func loadServerRooms() async {
        do {
            let rooms = try await serverClient.fetchRooms(config: serverConfig)
            self.serverRooms = rooms
            self.roomManagementService.syncWithServerRooms(rooms)
        } catch {
            // Server may be unavailable, persisted rooms in roomManagementService remain active
        }
    }

    public func saveRoom(name: String, floor: String?, icon: String, colorHex: String?, existingRoom: ManagedRoom? = nil) async {
        let cleanFloor = floor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFloor = (cleanFloor?.isEmpty == true) ? nil : cleanFloor

        let targetRoom: ManagedRoom
        if let existing = existingRoom {
            roomManagementService.updateRoom(
                id: existing.id,
                name: name,
                floor: resolvedFloor,
                icon: icon,
                colorHex: colorHex
            )
            targetRoom = roomManagementService.room(named: name) ?? existing
        } else {
            targetRoom = roomManagementService.addRoom(
                name: name,
                floor: resolvedFloor,
                icon: icon,
                colorHex: colorHex,
                source: .local
            )
        }

        // If server is connected and configured, sync upstream
        if !serverConfig.isLocalhost {
            do {
                _ = try await serverClient.createOrUpdateRoom(config: serverConfig, room: targetRoom)
                await loadServerRooms()
            } catch {
                // Offline fallback: saved locally, will sync when server becomes available
            }
        }
    }

    public func deleteRoom(_ room: ManagedRoom) async {
        roomManagementService.deleteRoom(id: room.id)
        if !serverConfig.isLocalhost {
            let serverId = room.serverRoomId ?? room.id
            do {
                _ = try await serverClient.deleteRoomOnServer(config: serverConfig, id: serverId)
                await loadServerRooms()
            } catch {
                // Server offline
            }
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

    public func updateDeviceLANAddress(id: UUID, lanAddress: String?) {
        bleService.updateDeviceLANAddress(id: id, lanAddress: lanAddress)
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

    // MARK: - Smart Plug / Switch Control

    public var shellyController: ShellyPlugController {
        bleService.shellyController
    }

    public func togglePlugPower(for device: DiscoveredDevice) {
        shellyController.togglePower(for: device.id)
    }

    public func setPlugPower(for device: DiscoveredDevice, isOn: Bool) {
        shellyController.setPower(for: device.id, isOn: isOn)
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

    // MARK: - Bulk Export

    public func exportAllCSV() -> String {
        ScanExportService.shared.exportAllCSV(sessions: savedScans)
    }

    public func exportAllCSVFileURL() -> URL? {
        ScanExportService.shared.exportAllCSVFile(sessions: savedScans)
    }

    public func exportAllJSON() -> String? {
        guard let data = ScanExportService.shared.exportAllJSONData(sessions: savedScans) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func exportAllJSONFileURL() -> URL? {
        ScanExportService.shared.exportAllJSONFile(sessions: savedScans)
    }

    public func exportAllSummary() -> String {
        ScanExportService.shared.exportAllSummary(sessions: savedScans)
    }

    // MARK: - Active GATT Device Inspection

    public var isInspecting: Bool = false
    public var inspectionError: String?

    public func inspectDevice(id: UUID) async -> Bool {
        isInspecting = true
        inspectionError = nil
        do {
            _ = try await bleService.inspectDevice(id: id)
            isInspecting = false
            return true
        } catch {
            isInspecting = false
            inspectionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Apple HomeKit Integration

    public func syncAppleHomeRooms() {
        homeKitService.syncWithRoomManagementService(roomManagementService)
    }

    public func homeKitAccessories(for roomName: String) -> [HomeKitAccessoryData] {
        let clean = roomName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return homeKitService.accessories.filter { acc in
            acc.roomName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean
        }
    }

    public func findHomeKitData(for device: DiscoveredDevice) -> HomeKitAccessoryData? {
        homeKitService.findMatchingAccessory(for: device)
    }

    public func toggleHomeKitPower(for accessoryId: UUID) async {
        try? await homeKitService.togglePower(for: accessoryId)
    }

    public func setHomeKitPower(for accessoryId: UUID, isOn: Bool) async {
        try? await homeKitService.setPower(for: accessoryId, isOn: isOn)
    }

    // MARK: - Managed Locations & Presence

    public var activeLocationState: ActiveLocationState {
        locationManagementService.activeLocationState
    }

    public var activeLocation: ManagedLocation {
        locationManagementService.activeLocation
    }

    public func calibrateActiveLocationWithGPS() async {
        if let loc = await locationService.fetchCurrentLocation() {
            locationManagementService.updateCoordinates(
                locationId: activeLocation.id,
                latitude: loc.latitude,
                longitude: loc.longitude
            )
            locationManagementService.recalculateActiveState(
                currentLocation: loc,
                activeServerHost: serverConfig.host
            )
        }
    }

    public func associateCurrentServerWithActiveLocation() {
        let host = serverConfig.host
        guard !host.isEmpty else { return }
        locationManagementService.updateAssociatedServer(
            locationId: activeLocation.id,
            host: host,
            port: serverConfig.port
        )
        locationManagementService.recalculateActiveState(
            currentLocation: locationService.currentLocation,
            activeServerHost: host
        )
    }
}

