import Foundation
import OSLog

/// Service responsible for persisting saved BLE scan sessions to disk
public final class SavedScanStorageService: @unchecked Sendable {
    public static let shared = SavedScanStorageService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "SavedScanStorage")
    private let fileURL: URL
    private let queue = DispatchQueue(label: "net.zehrer.homenode.saved_scans.storage", qos: .utility)

    public init(customDirectoryURL: URL? = nil) {
        if let customDir = customDirectoryURL {
            self.fileURL = customDir.appendingPathComponent("saved_scans.json")
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("mHomeNode", isDirectory: true)

            if !fileManager.fileExists(atPath: appFolder.path) {
                try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }
            self.fileURL = appFolder.appendingPathComponent("saved_scans.json")
        }
    }

    /// Loads all saved scan sessions from disk, ordered by date (newest first)
    public func loadSessions() -> [SavedScanSession] {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                logger.info("No saved scan sessions found on disk.")
                return []
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let sessions = try decoder.decode([SavedScanSession].self, from: data)
                logger.info("Successfully loaded \(sessions.count) saved scan sessions.")
                return sessions.sorted { $0.timestamp > $1.timestamp }
            } catch {
                logger.error("Failed to load saved scan sessions: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Saves a new scan session or updates an existing one
    public func saveSession(_ session: SavedScanSession) {
        queue.sync {
            var existing = self.internalLoad()
            if let index = existing.firstIndex(where: { $0.id == session.id }) {
                existing[index] = session
            } else {
                existing.insert(session, at: 0)
            }
            self.internalWrite(existing)
        }
    }

    /// Deletes a scan session by its UUID
    public func deleteSession(id: UUID) {
        queue.sync {
            var existing = self.internalLoad()
            existing.removeAll { $0.id == id }
            self.internalWrite(existing)
        }
    }

    /// Clears all saved scan sessions
    public func clearAll() {
        queue.sync {
            self.internalWrite([])
        }
    }

    // MARK: - Internal Helpers

    private func internalLoad() -> [SavedScanSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SavedScanSession].self, from: data)
        } catch {
            logger.warning("Could not read saved sessions: \(error.localizedDescription)")
            return []
        }
    }

    private func internalWrite(_ sessions: [SavedScanSession]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
            logger.debug("Successfully persisted \(sessions.count) saved scan sessions.")
        } catch {
            logger.error("Failed to write saved scan sessions to disk: \(error.localizedDescription)")
        }
    }
}
