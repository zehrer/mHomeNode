import Foundation
@preconcurrency import CoreBluetooth
import OSLog
import SwiftUI

public protocol BLEConnectionManager: AnyObject {
    func connect(peripheral: CBPeripheral)
    func cancelConnection(peripheral: CBPeripheral)
    func getPeripheral(id: UUID) -> CBPeripheral?
}

@Observable
@MainActor
public final class GoveeLightController: NSObject, @preconcurrency CBPeripheralDelegate {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "GoveeLightController")

    public weak var connectionManager: BLEConnectionManager?

    // Device states
    public var powerState: [UUID: Bool] = [:]
    public var brightness: [UUID: Int] = [:]
    public var isBusy: [UUID: Bool] = [:]
    public var lastError: [UUID: String] = [:]
    public var selectedColorHex: [UUID: String] = [:]

    // Active command queue per device
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

    public func getBrightness(for deviceId: UUID) -> Int {
        brightness[deviceId] ?? 100
    }

    public func isDeviceBusy(_ deviceId: UUID) -> Bool {
        isBusy[deviceId] ?? false
    }

    public func togglePower(for deviceId: UUID) {
        let current = isPowerOn(for: deviceId)
        setPower(for: deviceId, isOn: !current)
    }

    public func setPower(for deviceId: UUID, isOn: Bool) {
        logger.info("Setting power for \(deviceId) -> \(isOn ? "ON" : "OFF")")
        powerState[deviceId] = isOn
        savePersistedState()

        let packet = GoveeCommand.power(isOn: isOn)
        sendCommand(packet: packet, for: deviceId)
    }

    public func setBrightness(for deviceId: UUID, percent: Int) {
        let clamped = max(1, min(100, percent))
        logger.info("Setting brightness for \(deviceId) -> \(clamped)%")
        brightness[deviceId] = clamped
        savePersistedState()

        let packet = GoveeCommand.brightness(percent: clamped)
        sendCommand(packet: packet, for: deviceId)
    }

    public func setColor(for deviceId: UUID, red: UInt8, green: UInt8, blue: UInt8) {
        logger.info("Setting color for \(deviceId) -> R:\(red) G:\(green) B:\(blue)")
        let hex = String(format: "#%02X%02X%02X", red, green, blue)
        selectedColorHex[deviceId] = hex
        savePersistedState()

        let packet = GoveeCommand.color(red: red, green: green, blue: blue)
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
            logger.warning("Peripheral \(deviceId) not found in cache or system")
            lastError[deviceId] = "Device not in range or not discovered yet"
            return
        }

        // Cancel any pending idle disconnect
        disconnectTimers[deviceId]?.cancel()
        disconnectTimers[deviceId] = nil

        isBusy[deviceId] = true
        lastError[deviceId] = nil

        // If peripheral is already connected and characteristic is known, write immediately
        if peripheral.state == .connected, let char = writeCharacteristics[deviceId] {
            writePacket(packet, to: char, on: peripheral)
            isBusy[deviceId] = false
            scheduleIdleDisconnect(for: deviceId, peripheral: peripheral)
            return
        }

        // Enqueue packet
        if pendingPackets[deviceId] == nil {
            pendingPackets[deviceId] = []
        }
        pendingPackets[deviceId]?.append(packet)

        // Set safety timeout (8 seconds)
        timeoutTasks[deviceId]?.cancel()
        timeoutTasks[deviceId] = Task { [weak self, weak peripheral] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                if self.isBusy[deviceId] == true {
                    self.isBusy[deviceId] = false
                    self.lastError[deviceId] = "Connection timed out"
                    self.pendingPackets[deviceId] = nil
                    if let p = peripheral {
                        mgr.cancelConnection(peripheral: p)
                    }
                }
            }
        }

        // Connect if not already connected
        if peripheral.state != .connected {
            peripheral.delegate = self
            mgr.connect(peripheral: peripheral)
        } else {
            // Already connected but discovering services
            peripheral.delegate = self
            peripheral.discoverServices([GoveeCommand.serviceUUID])
        }
    }

    private func writePacket(_ packet: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        peripheral.writeValue(packet, for: characteristic, type: writeType)
        logger.info("Transmitted Govee packet [\(packet.map { String(format: "%02hhX", $0) }.joined(separator: " "))] to \(peripheral.identifier)")
    }

    private func scheduleIdleDisconnect(for deviceId: UUID, peripheral: CBPeripheral) {
        disconnectTimers[deviceId]?.cancel()
        disconnectTimers[deviceId] = Task { [weak self, weak peripheral] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds idle disconnect
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                if let p = peripheral, p.state == .connected {
                    self.logger.info("Disconnecting idle Govee light \(deviceId) to preserve energy")
                    self.connectionManager?.cancelConnection(peripheral: p)
                    self.writeCharacteristics[deviceId] = nil
                }
            }
        }
    }

    // MARK: - Central Connection Lifecycle Forwarding

    public func didConnect(peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier
        logger.info("Connected to Govee peripheral \(deviceId)")
        peripheral.delegate = self
        peripheral.discoverServices([GoveeCommand.serviceUUID])
    }

    public func didFailToConnect(peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier
        let msg = error?.localizedDescription ?? "Failed to connect"
        logger.error("Failed to connect to \(deviceId): \(msg)")
        isBusy[deviceId] = false
        lastError[deviceId] = msg
        pendingPackets[deviceId] = nil
        timeoutTasks[deviceId]?.cancel()
    }

    public func didDisconnect(peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier
        logger.info("Disconnected from \(deviceId)")
        writeCharacteristics[deviceId] = nil
        timeoutTasks[deviceId]?.cancel()
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let deviceId = peripheral.identifier
        if let error = error {
            logger.error("Discover services error for \(deviceId): \(error.localizedDescription)")
            isBusy[deviceId] = false
            lastError[deviceId] = error.localizedDescription
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            logger.warning("No services found on \(deviceId)")
            isBusy[deviceId] = false
            lastError[deviceId] = "Govee service not found"
            return
        }

        // Find standard Govee service or inspect first custom service
        let goveeService = services.first(where: { $0.uuid == GoveeCommand.serviceUUID }) ?? services.first
        if let service = goveeService {
            peripheral.discoverCharacteristics([
                GoveeCommand.writeCharacteristicUUID,
                GoveeCommand.notifyCharacteristicUUID
            ], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let deviceId = peripheral.identifier
        timeoutTasks[deviceId]?.cancel()

        if let error = error {
            logger.error("Discover characteristics error for \(deviceId): \(error.localizedDescription)")
            isBusy[deviceId] = false
            lastError[deviceId] = error.localizedDescription
            return
        }

        guard let characteristics = service.characteristics else {
            isBusy[deviceId] = false
            lastError[deviceId] = "No characteristics discovered"
            return
        }

        // Find write characteristic
        let writeChar = characteristics.first(where: { $0.uuid == GoveeCommand.writeCharacteristicUUID })
            ?? characteristics.first(where: { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) })

        guard let targetChar = writeChar else {
            logger.error("Write characteristic not found for \(deviceId)")
            isBusy[deviceId] = false
            lastError[deviceId] = "Control characteristic not found"
            return
        }

        writeCharacteristics[deviceId] = targetChar

        // Flush queued packets
        if let packets = pendingPackets[deviceId], !packets.isEmpty {
            for packet in packets {
                writePacket(packet, to: targetChar, on: peripheral)
            }
            pendingPackets[deviceId] = nil
        }

        isBusy[deviceId] = false
        scheduleIdleDisconnect(for: deviceId, peripheral: peripheral)
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let data = UserDefaults.standard.dictionary(forKey: "mHomeNode.govee.power") as? [String: Bool] {
            for (key, val) in data {
                if let uuid = UUID(uuidString: key) {
                    powerState[uuid] = val
                }
            }
        }
        if let data = UserDefaults.standard.dictionary(forKey: "mHomeNode.govee.brightness") as? [String: Int] {
            for (key, val) in data {
                if let uuid = UUID(uuidString: key) {
                    brightness[uuid] = val
                }
            }
        }
        if let data = UserDefaults.standard.dictionary(forKey: "mHomeNode.govee.colorHex") as? [String: String] {
            for (key, val) in data {
                if let uuid = UUID(uuidString: key) {
                    selectedColorHex[uuid] = val
                }
            }
        }
    }

    private func savePersistedState() {
        var pData: [String: Bool] = [:]
        for (k, v) in powerState { pData[k.uuidString] = v }
        UserDefaults.standard.set(pData, forKey: "mHomeNode.govee.power")

        var bData: [String: Int] = [:]
        for (k, v) in brightness { bData[k.uuidString] = v }
        UserDefaults.standard.set(bData, forKey: "mHomeNode.govee.brightness")

        var cData: [String: String] = [:]
        for (k, v) in selectedColorHex { cData[k.uuidString] = v }
        UserDefaults.standard.set(cData, forKey: "mHomeNode.govee.colorHex")
    }
}
