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
    public var searchText: String = ""
    public var onlyKnownDevices: Bool = false
    public var minRSSI: Double = -100
    public var sortOrder: DeviceSortOrder = .rssi

    public init(bleService: BLEScannerService? = nil) {
        self.bleService = bleService ?? BLEScannerService()
    }

    public var isScanning: Bool {
        bleService.isScanning
    }

    public var bluetoothStateText: String {
        bleService.bluetoothState.description
    }

    public var filteredDevices: [DiscoveredDevice] {
        let list = bleService.devices.filter { device in
            if onlyKnownDevices && device.family == .standardBLE {
                return false
            }
            if Double(device.rssi) < minRSSI {
                return false
            }
            if !searchText.isEmpty {
                let matchesName = device.displayTitle.localizedCaseInsensitiveContains(searchText)
                let matchesUUID = device.id.uuidString.localizedCaseInsensitiveContains(searchText)
                let matchesRoom = (device.assignedRoom ?? "").localizedCaseInsensitiveContains(searchText)
                return matchesName || matchesUUID || matchesRoom
            }
            return true
        }

        switch sortOrder {
        case .rssi:
            return list.sorted { $0.rssi > $1.rssi }
        case .name:
            return list.sorted { $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending }
        case .lastSeen:
            return list.sorted { $0.lastSeen > $1.lastSeen }
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
}
