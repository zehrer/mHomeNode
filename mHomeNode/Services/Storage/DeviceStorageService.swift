import Foundation
import OSLog

/// Service responsible for persisting discovered BLE devices to disk
/// Stores devices as JSON in Application Support so inventory survives app restarts.
public final class DeviceStorageService: @unchecked Sendable {
    public static let shared = DeviceStorageService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "DeviceStorage")
    private let fileURL: URL
    private let queue = DispatchQueue(label: "net.zehrer.homenode.storage", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    public init(customDirectoryURL: URL? = nil) {
        if let customDir = customDirectoryURL {
            self.fileURL = customDir.appendingPathComponent("device_inventory.json")
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("mHomeNode", isDirectory: true)

            if !fileManager.fileExists(atPath: appFolder.path) {
                try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }
            self.fileURL = appFolder.appendingPathComponent("device_inventory.json")
        }
    }

    /// Loads saved devices from disk
    public func loadDevices() -> [DiscoveredDevice] {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                logger.info("No saved device inventory found on disk.")
                return []
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let devices = try decoder.decode([DiscoveredDevice].self, from: data)
                logger.info("Successfully loaded \(devices.count) devices from persistent storage.")
                return devices
            } catch {
                logger.error("Failed to load devices from disk: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Saves devices to disk synchronously
    public func saveDevicesSync(_ devices: [DiscoveredDevice]) {
        queue.sync {
            self.writeDevices(devices)
        }
    }

    /// Debounced save: bundles rapid BLE discovery updates to write to disk at most once every 2 seconds
    public func scheduleSave(_ devices: [DiscoveredDevice]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.saveWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.writeDevices(devices)
            }
            self.saveWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }

    /// Clears the stored device inventory from disk
    public func clear() {
        queue.sync {
            saveWorkItem?.cancel()
            try? FileManager.default.removeItem(at: fileURL)
            logger.info("Cleared device inventory from disk.")
        }
    }

    /// Count of currently stored devices on disk
    public var storedDevicesCount: Int {
        loadDevices().count
    }

    private func writeDevices(_ devices: [DiscoveredDevice]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(devices)
            try data.write(to: fileURL, options: [.atomicWrite])
            logger.debug("Saved \(devices.count) devices to disk.")
        } catch {
            logger.error("Failed to write devices to disk: \(error.localizedDescription)")
        }
    }
}
