import Foundation
import OSLog

@Observable
@MainActor
public final class IgnoreService {
    public static let shared = IgnoreService()
    private let userDefaultsKey = "net.zehrer.homenode.ignored_devices"
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "IgnoreService")

    public var ignoredRecords: [IgnoredDeviceRecord] = []

    public init() {
        load()
    }

    public func isIgnored(id: String, name: String? = nil) -> Bool {
        let normId = normalize(id)
        if normId.isEmpty { return false }

        for r in ignoredRecords {
            let rNorm = r.normalizedId
            if rNorm == normId { return true }
            if rNorm.count >= 8 && (normId.contains(rNorm) || rNorm.contains(normId)) {
                return true
            }
            if let targetName = name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
               !targetName.isEmpty,
               let ignoredName = r.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
               !ignoredName.isEmpty && targetName == ignoredName {
                return true
            }
        }
        return false
    }

    public func ignore(id: String, name: String? = nil, reason: String = "Nachbargerät") {
        let record = IgnoredDeviceRecord(id: id, name: name, reason: reason)
        if !ignoredRecords.contains(where: { $0.normalizedId == record.normalizedId }) {
            ignoredRecords.append(record)
            save()
            logger.info("Ignored device: \(id) (\(name ?? ""))")
        }
    }

    public func unignore(id: String) {
        let norm = normalize(id)
        let countBefore = ignoredRecords.count
        ignoredRecords.removeAll { $0.normalizedId == norm || $0.id == id }
        if ignoredRecords.count != countBefore {
            save()
            logger.info("Unignored device: \(id)")
        }
    }

    public func syncWithServer(client: HomeNodeServerClientProtocol, config: ServerConfig) async {
        do {
            let serverList = try await client.fetchIgnoredDevices(config: config)
            var merged = self.ignoredRecords
            for s in serverList {
                if !merged.contains(where: { $0.normalizedId == s.normalizedId }) {
                    merged.append(s)
                }
            }
            self.ignoredRecords = merged
            save()

            // Push locally ignored records to server if not present
            for loc in self.ignoredRecords {
                if !serverList.contains(where: { $0.normalizedId == loc.normalizedId }) {
                    let _ = try? await client.ignoreDeviceOnServer(config: config, id: loc.id, name: loc.name, reason: loc.reason)
                }
            }
        } catch {
            logger.warning("Could not sync ignored devices with server: \(error.localizedDescription)")
        }
    }

    private func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([IgnoredDeviceRecord].self, from: data) {
            self.ignoredRecords = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(ignoredRecords) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
