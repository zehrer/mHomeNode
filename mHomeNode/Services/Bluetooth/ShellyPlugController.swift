import Foundation
import CoreBluetooth
import OSLog
import SwiftUI

@Observable
@MainActor
public final class ShellyPlugController: NSObject, CBPeripheralDelegate {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "ShellyPlugController")

    public weak var connectionManager: BLEConnectionManager?
    public let lanClient: ShellyLANClientProtocol
    public let lanDiscovery: ShellyLANDiscoveryService
    public var serverClient: (any HomeNodeServerClientProtocol)?
    public var serverConfigProvider: (@MainActor () -> (config: ServerConfig, isConnected: Bool))?

    // Device power states (persisted across app restarts)
    public var powerState: [UUID: Bool] = [:]
    public var isBusy: [UUID: Bool] = [:]
    public var lastError: [UUID: String] = [:]
    public var activeInterface: [UUID: ControlInterface] = [:]

    // Shelly Gen2/Gen3 BLE RPC Service & Characteristic UUIDs
    public static let shellyRpcServiceUUID = CBUUID(string: "5F5A0001-5D94-403F-A70B-A7F33667C0D3")
    public static let shellyRpcRxUUID = CBUUID(string: "5F5A0002-5D94-403F-A70B-A7F33667C0D3") // Data In / Write
    public static let shellyRpcTxUUID = CBUUID(string: "5F5A0003-5D94-403F-A70B-A7F33667C0D3") // Data Out / Notify

    // Active command queue & connection state per device (BLE)
    private var pendingPackets: [UUID: [Data]] = [:]
    private var writeCharacteristics: [UUID: CBCharacteristic] = [:]
    private var disconnectTimers: [UUID: Task<Void, Never>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        lanClient: ShellyLANClientProtocol = ShellyLANClient(),
        lanDiscovery: ShellyLANDiscoveryService? = nil
    ) {
        self.lanClient = lanClient
        self.lanDiscovery = lanDiscovery ?? .shared
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

    public func getActiveInterface(for deviceId: UUID) -> ControlInterface? {
        activeInterface[deviceId]
    }

    public func togglePower(for deviceId: UUID) {
        let current = isPowerOn(for: deviceId)
        setPower(for: deviceId, isOn: !current)
    }

    public func togglePower(for device: DiscoveredDevice) {
        let current = isPowerOn(for: device.id)
        setPower(for: device, isOn: !current)
    }

    public func setPower(for device: DiscoveredDevice, isOn: Bool) {
        setPower(
            for: device.id,
            lanHost: device.lanAddress,
            macAddress: device.macAddress,
            name: device.name,
            isOn: isOn
        )
    }

    public func setPower(for deviceId: UUID, isOn: Bool) {
        setPower(for: deviceId, lanHost: nil, macAddress: nil, name: nil, isOn: isOn)
    }

    /// Hybrid multi-path power control:
    /// 1. HomeNode Server (if server is active & online)
    /// 2. Local Wi-Fi / LAN HTTP RPC (if IP known or discovered via Bonjour)
    /// 3. Direct BLE CoreBluetooth RPC (fallback if LAN is unavailable or out of range)
    public func setPower(
        for deviceId: UUID,
        lanHost: String? = nil,
        macAddress: String? = nil,
        name: String? = nil,
        isOn: Bool
    ) {
        logger.info("Setting Shelly plug power for \(deviceId) -> \(isOn ? "ON" : "OFF") [LAN hint: \(lanHost ?? "none")]")
        powerState[deviceId] = isOn
        savePersistedState()
        isBusy[deviceId] = true
        lastError[deviceId] = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            // -------------------------------------------------------------
            // Path 1: HomeNode Server API (if server is active & connected)
            // -------------------------------------------------------------
            if let provider = self.serverConfigProvider {
                let (config, isConnected) = provider()
                if isConnected, let sClient = self.serverClient {
                    let targetId = macAddress ?? deviceId.uuidString
                    do {
                        self.logger.info("Attempting Shelly control via HomeNode Server for \(targetId)...")
                        let ok = try await sClient.toggleDevice(config: config, id: targetId, isOn: isOn)
                        if ok {
                            self.activeInterface[deviceId] = .server
                            self.isBusy[deviceId] = false
                            self.logger.info("Shelly controlled successfully via HomeNode Server")
                            return
                        }
                    } catch {
                        self.logger.info("HomeNode Server control failed: \(error.localizedDescription); trying LAN...")
                    }
                }
            }

            // -------------------------------------------------------------
            // Path 2: Direct Local LAN HTTP RPC
            // -------------------------------------------------------------
            var resolvedHost = lanHost
            if resolvedHost == nil || resolvedHost?.isEmpty == true {
                resolvedHost = self.lanDiscovery.lookupHost(macAddress: macAddress, name: name)
            }

            if let host = resolvedHost, !host.isEmpty {
                do {
                    self.logger.info("Attempting Shelly control via LAN at \(host)...")
                    let ok = try await self.lanClient.setPower(host: host, isOn: isOn, channel: 0)
                    if ok {
                        self.activeInterface[deviceId] = .lan
                        self.isBusy[deviceId] = false
                        self.logger.info("Shelly controlled successfully via direct LAN (\(host))")
                        return
                    }
                } catch {
                    self.logger.info("Shelly LAN control failed at \(host): \(error.localizedDescription); falling back to BLE...")
                }
            }

            // -------------------------------------------------------------
            // Path 3: Direct BLE CoreBluetooth RPC Fallback
            // -------------------------------------------------------------
            self.logger.info("Dispatching Shelly control via direct Bluetooth LE for \(deviceId)...")
            self.activeInterface[deviceId] = .ble

            let rpcJson = "{\"id\":1,\"src\":\"mHomeNode\",\"method\":\"Switch.Set\",\"params\":{\"id\":0,\"on\":\(isOn)}}"
            guard let packet = rpcJson.data(using: .utf8) else {
                self.isBusy[deviceId] = false
                return
            }

            self.sendBLECommand(packet: packet, for: deviceId)
        }
    }

    // MARK: - BLE Command Execution & Connection Pipeline

    private func sendBLECommand(packet: Data, for deviceId: UUID) {
        guard let mgr = connectionManager else {
            logger.error("Connection manager not configured")
            lastError[deviceId] = "BLE Connection Manager unavailable"
            isBusy[deviceId] = false
            return
        }

        guard let peripheral = mgr.getPeripheral(id: deviceId) else {
            logger.info("Peripheral \(deviceId) not in active BLE cache; command retained in local state.")
            isBusy[deviceId] = false
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

    // MARK: - Central Connection Lifecycle Forwarding

    public func didConnect(peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard pendingPackets[id] != nil else { return }
        logger.info("Connected to Shelly plug \(id)")
        peripheral.delegate = self
        peripheral.discoverServices([Self.shellyRpcServiceUUID])
    }

    public func didFailToConnect(peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        guard pendingPackets[id] != nil else { return }
        let msg = error?.localizedDescription ?? "Failed to connect"
        logger.error("Failed to connect to Shelly plug \(id): \(msg)")
        isBusy[id] = false
        lastError[id] = msg
        pendingPackets[id] = nil
        timeoutTasks[id]?.cancel()
    }

    public func didDisconnect(peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        guard pendingPackets[id] != nil || writeCharacteristics[id] != nil else { return }
        logger.info("Disconnected from Shelly plug \(id)")
        writeCharacteristics[id] = nil
        timeoutTasks[id]?.cancel()
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
