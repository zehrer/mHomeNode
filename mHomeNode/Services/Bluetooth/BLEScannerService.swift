import Foundation
@preconcurrency import CoreBluetooth
import OSLog

@Observable
@MainActor
public final class BLEScannerService: NSObject, BLEConnectionManager {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "BLEScanner")
    private let worker: BLECentralWorker
    private let ignoreService: IgnoreService
    private let storageService: DeviceStorageService

    public var isScanning: Bool = false
    public var bluetoothState: CBManagerState = .unknown
    public var devices: [DiscoveredDevice] = []
    public var errorMessage: String?

    public private(set) var peripheralMap: [UUID: CBPeripheral] = [:]
    public let goveeController = GoveeLightController()
    public let shellyController = ShellyPlugController()
    public let inspectorService = BLEInspectorService()

    private var pendingScanStart: Bool = false

    public init(ignoreService: IgnoreService? = nil, storageService: DeviceStorageService? = nil) {
        let ign = ignoreService ?? .shared
        self.ignoreService = ign
        let storage = storageService ?? .shared
        self.storageService = storage
        let initialDevices = storage.loadDevices()
        self.devices = initialDevices

        let bleQueue = DispatchQueue(label: "net.zehrer.homenode.bleQueue", qos: .userInitiated)
        let worker = BLECentralWorker(
            queue: bleQueue,
            initialDevices: initialDevices,
            ignoredRecords: ign.ignoredRecords
        )
        self.worker = worker

        super.init()

        if let state = worker.centralManager?.state, state != .unknown {
            self.bluetoothState = state
        }

        self.goveeController.connectionManager = self
        self.shellyController.connectionManager = self
        if let cm = worker.centralManager {
            self.inspectorService.setCentralManager(cm, queue: bleQueue)
        }

        worker.onDevicesBatched = { [weak self] snapshot, periphs in
            Task { @MainActor [weak self] in
                self?.applyBatchUpdate(snapshot: snapshot, peripherals: periphs)
            }
        }

        worker.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleStateChanged(state)
            }
        }

        worker.onDidConnect = { [weak self] peripheral in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.peripheralMap[peripheral.identifier] = peripheral
                if self.goveeController.isDeviceBusy(peripheral.identifier) || self.goveeController.hasPendingPackets(for: peripheral.identifier) {
                    self.goveeController.didConnect(peripheral: peripheral)
                } else if self.shellyController.isDeviceBusy(peripheral.identifier) {
                    self.shellyController.didConnect(peripheral: peripheral)
                } else {
                    self.inspectorService.didConnect(peripheral: peripheral)
                }
            }
        }

        worker.onDidFailToConnect = { [weak self] peripheral, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.goveeController.isDeviceBusy(peripheral.identifier) || self.goveeController.hasPendingPackets(for: peripheral.identifier) {
                    self.goveeController.didFailToConnect(peripheral: peripheral, error: error)
                } else if self.shellyController.isDeviceBusy(peripheral.identifier) {
                    self.shellyController.didFailToConnect(peripheral: peripheral, error: error)
                } else {
                    self.inspectorService.didFailToConnect(peripheral: peripheral, error: error)
                }
            }
        }

        worker.onDidDisconnect = { [weak self] peripheral, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.goveeController.isDeviceBusy(peripheral.identifier) || self.goveeController.hasPendingPackets(for: peripheral.identifier) {
                    self.goveeController.didDisconnect(peripheral: peripheral, error: error)
                } else if self.shellyController.isDeviceBusy(peripheral.identifier) {
                    self.shellyController.didDisconnect(peripheral: peripheral, error: error)
                } else {
                    self.inspectorService.didDisconnect(peripheral: peripheral, error: error)
                }
            }
        }
    }

    public private(set) var isBurstScanning: Bool = false
    private var burstTimer: Timer?
    private var isBurstActivePhase: Bool = false
    private var burstActiveDuration: TimeInterval = 4.0
    private var burstPauseDuration: TimeInterval = 4.0

    public func startScan() {
        switch bluetoothState {
        case .poweredOn:
            errorMessage = nil
            pendingScanStart = false
            isScanning = true
            logger.info("Starting BLE scan for nearby devices and BTHome broadcasts...")
            worker.startScan()
        case .unknown, .resetting:
            // Do NOT display a red error message during startup or reset.
            errorMessage = nil
            pendingScanStart = true
            logger.info("Bluetooth state is \(self.bluetoothState.description); scan will begin once powered on.")
        case .poweredOff:
            pendingScanStart = false
            errorMessage = "Bluetooth is turned off."
        case .unauthorized:
            pendingScanStart = false
            errorMessage = "Bluetooth permission is required."
        case .unsupported:
            pendingScanStart = false
            errorMessage = "Bluetooth Low Energy is not supported on this device."
        @unknown default:
            pendingScanStart = false
            errorMessage = "Bluetooth is unavailable."
        }
    }

    /// Starts a duty-cycled burst scan (e.g. 4s active, 4s pause) to continuously receive telemetry while conserving battery
    public func startBurstScan(activeDuration: TimeInterval = 4.0, pauseDuration: TimeInterval = 4.0) {
        self.burstActiveDuration = activeDuration
        self.burstPauseDuration = pauseDuration
        self.isBurstScanning = true
        self.isBurstActivePhase = true
        startScan()
        scheduleBurstCycle()
    }

    private func scheduleBurstCycle() {
        burstTimer?.invalidate()
        guard isBurstScanning else { return }

        let interval = isBurstActivePhase ? burstActiveDuration : burstPauseDuration
        burstTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isBurstScanning else { return }
                if self.isBurstActivePhase {
                    // Switch to pause phase to save battery
                    self.worker.stopScan()
                    self.isScanning = false
                    self.isBurstActivePhase = false
                    self.logger.debug("Burst scan cycle: paused (conserving battery)")
                } else {
                    // Switch to active scanning phase
                    guard self.bluetoothState == .poweredOn else { return }
                    self.worker.startScan()
                    self.isScanning = true
                    self.isBurstActivePhase = true
                    self.logger.debug("Burst scan cycle: active")
                }
                self.scheduleBurstCycle()
            }
        }
    }

    public func pauseScan() {
        burstTimer?.invalidate()
        burstTimer = nil
        worker.stopScan()
        isScanning = false
        logger.info("Paused BLE scan.")
    }

    public func resumeScan() {
        if isBurstScanning {
            isBurstActivePhase = true
            startScan()
            scheduleBurstCycle()
        } else {
            startScan()
        }
    }

    public func stopScan() {
        isBurstScanning = false
        burstTimer?.invalidate()
        burstTimer = nil
        worker.stopScan()
        isScanning = false
        activeAutoInspectDeviceName = nil
        isAutoGATTInFlight = false
        storageService.saveDevicesSync(devices)
        logger.info("Stopped BLE scan.")
    }

    public func clear() {
        // Retain devices that have a room assigned or are registered in the active location
        let activeRegIds = Set(LocationManagementService.shared.activeLocation.devices.map { $0.id.uppercased() })
        devices.removeAll { dev in
            let key = (dev.macAddress ?? dev.id.uuidString).uppercased()
            let hasRoom = dev.assignedRoom != nil && !(dev.assignedRoom?.isEmpty ?? true)
            return !hasRoom && !activeRegIds.contains(key)
        }
        storageService.saveDevicesSync(devices)
        worker.syncDevices(devices)
    }

    public func updateRoom(for deviceId: UUID, room: String?) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].assignedRoom = room
            storageService.scheduleSave(devices)
            worker.syncDevices(devices)
            let dev = devices[index]
            let devKey = dev.macAddress ?? dev.id.uuidString
            LocationManagementService.shared.registerDevice(
                deviceId: devKey,
                customName: dev.customName,
                room: room,
                family: dev.family.rawValue
            )
        }
    }

    public func updateDeviceName(id: UUID, customName: String?) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].customName = customName
            storageService.scheduleSave(devices)
            worker.syncDevices(devices)
            let dev = devices[index]
            let devKey = dev.macAddress ?? dev.id.uuidString
            LocationManagementService.shared.registerDevice(
                deviceId: devKey,
                customName: customName,
                room: dev.assignedRoom,
                family: dev.family.rawValue
            )
        }
    }

    public func updateDeviceLANAddress(id: UUID, lanAddress: String?) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].lanAddress = lanAddress
            storageService.scheduleSave(devices)
            worker.syncDevices(devices)
        }
    }

    public func setDeviceIgnored(id: UUID, isIgnored: Bool) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].isIgnored = isIgnored
            storageService.scheduleSave(devices)
            worker.syncDevices(devices)
        }
        worker.syncIgnoredRecords(ignoreService.ignoredRecords)
    }

    // MARK: - Batch Updates & State Handling

    private func applyBatchUpdate(snapshot: [DiscoveredDevice], peripherals: [UUID: CBPeripheral]) {
        var merged = snapshot
        for i in merged.indices {
            if merged[i].assignedRoom == nil || merged[i].customName == nil {
                let devKey = merged[i].macAddress ?? merged[i].id.uuidString
                if let reg = LocationManagementService.shared.lookupDevice(deviceId: devKey) {
                    if merged[i].assignedRoom == nil { merged[i].assignedRoom = reg.assignedRoom }
                    if merged[i].customName == nil { merged[i].customName = reg.customName }
                    LocationManagementService.shared.markDeviceSeen(deviceId: devKey)
                }
            }
        }

        self.devices = merged
        for (k, v) in peripherals {
            self.peripheralMap[k] = v
        }

        // Passively synchronize real-time power state from BLE advertisement packets
        for dev in merged {
            if dev.family == .govee, let mfgHex = dev.manufacturerDataHex {
                if let pState = DeviceFingerprinter.parseGoveePowerStateFromHex(mfgHex) {
                    self.goveeController.updatePowerStateFromAdvertisement(deviceId: dev.id, isOn: pState)
                }
            }
        }

        self.storageService.scheduleSave(merged)

        if isAutoGATTEnabled {
            triggerAutoGATTCheck()
        }
    }

    private func handleStateChanged(_ state: CBManagerState) {
        self.bluetoothState = state
        logger.info("Bluetooth state changed: \(state.description)")

        switch state {
        case .poweredOn:
            errorMessage = nil
            if pendingScanStart || isScanning || isBurstScanning {
                pendingScanStart = false
                if isBurstScanning && !isBurstActivePhase {
                    // Wait for next active cycle
                } else {
                    isScanning = true
                    worker.startScan()
                }
            }
        case .poweredOff:
            isScanning = false
            pendingScanStart = false
            errorMessage = "Bluetooth is turned off."
        case .unauthorized:
            isScanning = false
            pendingScanStart = false
            errorMessage = "Bluetooth permission is required."
        case .unsupported:
            isScanning = false
            pendingScanStart = false
            errorMessage = "Bluetooth Low Energy is not supported on this device."
        case .unknown, .resetting:
            isScanning = false
            errorMessage = nil
        @unknown default:
            break
        }
    }

    // MARK: - BLEConnectionManager

    public func connect(peripheral: CBPeripheral) {
        peripheralMap[peripheral.identifier] = peripheral
        worker.connect(peripheral: peripheral)
    }

    public func cancelConnection(peripheral: CBPeripheral) {
        worker.cancelConnection(peripheral: peripheral)
    }

    public func getPeripheral(id: UUID) -> CBPeripheral? {
        if let p = peripheralMap[id] { return p }
        return worker.getPeripheral(id: id)
    }

    public func cancelAutoGATT(for targetId: UUID? = nil) {
        if let targetId = targetId {
            autoGATTAttemptCooldowns[targetId] = Date.distantFuture
        }
        if isAutoGATTInFlight {
            logger.info("Preempting background auto-GATT inspection for target \(targetId?.uuidString ?? "all")...")
            isAutoGATTInFlight = false
            activeAutoInspectDeviceName = nil
            // If targetId is provided, detach delegate without terminating the physical connection
            inspectorService.cancelCurrentInspection(disconnect: targetId == nil)
        }
    }

    // MARK: - Auto GATT Deep Inspection

    public var isAutoGATTEnabled: Bool = false {
        didSet {
            if isAutoGATTEnabled {
                triggerAutoGATTCheck()
            } else {
                activeAutoInspectDeviceName = nil
            }
        }
    }
    public var autoGATTRSSIThreshold: Int = -70
    public private(set) var activeAutoInspectDeviceName: String?
    private var autoGATTAttemptCooldowns: [UUID: Date] = [:]
    private var isAutoGATTInFlight: Bool = false
    private let autoGATTCooldownInterval: TimeInterval = 300.0 // 5 minutes cooldown after attempt

    public func triggerAutoGATTCheck() {
        guard isAutoGATTEnabled,
              bluetoothState == .poweredOn,
              (isScanning || isBurstScanning),
              !isAutoGATTInFlight else { return }

        // Never start auto-GATT if any light controller has active operations or packets queued
        guard !goveeController.hasActiveOperations else { return }

        let now = Date()

        // Find candidate devices:
        // 1. Must be connectable
        // 2. Must not be ignored
        // 3. Must have RSSI >= autoGATTRSSIThreshold
        // 4. Must not have completed inspectionInfo already (modelNumber, manufacturerName, or discoveredServices)
        // 5. Must not be in cooldown from a recent attempt (< 5 minutes)
        // 6. Must have an active peripheral in peripheralMap
        // 7. MUST NOT be a controllable light, curtain, plug, or active Govee/Shelly device
        let candidate = devices
            .filter { dev in
                guard dev.isConnectable, !dev.isIgnored else { return false }
                guard dev.rssi >= autoGATTRSSIThreshold else { return false }

                // Exclude actively controlled families and devices
                guard dev.family != .govee && dev.family != .shellyBlu && dev.family != .smartLight else { return false }
                guard !dev.isLightingDevice && !dev.isSwitchablePlug else { return false }
                guard !goveeController.isDeviceBusy(dev.id) && !goveeController.hasPendingPackets(for: dev.id) else { return false }

                let low = (dev.displayTitle + " " + dev.name).lowercased()
                if low.contains("govee") || low.contains("curtain") || low.contains("vorhang") || low.contains("h70b") || low.starts(with: "gvh") || low.starts(with: "ihoment") {
                    return false
                }
                if let mfg = dev.manufacturerDataHex?.lowercased(), mfg.contains("88ec") || mfg.contains("ec88") {
                    return false
                }

                let isAlreadyInspected = dev.inspectionInfo != nil &&
                    (!dev.inspectionInfo!.discoveredServices.isEmpty || dev.inspectionInfo!.modelNumber != nil || dev.inspectionInfo!.manufacturerName != nil)
                guard !isAlreadyInspected else { return false }

                if let lastAttempt = autoGATTAttemptCooldowns[dev.id] {
                    if now.timeIntervalSince(lastAttempt) < autoGATTCooldownInterval {
                        return false
                    }
                }
                return getPeripheral(id: dev.id) != nil
            }
            .sorted { $0.rssi > $1.rssi } // Closest / strongest RSSI first
            .first

        guard let target = candidate else { return }

        isAutoGATTInFlight = true
        activeAutoInspectDeviceName = target.displayTitle
        autoGATTAttemptCooldowns[target.id] = now
        logger.info("Starting automatic GATT deep probe for candidate '\(target.displayTitle)' (RSSI: \(target.rssi) dBm)...")

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                _ = try await self.inspectDevice(id: target.id, timeoutSeconds: 8.0)
                self.logger.info("Automatic GATT deep probe completed for '\(target.displayTitle)'.")
            } catch {
                self.logger.warning("Automatic GATT deep probe ended with error for '\(target.displayTitle)': \(error.localizedDescription)")
            }
            self.isAutoGATTInFlight = false
            self.activeAutoInspectDeviceName = nil

            // Check next candidate after brief pause
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self.isAutoGATTEnabled {
                self.triggerAutoGATTCheck()
            }
        }
    }

    // MARK: - Active GATT Inspection

    public func inspectDevice(id: UUID, timeoutSeconds: TimeInterval = 15.0) async throws -> DeviceInspectionInfo {
        guard let peripheral = getPeripheral(id: id) else {
            throw NSError(
                domain: "BLEScannerService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Peripheral not currently reachable or out of signal range."]
            )
        }
        let wasBurst = self.isBurstScanning
        let wasScanning = self.isScanning
        if wasBurst || wasScanning {
            pauseScan()
        }
        defer {
            if wasBurst {
                startBurstScan(activeDuration: self.burstActiveDuration, pauseDuration: self.burstPauseDuration)
            } else if wasScanning {
                startScan()
            }
        }
        let info = try await inspectorService.inspect(peripheral: peripheral, timeoutSeconds: timeoutSeconds)
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].applyInspectionInfo(info)
            storageService.scheduleSave(devices)
            worker.syncDevices(devices)
        }
        return info
    }
}

