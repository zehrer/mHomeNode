import Foundation
import CoreBluetooth
import OSLog

@Observable
@MainActor
public final class BLEScannerService: NSObject, @preconcurrency CBCentralManagerDelegate {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "BLEScanner")
    private var centralManager: CBCentralManager?

    public var isScanning: Bool = false
    public var bluetoothState: CBManagerState = .unknown
    public var devices: [DiscoveredDevice] = []
    public var errorMessage: String?

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

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

    public func stopScan() {
        centralManager?.stopScan()
        isScanning = false
        logger.info("Stopped BLE scan.")
    }

    public func clear() {
        devices.removeAll()
    }

    public func updateRoom(for deviceId: UUID, room: String?) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].assignedRoom = room
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
        // Ignore out-of-range outlier readings
        guard rssiVal != 127 else { return }

        let rawName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false

        // Extract service UUIDs
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let serviceUUIDStrings = serviceUUIDs.map { $0.uuidString }

        // Extract Service Data
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]

        // Extract Manufacturer Data
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let mfgDataHex = mfgData?.map { String(format: "%02hhX", $0) }.joined()

        let (family, btHomeData) = DeviceFingerprinter.identify(
            advertisedName: rawName,
            serviceUUIDs: serviceUUIDs,
            serviceData: serviceData,
            manufacturerData: mfgData
        )

        let now = Date()

        if let index = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Update existing device
            devices[index].rssi = rssiVal
            devices[index].rssiHistory.append(rssiVal)
            if devices[index].rssiHistory.count > 20 {
                devices[index].rssiHistory.removeFirst()
            }
            if !rawName.isEmpty && devices[index].name != rawName {
                devices[index].name = rawName
            }
            if let btHomeData = btHomeData {
                devices[index].btHomeData = btHomeData
            }
            if family != .standardBLE {
                devices[index].family = family
            }
            devices[index].lastSeen = now
        } else {
            // New device found
            let newDevice = DiscoveredDevice(
                id: peripheral.identifier,
                name: rawName.isEmpty ? "Unknown" : rawName,
                rssi: rssiVal,
                rssiHistory: [rssiVal],
                serviceUUIDs: serviceUUIDStrings,
                manufacturerDataHex: mfgDataHex,
                btHomeData: btHomeData,
                family: family,
                isConnectable: isConnectable,
                firstSeen: now,
                lastSeen: now
            )
            devices.append(newDevice)
        }
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
