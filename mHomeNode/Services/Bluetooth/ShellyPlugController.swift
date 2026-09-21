import Foundation
import CoreBluetooth
import OSLog
import SwiftUI

@Observable
@MainActor
public final class ShellyPlugController: NSObject, CBPeripheralDelegate {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "ShellyPlugController")

    public weak var connectionManager: BLEConnectionManager?

    // Device power states (persisted across app restarts)
    public var powerState: [UUID: Bool] = [:]
    public var isBusy: [UUID: Bool] = [:]
    public var lastError: [UUID: String] = [:]

    // Shelly Gen2/Gen3 BLE RPC Service & Characteristic UUIDs
    public static let shellyRpcServiceUUID = CBUUID(string: "5F5A0001-5D94-403F-A70B-A7F33667C0D3")
    public static let shellyRpcRxUUID = CBUUID(string: "5F5A0002-5D94-403F-A70B-A7F33667C0D3") // Data In / Write
    public static let shellyRpcTxUUID = CBUUID(string: "5F5A0003-5D94-403F-A70B-A7F33667C0D3") // Data Out / Notify

    // Active command queue & connection state per device
    private var pendingPackets: [UUID: [Data]] = [:]
    private var writeCharacteristics: [UUID: CBCharacteristic] = [:]
    private var disconnectTimers: [UUID: Task<Void, Never>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    public override init() {
        super.init()
        loadPersistedState()
    }

    // MARK: - Public Control APIs

    public func isPowerOn(for deviceId: UUID) -> Bool {
        powerState[deviceId] ?? false
    }

    public func isDeviceBusy(_ deviceId: UUID) -> Bool {
        isBusy[deviceId] ?? false
    }

    public func togglePower(for deviceId: UUID) {
        let current = isPowerOn(for: deviceId)
        setPower(for: deviceId, isOn: !current)
    }

    public func setPower(for deviceId: UUID, isOn: Bool) {
        logger.info("Setting Shelly plug power for \(deviceId) -> \(isOn ? "ON" : "OFF")")
        powerState[deviceId] = isOn
        savePersistedState()

        // Construct Shelly RPC JSON frame
        let rpcJson = "{\"id\":1,\"src\":\"mHomeNode\",\"method\":\"Switch.Set\",\"params\":{\"id\":0,\"on\":\(isOn)}}"
        guard let packet = rpcJson.data(using: .utf8) else { return }

        sendCommand(packet: packet, for: deviceId)
    }

    // MARK: - Command Execution & Connection Pipeline

    private func sendCommand(packet: Data, for deviceId: UUID) {
        guard let mgr = connectionManager else {
            logger.error("Connection manager not configured")
            lastError[deviceId] = "BLE Connection Manager unavailable"
            return
        }

        guard let peripheral = mgr.getPeripheral(id: deviceId) else {
            logger.info("Peripheral \(deviceId) not in active BLE cache; state updated locally.")
            return
        }

        // Enqueue command
        if pendingPackets[deviceId] == nil {
            pendingPackets[deviceId] = []
        }
        pendingPackets[deviceId]?.append(packet)
        isBusy[deviceId] = true
        lastError[deviceId] = nil

        // Set safety timeout
        timeoutTasks[deviceId]?.cancel()
        timeoutTasks[deviceId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if let self = self, self.isBusy[deviceId] == true {
                self.isBusy[deviceId] = false
                self.lastError[deviceId] = "Command timed out"
                self.cleanupConnection(for: peripheral)
            }
        }

        // Cancel pending disconnect timer if active
        disconnectTimers[deviceId]?.cancel()
        disconnectTimers[deviceId] = nil

        peripheral.delegate = self

        switch peripheral.state {
        case .connected:
            if let char = writeCharacteristics[deviceId] {
                flushPendingCommands(to: peripheral, characteristic: char)
            } else {
                peripheral.discoverServices([Self.shellyRpcServiceUUID])
            }
        case .connecting:
            break
        case .disconnected, .disconnecting:
            mgr.connect(peripheral: peripheral)
        @unknown default:
            break
        }
    }

    // MARK: - CBPeripheralDelegate Callbacks

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { @MainActor in
            let id = peripheral.identifier
            if let error = error {
                logger.error("Service discovery failed for \(id): \(error.localizedDescription)")
                self.lastError[id] = error.localizedDescription
                self.isBusy[id] = false
                return
            }

            guard let services = peripheral.services, !services.isEmpty else {
                // Try discovering all services as fallback
                peripheral.discoverServices(nil)
                return
            }

            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        Task { @MainActor in
            let id = peripheral.identifier
            if let error = error {
                logger.error("Characteristic discovery failed for \(id): \(error.localizedDescription)")
                self.lastError[id] = error.localizedDescription
                self.isBusy[id] = false
                return
            }

            guard let chars = service.characteristics else { return }
            for char in chars {
                // Match Shelly RPC RX or any writable characteristic
                if char.uuid == Self.shellyRpcRxUUID ||
                   char.properties.contains(.write) ||
                   char.properties.contains(.writeWithoutResponse) {
                    self.writeCharacteristics[id] = char
                    self.flushPendingCommands(to: peripheral, characteristic: char)
                    return
                }
            }
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        Task { @MainActor in
            let id = peripheral.identifier
            if let error = error {
                logger.error("Write failed for \(id): \(error.localizedDescription)")
                self.lastError[id] = error.localizedDescription
            } else {
                logger.info("Command acknowledged by \(id)")
            }
            self.checkFinishedAndScheduleDisconnect(peripheral: peripheral)
        }
    }

    private func flushPendingCommands(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let id = peripheral.identifier
        guard var queue = pendingPackets[id], !queue.isEmpty else {
            checkFinishedAndScheduleDisconnect(peripheral: peripheral)
            return
        }

        let packet = queue.removeFirst()
        pendingPackets[id] = queue

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(packet, for: characteristic, type: writeType)

        if writeType == .withoutResponse {
            if queue.isEmpty {
                checkFinishedAndScheduleDisconnect(peripheral: peripheral)
            } else {
                flushPendingCommands(to: peripheral, characteristic: characteristic)
            }
        }
    }

    private func checkFinishedAndScheduleDisconnect(peripheral: CBPeripheral) {
        let id = peripheral.identifier
        if pendingPackets[id]?.isEmpty ?? true {
            isBusy[id] = false
            timeoutTasks[id]?.cancel()
            timeoutTasks[id] = nil

            // Disconnect after 3 seconds of inactivity
            disconnectTimers[id]?.cancel()
            disconnectTimers[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.cleanupConnection(for: peripheral)
            }
        }
    }

    private func cleanupConnection(for peripheral: CBPeripheral) {
        let id = peripheral.identifier
        writeCharacteristics[id] = nil
        pendingPackets[id] = nil
        isBusy[id] = false
        connectionManager?.cancelConnection(peripheral: peripheral)
    }

    // MARK: - State Persistence

    private let persistenceKey = "mHomeNode_shelly_plug_power_states"

    private func savePersistedState() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: powerState.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(stringKeyed, forKey: persistenceKey)
    }

    private func loadPersistedState() {
        guard let dict = UserDefaults.standard.dictionary(forKey: persistenceKey) as? [String: Bool] else { return }
        var result: [UUID: Bool] = [:]
        for (k, v) in dict {
            if let uuid = UUID(uuidString: k) {
                result[uuid] = v
            }
        }
        self.powerState = result
    }
}
