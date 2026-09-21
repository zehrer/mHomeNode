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
        ManagedRoom(name: "Living Room", floor: "Erdgeschoss", icon: "sofa.fill", colorHex: "#34C759", source: .local),
        ManagedRoom(name: "Bedroom", floor: "Obergeschoss", icon: "bed.double.fill", colorHex: "#5856D6", source: .local),
        ManagedRoom(name: "Kitchen", floor: "Erdgeschoss", icon: "fork.knife", colorHex: "#FF9500", source: .local),
        ManagedRoom(name: "Office", floor: "Obergeschoss", icon: "laptopcomputer", colorHex: "#007AFF", source: .local),
        ManagedRoom(name: "Bathroom", floor: "Obergeschoss", icon: "bathtub.fill", colorHex: "#5AC8FA", source: .local)
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
        // Sanitize any existing emoji icons to valid SF symbols
        var needsSave = false
        for i in self.rooms.indices {
            if !self.rooms[i].icon.isSFSymbolName {
                self.rooms[i].icon = ManagedRoom.sfSymbol(for: self.rooms[i].icon)
                needsSave = true
            }
        }
        if self.rooms.isEmpty {
            self.rooms = Self.defaultRooms
            saveRoomsToDisk()
        } else if needsSave {
            saveRoomsToDisk()
        }
    }

    // MARK: - CRUD Operations

    @discardableResult
    public func addRoom(
        name: String,
        floor: String? = nil,
        icon: String = "door.left.hand.open",
        colorHex: String? = nil,
        source: RoomSource = .local,
        serverRoomId: String? = nil
    ) -> ManagedRoom {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFloor = floor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFloor = (cleanFloor?.isEmpty == true) ? nil : cleanFloor

        // If room with same name already exists, update and return existing
        if let index = rooms.firstIndex(where: { $0.name.lowercased() == cleanName.lowercased() }) {
            if resolvedFloor != nil && rooms[index].floor == nil {
                rooms[index].floor = resolvedFloor
            }
            if serverRoomId != nil && rooms[index].serverRoomId == nil {
                rooms[index].serverRoomId = serverRoomId
            }
            saveRoomsToDisk()
            return rooms[index]
        }

        let newRoom = ManagedRoom(
            name: cleanName,
            floor: resolvedFloor,
            icon: icon,
            colorHex: colorHex,
            source: source,
            serverRoomId: serverRoomId
        )
        rooms.append(newRoom)
        saveRoomsToDisk()
        logger.info("Added room '\(cleanName)' (floor: \(resolvedFloor ?? "-"), source: \(source.rawValue))")
        return newRoom
    }

    public func updateRoom(id: String, name: String, floor: String? = nil, icon: String, colorHex: String?) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        let cleanFloor = floor?.trimmingCharacters(in: .whitespacesAndNewlines)
        rooms[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rooms[index].floor = (cleanFloor?.isEmpty == true) ? nil : cleanFloor
        rooms[index].icon = icon
        rooms[index].colorHex = colorHex
        rooms[index].updatedAt = Date()
        saveRoomsToDisk()
        logger.info("Updated room '\(name)' (\(id)) on floor '\(cleanFloor ?? "-")'")
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

    // MARK: - Floor Helpers

    /// Distinct sorted list of floors present in the managed rooms
    public var distinctFloors: [String] {
        var set = Set<String>()
        for r in rooms {
            if let f = r.floor?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
                set.insert(f)
            }
        }
        let orderMap: [String: Int] = [
            "Erdgeschoss": 1, "EG": 1, "Ground Floor": 1,
            "Obergeschoss": 2, "1. OG": 2, "OG": 2, "First Floor": 2,
            "2. OG": 3, "2. Obergeschoss": 3,
            "Keller": 10, "UG": 10, "Untergeschoss": 10, "Basement": 10,
            "Dachgeschoss": 15, "DG": 15, "Attic": 15,
            "Außenbereich": 20, "Garten": 20, "Outdoor": 20
        ]
        return set.sorted { a, b in
            let ordA = orderMap[a] ?? 100
            let ordB = orderMap[b] ?? 100
            if ordA != ordB { return ordA < ordB }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    /// Rooms for a specific floor (nil or empty floor string returns rooms without an assigned floor)
    public func rooms(forFloor floor: String?) -> [ManagedRoom] {
        if let floor = floor?.trimmingCharacters(in: .whitespacesAndNewlines), !floor.isEmpty {
            return rooms.filter { $0.floor?.lowercased() == floor.lowercased() }
        } else {
            return rooms.filter { $0.floor == nil || $0.floor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true }
        }
    }

    // MARK: - Synchronization

    /// Merges server rooms into local persistent registry and reconciles duplicates
    public func syncWithServerRooms(_ serverRooms: [ServerRoom]) {
        guard !serverRooms.isEmpty else { return }

        // If local rooms only consist of default seed rooms (never customized) and server has rooms,
        // supersede the dummy seed rooms with actual server rooms to prevent parallel duplicates.
        let isDefaultSeedOnly = rooms.count == Self.defaultRooms.count &&
            rooms.allSatisfy { r in
                Self.defaultRooms.contains(where: { $0.name.lowercased() == r.name.lowercased() && r.serverRoomId == nil })
            }
        if isDefaultSeedOnly {
            rooms.removeAll()
        }

        for sRoom in serverRooms {
            let sName = sRoom.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedIcon = sRoom.icon.map { ManagedRoom.sfSymbol(for: $0) } ?? "door.left.hand.open"

            // Match either by serverRoomId or case-insensitive name
            if let index = rooms.firstIndex(where: {
                $0.serverRoomId == sRoom.id || $0.name.lowercased() == sName.lowercased()
            }) {
                // Unify existing room with server reference
                rooms[index].serverRoomId = sRoom.id
                rooms[index].name = sName
                rooms[index].source = .homeNodeServer
                if let sFloor = sRoom.floor, !sFloor.isEmpty {
                    rooms[index].floor = sFloor
                }
                if rooms[index].icon == "door.left.hand.open" {
                    rooms[index].icon = mappedIcon
                }
            } else {
                // Add new server room
                let newRoom = ManagedRoom(
                    id: sRoom.id,
                    name: sName,
                    floor: sRoom.floor,
                    icon: mappedIcon,
                    source: .homeNodeServer,
                    serverRoomId: sRoom.id
                )
                rooms.append(newRoom)
            }
        }

        lastSyncedDate = Date()
        saveRoomsToDisk()
        logger.info("Successfully merged and reconciled \(serverRooms.count) server room(s)")
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