// MARK: - Background BLE Central Worker

private final class BLECentralWorker: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "BLEWorker")
    let queue: DispatchQueue
    private(set) var centralManager: CBCentralManager?

    private var deviceMap: [UUID: DiscoveredDevice] = [:]
    private var macToId: [String: UUID] = [:]
    private var peripheralMap: [UUID: CBPeripheral] = [:]
    private var ignoredRecords: [IgnoredDeviceRecord] = []

    private var hasPendingBatchUpdate: Bool = false
    private var batchTimer: DispatchSourceTimer?

    var onDevicesBatched: (@Sendable ([DiscoveredDevice], [UUID: CBPeripheral]) -> Void)?
    var onStateChanged: (@Sendable (CBManagerState) -> Void)?
    var onDidConnect: (@Sendable (CBPeripheral) -> Void)?
    var onDidFailToConnect: (@Sendable (CBPeripheral, Error?) -> Void)?
    var onDidDisconnect: (@Sendable (CBPeripheral, Error?) -> Void)?

    init(queue: DispatchQueue, initialDevices: [DiscoveredDevice], ignoredRecords: [IgnoredDeviceRecord]) {
        self.queue = queue
        self.ignoredRecords = ignoredRecords
        for dev in initialDevices {
            self.deviceMap[dev.id] = dev
            if let mac = dev.macAddress {
                self.macToId[mac.uppercased()] = dev.id
            }
        }
        super.init()

        // Coalesce updates to UI at ~600ms intervals (preserves 60fps main thread responsiveness)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(600), repeating: .milliseconds(600))
        timer.setEventHandler { [weak self] in
            self?.flushBatchIfNeeded()
        }
        timer.resume()
        self.batchTimer = timer

        self.centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    deinit {
        batchTimer?.cancel()
    }

    private func flushBatchIfNeeded() {
        guard hasPendingBatchUpdate else { return }
        hasPendingBatchUpdate = false
        let snapshot = Array(deviceMap.values)
        let periphSnapshot = peripheralMap
        onDevicesBatched?(snapshot, periphSnapshot)
    }

    func syncDevices(_ devices: [DiscoveredDevice]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.deviceMap.removeAll(keepingCapacity: true)
            self.macToId.removeAll(keepingCapacity: true)
            for dev in devices {
                self.deviceMap[dev.id] = dev
                if let mac = dev.macAddress {
                    self.macToId[mac.uppercased()] = dev.id
                }
            }
        }
    }

    func syncIgnoredRecords(_ records: [IgnoredDeviceRecord]) {
        queue.async { [weak self] in
            self?.ignoredRecords = records
        }
    }

    func startScan() {
        queue.async { [weak self] in
            guard let self = self, let cm = self.centralManager else { return }
            guard cm.state == .poweredOn else { return }
            cm.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func stopScan() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.centralManager?.stopScan()
            self.flushBatchIfNeeded()
        }
    }

    func connect(peripheral: CBPeripheral) {
        queue.async { [weak self] in
            self?.centralManager?.connect(peripheral, options: nil)
        }
    }

    func cancelConnection(peripheral: CBPeripheral) {
        queue.async { [weak self] in
            self?.centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    func getPeripheral(id: UUID) -> CBPeripheral? {
        queue.sync {
            if let p = peripheralMap[id] { return p }
            return centralManager?.retrievePeripherals(withIdentifiers: [id]).first
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChanged?(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiVal = RSSI.intValue
        guard rssiVal != 127 else { return }

        peripheralMap[peripheral.identifier] = peripheral

        let rawName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false

        // Extract service UUIDs
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let serviceUUIDStrings = serviceUUIDs.map { $0.uuidString }

        // Extract Service Data
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        var serviceDataHexDict: [String: String]? = nil
        if let serviceData = serviceData, !serviceData.isEmpty {
            var dict: [String: String] = [:]
            for (uuid, data) in serviceData {
                dict[uuid.uuidString] = data.map { String(format: "%02hhX", $0) }.joined()
            }
            serviceDataHexDict = dict
        }

        // Extract Manufacturer Data
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let mfgDataHex = mfgData?.map { String(format: "%02hhX", $0) }.joined()

        let identification = DeviceFingerprinter.identifyDetails(
            advertisedName: rawName,
            serviceUUIDs: serviceUUIDs,
            serviceData: serviceData,
            manufacturerData: mfgData
        )

        let resolvedName: String
        if identification.isHomeKitAccessory, let modelName = identification.resolvedName {
            resolvedName = modelName
        } else if !rawName.isEmpty && rawName.lowercased() != "qin" {
            resolvedName = rawName
        } else if let modelName = identification.resolvedName {
            resolvedName = modelName
        } else {
            resolvedName = "Unknown"
        }

        let isIgnored = isDeviceIgnored(
            id: identification.macAddress ?? peripheral.identifier.uuidString,
            name: resolvedName
        )
        let now = Date()

        // Lookup existing device: first by UUID, then by MAC address
        var existingDev = deviceMap[peripheral.identifier]
        if existingDev == nil, let mac = identification.macAddress?.uppercased(), let existingId = macToId[mac] {
            existingDev = deviceMap[existingId]
        }

        if var dev = existingDev {
            peripheralMap[dev.id] = peripheral
            dev.rssi = rssiVal
            dev.rssiHistory.append(rssiVal)
            if dev.rssiHistory.count > 20 {
                dev.rssiHistory.removeFirst()
            }
            if !rawName.isEmpty && rawName != "Unknown" {
                dev.originalName = rawName
            }
            if dev.customName == nil {
                if dev.name == "Unknown" || dev.name.isEmpty || dev.name == "Qin" {
                    dev.name = resolvedName
                } else if dev.family == .govee, let orig = dev.originalName, !orig.isEmpty {
                    let suffix = orig.components(separatedBy: "_").last ?? ""
                    if suffix.count == 4 && !dev.name.contains(suffix) {
                        dev.name = resolvedName
                    }
                }
            }
            if identification.isHomeKitAccessory {
                dev.isHomeKitAccessory = true
                dev.isHomeKitPaired = identification.isHomeKitPaired
            }
            if let btHomeData = identification.btHomeData {
                if dev.btHomeData != nil {
                    dev.btHomeData?.merge(with: btHomeData)
                } else {
                    dev.btHomeData = btHomeData
                }
                dev.lastMeasurementDate = now
            }
            if identification.family != .standardBLE {
                dev.family = identification.family
            }
            if let mac = identification.macAddress {
                dev.macAddress = mac
                macToId[mac.uppercased()] = dev.id
            }
            if isConnectable {
                dev.isConnectable = true
            }

            for suuid in serviceUUIDStrings {
                if !dev.serviceUUIDs.contains(suuid) {
                    dev.serviceUUIDs.append(suuid)
                }
            }
            if let mfg = mfgDataHex, !mfg.isEmpty {
                dev.manufacturerDataHex = mfg
            }
            if let sdict = serviceDataHexDict {
                if dev.serviceDataHex == nil {
                    dev.serviceDataHex = sdict
                } else {
                    for (k, v) in sdict {
                        dev.serviceDataHex?[k] = v
                    }
                }
            }

            dev.isIgnored = isIgnored
            dev.lastSeen = now

            deviceMap[dev.id] = dev
        } else {
            let newDevice = DiscoveredDevice(
                id: peripheral.identifier,
                name: resolvedName,
                originalName: rawName.isEmpty ? nil : rawName,
                rssi: rssiVal,
                rssiHistory: [rssiVal],
                serviceUUIDs: serviceUUIDStrings,
                manufacturerDataHex: mfgDataHex,
                serviceDataHex: serviceDataHexDict,
                btHomeData: identification.btHomeData,
                family: identification.family,
                isConnectable: isConnectable,
                assignedRoom: nil,
                customName: nil,
                isIgnored: isIgnored,
                macAddress: identification.macAddress,
                isHomeKitAccessory: identification.isHomeKitAccessory,
                isHomeKitPaired: identification.isHomeKitPaired,
                firstSeen: now,
                lastSeen: now,
                lastMeasurementDate: identification.btHomeData != nil ? now : nil
            )
            deviceMap[newDevice.id] = newDevice
            if let mac = identification.macAddress {
                macToId[mac.uppercased()] = newDevice.id
            }
        }

        hasPendingBatchUpdate = true
    }

    private func isDeviceIgnored(id: String, name: String?) -> Bool {
        let normId = id.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard !normId.isEmpty else { return false }
        for r in ignoredRecords {
            let rNorm = r.normalizedId
            if rNorm == normId { return true }
            if let tName = name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
               !tName.isEmpty,
               !IgnoreService.genericNames.contains(tName),
               let iName = r.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
               !iName.isEmpty, !IgnoreService.genericNames.contains(iName),
               tName == iName {
                return true
            }
        }
        return false
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onDidConnect?(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onDidFailToConnect?(peripheral, error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onDidDisconnect?(peripheral, error)
    }
}

extension CBManagerState {
    var description: String {
        switch self {
        case .poweredOn: return "Powered On"
        case .poweredOff: return "Powered Off"
        case .resetting: return "Resetting"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}
