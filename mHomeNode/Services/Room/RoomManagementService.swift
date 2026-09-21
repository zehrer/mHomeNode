import Foundation
import SwiftUI
import OSLog

@Observable
@MainActor
public final class RoomManagementService {
    public static let shared = RoomManagementService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "RoomManagement")
    private let fileURL: URL

    public var rooms: [ManagedRoom] = []
    public var lastSyncedDate: Date?

    public static let defaultRooms: [ManagedRoom] = [
        ManagedRoom(name: "Living Room", icon: "sofa.fill", colorHex: "#34C759", source: .local),
        ManagedRoom(name: "Bedroom", icon: "bed.double.fill", colorHex: "#5856D6", source: .local),
        ManagedRoom(name: "Kitchen", icon: "fork.knife", colorHex: "#FF9500", source: .local),
        ManagedRoom(name: "Office", icon: "laptopcomputer", colorHex: "#007AFF", source: .local),
        ManagedRoom(name: "Bathroom", icon: "bathtub.fill", colorHex: "#5AC8FA", source: .local)
    ]

    public init(customFileURL: URL? = nil) {
        if let custom = customFileURL {
            self.fileURL = custom
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("mHomeNode", isDirectory: true)
            if !fileManager.fileExists(atPath: appFolder.path) {
                try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }
            self.fileURL = appFolder.appendingPathComponent("rooms.json")
        }

        self.rooms = loadRoomsFromDisk()
        if self.rooms.isEmpty {
            self.rooms = Self.defaultRooms
            saveRoomsToDisk()
        }
    }

    // MARK: - CRUD Operations

    @discardableResult
    public func addRoom(
        name: String,
        icon: String = "door.left.hand.open",
        colorHex: String? = nil,
        source: RoomSource = .local
    ) -> ManagedRoom {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // If room with same name already exists, return existing
        if let existing = rooms.first(where: { $0.name.lowercased() == cleanName.lowercased() }) {
            return existing
        }

        let newRoom = ManagedRoom(
            name: cleanName,
            icon: icon,
            colorHex: colorHex,
            source: source
        )
        rooms.append(newRoom)
        saveRoomsToDisk()
        logger.info("Added room '\(cleanName)' (source: \(source.rawValue))")
        return newRoom
    }

    public func updateRoom(id: String, name: String, icon: String, colorHex: String?) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        rooms[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rooms[index].icon = icon
        rooms[index].colorHex = colorHex
        rooms[index].updatedAt = Date()
        saveRoomsToDisk()
        logger.info("Updated room '\(name)' (\(id))")
    }

    public func deleteRoom(id: String) {
        rooms.removeAll(where: { $0.id == id })
        saveRoomsToDisk()
        logger.info("Deleted room (\(id))")
    }

    public func room(named name: String) -> ManagedRoom? {
        rooms.first(where: { $0.name.lowercased() == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    public func allRoomNames() -> [String] {
        rooms.map(\.name)
    }

    // MARK: - Synchronization

    /// Merges server rooms into local persistent registry
    public func syncWithServerRooms(_ serverRooms: [ServerRoom]) {
        guard !serverRooms.isEmpty else { return }

        for sRoom in serverRooms {
            let sName = sRoom.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = rooms.firstIndex(where: { $0.name.lowercased() == sName.lowercased() }) {
                // Update existing room with server reference
                rooms[index].serverRoomId = sRoom.id
                if let sIcon = sRoom.icon, !sIcon.isEmpty, rooms[index].icon == "door.left.hand.open" {
                    rooms[index].icon = sIcon
                }
            } else {
                // Add new server room
                let newRoom = ManagedRoom(
                    id: sRoom.id,
                    name: sName,
                    icon: sRoom.icon ?? "door.left.hand.open",
                    source: .homeNodeServer,
                    serverRoomId: sRoom.id
                )
                rooms.append(newRoom)
            }
        }

        lastSyncedDate = Date()
        saveRoomsToDisk()
        logger.info("Successfully merged \(serverRooms.count) server room(s)")
    }

    /// Prepares for Philips Hue synchronization
    public func syncWithHue(hueRooms: [(id: String, name: String, icon: String?)]) {
        for hue in hueRooms {
            let hName = hue.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = rooms.firstIndex(where: { $0.name.lowercased() == hName.lowercased() }) {
                rooms[index].externalId = hue.id
            } else {
                let newRoom = ManagedRoom(
                    name: hName,
                    icon: hue.icon ?? "lightbulb.fill",
                    source: .philipsHue,
                    externalId: hue.id
                )
                rooms.append(newRoom)
            }
        }
        saveRoomsToDisk()
    }

    /// Prepares for Apple Home (HomeKit) synchronization
    public func syncWithAppleHome(homeKitRooms: [(id: String, name: String)]) {
        for hk in homeKitRooms {
            let hkName = hk.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = rooms.firstIndex(where: { $0.name.lowercased() == hkName.lowercased() }) {
                rooms[index].externalId = hk.id
            } else {
                let newRoom = ManagedRoom(
                    name: hkName,
                    icon: "homekit",
                    source: .appleHome,
                    externalId: hk.id
                )
                rooms.append(newRoom)
            }
        }
        saveRoomsToDisk()
    }

    // MARK: - Persistence

    private func loadRoomsFromDisk() -> [ManagedRoom] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([ManagedRoom].self, from: data)
            return decoded
        } catch {
            logger.error("Failed to load rooms from disk: \(error.localizedDescription)")
            return []
        }
    }

    private func saveRoomsToDisk() {
        do {
            let data = try JSONEncoder().encode(rooms)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Failed to save rooms to disk: \(error.localizedDescription)")
        }
    }
}
