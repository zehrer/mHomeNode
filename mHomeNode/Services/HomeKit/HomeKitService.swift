import Foundation
import SwiftUI
@preconcurrency import HomeKit
import OSLog

/// Snapshot of an Apple HomeKit accessory with decrypted telemetry and control status
public struct HomeKitAccessoryData: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let roomName: String?
    public let floorName: String?
    public let model: String?
    public let manufacturer: String?
    public let isReachable: Bool
    public let temperature: Double?
    public let humidity: Double?
    public let batteryLevel: Int?
    public let isSwitchable: Bool
    public let isPowerOn: Bool?
    public let isLight: Bool
    public let brightness: Int?
    public let lastUpdated: Date

    public init(
        id: UUID,
        name: String,
        roomName: String? = nil,
        floorName: String? = nil,
        model: String? = nil,
        manufacturer: String? = nil,
        isReachable: Bool = true,
        temperature: Double? = nil,
        humidity: Double? = nil,
        batteryLevel: Int? = nil,
        isSwitchable: Bool = false,
        isPowerOn: Bool? = nil,
        isLight: Bool = false,
        brightness: Int? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.roomName = roomName
        self.floorName = floorName
        self.model = model
        self.manufacturer = manufacturer
        self.isReachable = isReachable
        self.temperature = temperature
        self.humidity = humidity
        self.batteryLevel = batteryLevel
        self.isSwitchable = isSwitchable
        self.isPowerOn = isPowerOn
        self.isLight = isLight
        self.brightness = brightness
        self.lastUpdated = lastUpdated
    }
}

