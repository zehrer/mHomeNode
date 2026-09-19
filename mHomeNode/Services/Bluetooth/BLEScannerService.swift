import Foundation
@preconcurrency import CoreBluetooth
import OSLog

@Observable
@MainActor
public final class BLEScannerService: NSObject, @preconcurrency CBCentralManagerDelegate, BLEConnectionManager {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "BLEScanner")
    private var centralManager: CBCentralManager?
    private let ignoreService: IgnoreService
    private let storageService: DeviceStorageService

    public var isScanning: Bool = false
    public var bluetoothState: CBManagerState = .unknown
    public var devices: [DiscoveredDevice] = []
    public var errorMessage: String?

    public private(set) var peripheralMap: [UUID: CBPeripheral] = [:]
    public let goveeController = GoveeLightController()

    public init(ignoreService: IgnoreService? = nil, storageService: DeviceStorageService? = nil) {
        self.ignoreService = ignoreService ?? .shared
        let storage = storageService ?? .shared
        self.storageService = storage
        self.devices = storage.loadDevices()
        super.init()
        self.goveeController.connectionManager = self
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    public private(set) var isBurstScanning: Bool = false
    private var burstTimer: Timer?
    private var isBurstActivePhase: Bool = false
    private var burstActiveDuration: TimeInterval = 4.0
    private var burstPauseDuration: TimeInterval = 4.0

    public func startScan() {
        guard let central = centralManager else { return }
        guard central.state == .poweredOn else {
            errorMessage = "Bluetooth is not powered on (\(central.state.description))."
            return
        }

        errorMessage = nil
        isScanning = true
        logger.info("Starting BLE scan for nearby devices and BTHome broadcasts...")

        // Scan allowing duplicates to ensure continuous RSSI and broadcast updates
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
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
                    self.centralManager?.stopScan()
                    self.isScanning = false
                    self.isBurstActivePhase = false
                    self.logger.debug("Burst scan cycle: paused (conserving battery)")
                } else {
                    // Switch to active scanning phase
                    guard let central = self.centralManager, central.state == .poweredOn else { return }
                    central.scanForPeripherals(
                        withServices: nil,
                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                    )
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
        centralManager?.stopScan()
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
        centralManager?.stopScan()
        isScanning = false
        storageService.saveDevicesSync(devices)
        logger.info("Stopped BLE scan.")
    }

    public func clear() {
        devices.removeAll()
        storageService.clear()
    }

    public func updateRoom(for deviceId: UUID, room: String?) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].assignedRoom = room
            storageService.scheduleSave(devices)
        }
    }

    public func updateDeviceName(id: UUID, customName: String?) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].customName = customName
            storageService.scheduleSave(devices)
        }
    }

    public func setDeviceIgnored(id: UUID, isIgnored: Bool) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].isIgnored = isIgnored
            storageService.scheduleSave(devices)
        }
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bluetoothState = central.state
        logger.info("Bluetooth state changed: \(central.state.description)")

        if central.state != .poweredOn {
            self.isScanning = false
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiVal = RSSI.intValue
        // Ignore out-of-range outlier readings (127 means unavailable in CoreBluetooth)
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
        if !rawName.isEmpty {
            resolvedName = rawName
        } else if let modelName = identification.resolvedName {
            resolvedName = modelName
        } else {
            resolvedName = "Unknown"
        }

        let isIgnored = ignoreService.isIgnored(
            id: identification.macAddress ?? peripheral.identifier.uuidString,
            name: resolvedName
        )
        let now = Date()

        // Match existing device by peripheral UUID or MAC address
        let existingIndex = devices.firstIndex { dev in
            dev.id == peripheral.identifier ||
            (identification.macAddress != nil && dev.macAddress == identification.macAddress)
        }

        if let index = existingIndex {
            // Update existing device in-place without removing or flickering
            devices[index].rssi = rssiVal
            devices[index].rssiHistory.append(rssiVal)
            if devices[index].rssiHistory.count > 20 {
                devices[index].rssiHistory.removeFirst()
            }
            if resolvedName != "Unknown" && (devices[index].name == "Unknown" || devices[index].name.isEmpty) {
                devices[index].name = resolvedName
            }
            if let btHomeData = identification.btHomeData {
                if devices[index].btHomeData != nil {
                    devices[index].btHomeData?.merge(with: btHomeData)
                } else {
                    devices[index].btHomeData = btHomeData
                }
                devices[index].lastMeasurementDate = now
            }
            if identification.family != .standardBLE {
                devices[index].family = identification.family
            }
            if let mac = identification.macAddress {
                devices[index].macAddress = mac
            }
            if isConnectable {
                devices[index].isConnectable = true
            }

            // Merge scan-response data (service UUIDs, manufacturer data, service data)
            for suuid in serviceUUIDStrings {
                if !devices[index].serviceUUIDs.contains(suuid) {
                    devices[index].serviceUUIDs.append(suuid)
                }
            }
            if let mfg = mfgDataHex, !mfg.isEmpty {
                if devices[index].manufacturerDataHex == nil || devices[index].manufacturerDataHex?.isEmpty == true {
                    devices[index].manufacturerDataHex = mfg
                }
            }
            if let sdict = serviceDataHexDict {
                if devices[index].serviceDataHex == nil {
                    devices[index].serviceDataHex = sdict
                } else {
                    for (k, v) in sdict {
                        devices[index].serviceDataHex?[k] = v
                    }
                }
            }

            devices[index].isIgnored = isIgnored
            devices[index].lastSeen = now
        } else {
            // Permanently record newly seen device
            let newDevice = DiscoveredDevice(
                id: peripheral.identifier,
                name: resolvedName,
                rssi: rssiVal,
                rssiHistory: [rssiVal],
                serviceUUIDs: serviceUUIDStrings,
                manufacturerDataHex: mfgDataHex,
                serviceDataHex: serviceDataHexDict,
                btHomeData: identification.btHomeData,
                family: identification.family,
                isConnectable: isConnectable,
                assignedRoom: nil,
                isIgnored: isIgnored,
                macAddress: identification.macAddress,
                firstSeen: now,
                lastSeen: now,
                lastMeasurementDate: identification.btHomeData != nil ? now : nil
            )
            devices.append(newDevice)
        }

        // Persist updated device inventory
        storageService.scheduleSave(devices)
    }

    // MARK: - BLEConnectionManager

    public func connect(peripheral: CBPeripheral) {
        peripheralMap[peripheral.identifier] = peripheral
        centralManager?.connect(peripheral, options: nil)
    }

    public func cancelConnection(peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    public func getPeripheral(id: UUID) -> CBPeripheral? {
        if let p = peripheralMap[id] { return p }
        return centralManager?.retrievePeripherals(withIdentifiers: [id]).first
    }

    // MARK: - CBCentralManager Connection Callbacks

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        goveeController.didConnect(peripheral: peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        goveeController.didFailToConnect(peripheral: peripheral, error: error)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        goveeController.didDisconnect(peripheral: peripheral, error: error)
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