/// Manages integration with Apple HomeKit (HMHomeManager)
@Observable
@MainActor
public final class HomeKitService: NSObject, HMHomeManagerDelegate, HMAccessoryDelegate {
    public static let shared = HomeKitService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "HomeKitService")

    private var homeManager: HMHomeManager?

    // Published observable state
    public var isAuthorized: Bool = false
    public var authorizationStatusString: String = "Not Determined"
    public var homes: [HMHome] = []
    public var selectedHome: HMHome?
    public var accessories: [HomeKitAccessoryData] = []
    public var lastSyncDate: Date?
    public var isSyncing: Bool = false
    public var errorMessage: String?

    // Raw accessory references for control
    private var rawAccessories: [UUID: HMAccessory] = [:]

    override public init() {
        super.init()
        initializeHomeManager()
    }

    /// Initializes HMHomeManager to trigger permissions and home loading
    public func initializeHomeManager() {
        guard homeManager == nil else { return }
        logger.info("Initializing HMHomeManager for Apple HomeKit integration...")
        homeManager = HMHomeManager()
        homeManager?.delegate = self
        updateAuthStatus()
    }

    private func updateAuthStatus() {
        if let hm = homeManager {
            let status = hm.authorizationStatus
            if status.contains(.authorized) {
                isAuthorized = true
                authorizationStatusString = "Authorized"
            } else if status.contains(.restricted) {
                isAuthorized = false
                authorizationStatusString = "Restricted"
            } else if status.contains(.determined) {
                isAuthorized = false
                authorizationStatusString = "Denied"
            } else {
                isAuthorized = false
                authorizationStatusString = "Not Determined"
            }
        }
    }

    // MARK: - HMHomeManagerDelegate

    public nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.handleHomesUpdated(manager)
        }
    }

    public nonisolated func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) {
        Task { @MainActor in
            self.handleHomeAdded(manager, home: home)
        }
    }

    public nonisolated func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) {
        Task { @MainActor in
            self.handleHomeRemoved(manager, home: home)
        }
    }

    private func handleHomesUpdated(_ manager: HMHomeManager) {
        logger.info("HMHomeManager did update homes. Found \(manager.homes.count) home(s).")
        updateAuthStatus()
        self.homes = manager.homes
        if selectedHome == nil || !manager.homes.contains(where: { $0.uniqueIdentifier == selectedHome?.uniqueIdentifier }) {
            self.selectedHome = manager.homes.first
        }
        refreshHomeAccessories()
    }

    private func handleHomeAdded(_ manager: HMHomeManager, home: HMHome) {
        self.homes = manager.homes
        if selectedHome == nil {
            selectedHome = home
            refreshHomeAccessories()
        }
    }

    private func handleHomeRemoved(_ manager: HMHomeManager, home: HMHome) {
        self.homes = manager.homes
        if selectedHome?.uniqueIdentifier == home.uniqueIdentifier {
            selectedHome = manager.homes.first
            refreshHomeAccessories()
        }
    }

    // MARK: - Home Selection & Refresh

    public func selectHome(_ home: HMHome) {
        self.selectedHome = home
        refreshHomeAccessories()
    }

    /// Refreshes all accessories, registers delegates, enables notifications, and reads telemetry
    public func refreshHomeAccessories() {
        guard let home = selectedHome else {
            self.accessories = []
            self.rawAccessories = [:]
            return
        }

        isSyncing = true
        rawAccessories.removeAll()

        var snapshots: [HomeKitAccessoryData] = []

        // Map zones to floors
        var roomToFloor: [UUID: String] = [:]
        for zone in home.zones {
            for r in zone.rooms {
                roomToFloor[r.uniqueIdentifier] = zone.name
            }
        }

        for acc in home.accessories {
            rawAccessories[acc.uniqueIdentifier] = acc
            acc.delegate = self

            let roomName = acc.room?.name
            let floorName = acc.room.flatMap { roomToFloor[$0.uniqueIdentifier] }

            var tempVal: Double?
            var humVal: Double?
            var batVal: Int?
            var isSwitchable = false
            var powerOn: Bool?
            var isLight = false
            var brightnessVal: Int?

            // Check if the accessory is categorized as a light in Apple Home
            let catType = acc.category.categoryType
            let catDesc = acc.category.localizedDescription.lowercased()
            if catType == HMAccessoryCategoryTypeLightbulb ||
               catType.lowercased().contains("light") ||
               catType.lowercased().contains("lamp") ||
               catDesc.contains("light") ||
               catDesc.contains("licht") ||
               catDesc.contains("glühbirne") ||
               catDesc.contains("lampe") ||
               catDesc.contains("leuchte") {
                isLight = true
            }

            for service in acc.services {
                let st = service.serviceType
                let sName = service.name.lowercased()
                if st == HMServiceTypeLightbulb ||
                   service.associatedServiceType == HMServiceTypeLightbulb ||
                   (service.associatedServiceType?.lowercased().contains("light") == true) ||
                   sName.contains("light") ||
                   sName.contains("licht") ||
                   sName.contains("lampe") ||
                   sName.contains("leuchte") {
                    isLight = true
                }

                if st == HMServiceTypeTemperatureSensor {
                    for char in service.characteristics where char.characteristicType == HMCharacteristicTypeCurrentTemperature {
                        char.enableNotification(true) { _ in }
                        char.readValue { _ in }
                        if let num = char.value as? NSNumber {
                            tempVal = num.doubleValue
                        }
                    }
                }

                if st == HMServiceTypeHumiditySensor {
                    for char in service.characteristics where char.characteristicType == HMCharacteristicTypeCurrentRelativeHumidity {
                        char.enableNotification(true) { _ in }
                        char.readValue { _ in }
                        if let num = char.value as? NSNumber {
                            humVal = num.doubleValue
                        }
                    }
                }

                if st == HMServiceTypeBattery {
                    for char in service.characteristics where char.characteristicType == HMCharacteristicTypeBatteryLevel {
                        char.enableNotification(true) { _ in }
                        char.readValue { _ in }
                        if let num = char.value as? NSNumber {
                            batVal = num.intValue
                        }
                    }
                }

                if st == HMServiceTypeOutlet || st == HMServiceTypeSwitch || st == HMServiceTypeLightbulb {
                    isSwitchable = true
                    if st == HMServiceTypeLightbulb { isLight = true }

                    for char in service.characteristics {
                        if char.characteristicType == HMCharacteristicTypePowerState {
                            char.enableNotification(true) { _ in }
                            char.readValue { _ in }
                            if let b = char.value as? Bool {
                                powerOn = b
                            }
                        } else if char.characteristicType == HMCharacteristicTypeBrightness {
                            char.enableNotification(true) { _ in }
                            char.readValue { _ in }
                            if let num = char.value as? NSNumber {
                                brightnessVal = num.intValue
                                isLight = true
                            }
                        }
                    }
                }
            }

            let data = HomeKitAccessoryData(
                id: acc.uniqueIdentifier,
                name: acc.name,
                roomName: roomName,
                floorName: floorName,
                model: acc.model,
                manufacturer: acc.manufacturer,
                isReachable: acc.isReachable,
                temperature: tempVal,
                humidity: humVal,
                batteryLevel: batVal,
                isSwitchable: isSwitchable,
                isPowerOn: powerOn,
                isLight: isLight,
                brightness: brightnessVal,
                lastUpdated: Date()
            )
            snapshots.append(data)
        }

        self.accessories = snapshots
        self.lastSyncDate = Date()
        self.isSyncing = false
        logger.info("Loaded \(snapshots.count) accessory snapshot(s) for home '\(home.name)'")
    }

    // MARK: - HMAccessoryDelegate

    public nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in
            self.handleCharacteristicUpdate(accessory, service: service, characteristic: characteristic)
        }
    }

    private func handleCharacteristicUpdate(_ accessory: HMAccessory, service: HMService, characteristic: HMCharacteristic) {
        let accId = accessory.uniqueIdentifier
        logger.debug("Characteristic \(characteristic.characteristicType) updated for \(accessory.name)")

        guard let index = accessories.firstIndex(where: { $0.id == accId }) else { return }

        var current = accessories[index]
        let ct = characteristic.characteristicType

        if ct == HMCharacteristicTypeCurrentTemperature, let num = characteristic.value as? NSNumber {
            current = HomeKitAccessoryData(
                id: current.id,
                name: current.name,
                roomName: current.roomName,
                floorName: current.floorName,
                model: current.model,
                manufacturer: current.manufacturer,
                isReachable: current.isReachable,
                temperature: num.doubleValue,
                humidity: current.humidity,
                batteryLevel: current.batteryLevel,
                isSwitchable: current.isSwitchable,
                isPowerOn: current.isPowerOn,
                isLight: current.isLight,
                brightness: current.brightness,
                lastUpdated: Date()
            )
        } else if ct == HMCharacteristicTypeCurrentRelativeHumidity, let num = characteristic.value as? NSNumber {
            current = HomeKitAccessoryData(
                id: current.id,
                name: current.name,
                roomName: current.roomName,
                floorName: current.floorName,
                model: current.model,
                manufacturer: current.manufacturer,
                isReachable: current.isReachable,
                temperature: current.temperature,
                humidity: num.doubleValue,
                batteryLevel: current.batteryLevel,
                isSwitchable: current.isSwitchable,
                isPowerOn: current.isPowerOn,
                isLight: current.isLight,
                brightness: current.brightness,
                lastUpdated: Date()
            )
        } else if ct == HMCharacteristicTypeBatteryLevel, let num = characteristic.value as? NSNumber {
            current = HomeKitAccessoryData(
                id: current.id,
                name: current.name,
                roomName: current.roomName,
                floorName: current.floorName,
                model: current.model,
                manufacturer: current.manufacturer,
                isReachable: current.isReachable,
                temperature: current.temperature,
                humidity: current.humidity,
                batteryLevel: num.intValue,
                isSwitchable: current.isSwitchable,
                isPowerOn: current.isPowerOn,
                isLight: current.isLight,
                brightness: current.brightness,
                lastUpdated: Date()
            )
        } else if ct == HMCharacteristicTypePowerState, let b = characteristic.value as? Bool {
            current = HomeKitAccessoryData(
                id: current.id,
                name: current.name,
                roomName: current.roomName,
                floorName: current.floorName,
                model: current.model,
                manufacturer: current.manufacturer,
                isReachable: current.isReachable,
                temperature: current.temperature,
                humidity: current.humidity,
                batteryLevel: current.batteryLevel,
                isSwitchable: current.isSwitchable,
                isPowerOn: b,
                isLight: current.isLight,
                brightness: current.brightness,
                lastUpdated: Date()
            )
        } else if ct == HMCharacteristicTypeBrightness, let num = characteristic.value as? NSNumber {
            current = HomeKitAccessoryData(
                id: current.id,
                name: current.name,
                roomName: current.roomName,
                floorName: current.floorName,
                model: current.model,
                manufacturer: current.manufacturer,
                isReachable: current.isReachable,
                temperature: current.temperature,
                humidity: current.humidity,
                batteryLevel: current.batteryLevel,
                isSwitchable: current.isSwitchable,
                isPowerOn: current.isPowerOn,
                isLight: current.isLight,
                brightness: num.intValue,
                lastUpdated: Date()
            )
        }

        accessories[index] = current
    }

    public nonisolated func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        Task { @MainActor in
            self.handleAccessoryReachabilityUpdate(accessory)
        }
    }

    private func handleAccessoryReachabilityUpdate(_ accessory: HMAccessory) {
        let accId = accessory.uniqueIdentifier
        if let index = accessories.firstIndex(where: { $0.id == accId }) {
            var current = accessories[index]
            current = HomeKitAccessoryData(
                id: current.id,
                name: current.name,
                roomName: current.roomName,
                floorName: current.floorName,
                model: current.model,
                manufacturer: current.manufacturer,
                isReachable: accessory.isReachable,
                temperature: current.temperature,
                humidity: current.humidity,
                batteryLevel: current.batteryLevel,
                isSwitchable: current.isSwitchable,
                isPowerOn: current.isPowerOn,
                isLight: current.isLight,
                brightness: current.brightness,
                lastUpdated: Date()
            )
            accessories[index] = current
        }
    }

    // MARK: - Device Control Operations

    public func togglePower(for accessoryId: UUID) async throws {
        guard let current = accessories.first(where: { $0.id == accessoryId }),
              let currentPower = current.isPowerOn else {
            return
        }
        try await setPower(for: accessoryId, isOn: !currentPower)
    }

    public func setPower(for accessoryId: UUID, isOn: Bool) async throws {
        guard let raw = rawAccessories[accessoryId] else {
            throw NSError(domain: "HomeKitService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Accessory not found in Apple Home cache."])
        }

        for service in raw.services where service.serviceType == HMServiceTypeOutlet ||
                                          service.serviceType == HMServiceTypeSwitch ||
                                          service.serviceType == HMServiceTypeLightbulb {
            if let char = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypePowerState }) {
                try await char.writeValue(isOn)
                if let index = accessories.firstIndex(where: { $0.id == accessoryId }) {
                    var current = accessories[index]
                    current = HomeKitAccessoryData(
                        id: current.id,
                        name: current.name,
                        roomName: current.roomName,
                        floorName: current.floorName,
                        model: current.model,
                        manufacturer: current.manufacturer,
                        isReachable: current.isReachable,
                        temperature: current.temperature,
                        humidity: current.humidity,
                        batteryLevel: current.batteryLevel,
                        isSwitchable: current.isSwitchable,
                        isPowerOn: isOn,
                        isLight: current.isLight,
                        brightness: current.brightness,
                        lastUpdated: Date()
                    )
                    accessories[index] = current
                }
                logger.info("Set power state to \(isOn) for Apple Home accessory \(raw.name)")
                return
            }
        }
    }

    public func setBrightness(for accessoryId: UUID, percent: Int) async throws {
        guard let raw = rawAccessories[accessoryId] else {
            throw NSError(domain: "HomeKitService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Accessory not found in Apple Home cache."])
        }

        let clamped = max(0, min(100, percent))
        for service in raw.services where service.serviceType == HMServiceTypeLightbulb {
            if let char = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeBrightness }) {
                try await char.writeValue(clamped)
                if let index = accessories.firstIndex(where: { $0.id == accessoryId }) {
                    var current = accessories[index]
                    current = HomeKitAccessoryData(
                        id: current.id,
                        name: current.name,
                        roomName: current.roomName,
                        floorName: current.floorName,
                        model: current.model,
                        manufacturer: current.manufacturer,
                        isReachable: current.isReachable,
                        temperature: current.temperature,
                        humidity: current.humidity,
                        batteryLevel: current.batteryLevel,
                        isSwitchable: current.isSwitchable,
                        isPowerOn: current.isPowerOn,
                        isLight: current.isLight,
                        brightness: clamped,
                        lastUpdated: Date()
                    )
                    accessories[index] = current
                }
                logger.info("Set brightness to \(clamped)% for Apple Home light \(raw.name)")
                return
            }
        }
    }

    // MARK: - Correlate BLE Device with HomeKit Accessory

    /// Attempts to find a matching Apple HomeKit accessory for a BLE discovered device (e.g. Qingping sensor)
    public func findMatchingAccessory(for device: DiscoveredDevice) -> HomeKitAccessoryData? {
        // 1. Direct name match
        let devName = device.name.lowercased()
        let customName = device.customName?.lowercased()

        for acc in accessories {
            let accName = acc.name.lowercased()
            if accName == devName || (customName != nil && accName == customName) {
                return acc
            }
        }

        // 2. Family match for Qingping sensors
        if device.family == .qingping || device.isHomeKitAccessory {
            for acc in accessories {
                let mfg = acc.manufacturer?.lowercased() ?? ""
                let model = acc.model?.lowercased() ?? ""
                let name = acc.name.lowercased()
                if mfg.contains("qingping") || model.contains("cgg1") || model.contains("cgd1") || name.contains("qingping") {
                    return acc
                }
            }
        }

        return nil
    }

    // MARK: - Synchronize Rooms & Zones with RoomManagementService

    /// Synchronizes rooms and zones (floors) from the selected Apple Home into the unified room management service
    public func syncWithRoomManagementService(_ roomService: RoomManagementService) {
        guard let home = selectedHome else { return }

        var roomToFloor: [UUID: String] = [:]
        for zone in home.zones {
            for r in zone.rooms {
                roomToFloor[r.uniqueIdentifier] = zone.name
            }
        }

        let hkRooms: [(id: String, name: String, floor: String?)] = home.rooms.map { r in
            (
                id: r.uniqueIdentifier.uuidString,
                name: r.name,
                floor: roomToFloor[r.uniqueIdentifier]
            )
        }

        roomService.syncWithAppleHome(homeKitRoomsWithFloor: hkRooms)
        logger.info("Synchronized \(hkRooms.count) room(s) from Apple Home '\(home.name)' with RoomManagementService")
    }
}
