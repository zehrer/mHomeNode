import Foundation

public struct ServerStatus: Codable, Sendable {
    public let version: String
    public let uptimeSeconds: UInt64
    public let activeMatterNodes: Int
    public let activeBLEGateways: Int
    public let activeDevices: Int?

    public init(
        version: String = "0.1.0-alpha",
        uptimeSeconds: UInt64 = 4200,
        activeMatterNodes: Int = 3,
        activeBLEGateways: Int = 2,
        activeDevices: Int? = 100
    ) {
        self.version = version
        self.uptimeSeconds = uptimeSeconds
        self.activeMatterNodes = activeMatterNodes
        self.activeBLEGateways = activeBLEGateways
        self.activeDevices = activeDevices
    }

    enum CodingKeys: String, CodingKey {
        case version
        case uptimeSeconds
        case activeMatterNodes
        case activeBleGateways
        case activeBLEGateways
        case activeDevices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.uptimeSeconds = try container.decode(UInt64.self, forKey: .uptimeSeconds)
        self.activeMatterNodes = try container.decode(Int.self, forKey: .activeMatterNodes)
        if let gways = try container.decodeIfPresent(Int.self, forKey: .activeBleGateways) {
            self.activeBLEGateways = gways
        } else if let gways = try container.decodeIfPresent(Int.self, forKey: .activeBLEGateways) {
            self.activeBLEGateways = gways
        } else {
            self.activeBLEGateways = 0
        }
        self.activeDevices = try container.decodeIfPresent(Int.self, forKey: .activeDevices)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try container.encode(activeMatterNodes, forKey: .activeMatterNodes)
        try container.encode(activeBLEGateways, forKey: .activeBleGateways)
        try container.encodeIfPresent(activeDevices, forKey: .activeDevices)
    }
}

public struct MobileBleScanItem: Codable, Sendable {
    public let id: String
    public let name: String?
    public let rssi: Int16?
    public let manufacturerDataHex: String?
    public let family: String?
    public let assignedRoom: String?
    public let scoutName: String?
    public let bthomeVersion: UInt8?
    public let battery: UInt8?
    public let temperatureC: Float?
    public let humidityPct: Float?
    public let illuminanceLux: Float?
    public let pressureHpa: Float?
    public let contactOpen: Bool?
    public let motionDetected: Bool?
    public let buttonEvent: String?

    public init(
        id: String,
        name: String? = nil,
        rssi: Int16? = nil,
        manufacturerDataHex: String? = nil,
        family: String? = nil,
        assignedRoom: String? = nil,
        scoutName: String? = nil,
        bthomeVersion: UInt8? = nil,
        battery: UInt8? = nil,
        temperatureC: Float? = nil,
        humidityPct: Float? = nil,
        illuminanceLux: Float? = nil,
        pressureHpa: Float? = nil,
        contactOpen: Bool? = nil,
        motionDetected: Bool? = nil,
        buttonEvent: String? = nil
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.manufacturerDataHex = manufacturerDataHex
        self.family = family
        self.assignedRoom = assignedRoom
        self.scoutName = scoutName
        self.bthomeVersion = bthomeVersion
        self.battery = battery
        self.temperatureC = temperatureC
        self.humidityPct = humidityPct
        self.illuminanceLux = illuminanceLux
        self.pressureHpa = pressureHpa
        self.contactOpen = contactOpen
        self.motionDetected = motionDetected
        self.buttonEvent = buttonEvent
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case rssi
        case manufacturerDataHex = "manufacturer_data_hex"
        case family
        case assignedRoom = "assigned_room"
        case scoutName = "scout_name"
        case bthomeVersion = "bthome_version"
        case battery
        case temperatureC = "temperature_c"
        case humidityPct = "humidity_pct"
        case illuminanceLux = "illuminance_lux"
        case pressureHpa = "pressure_hpa"
        case contactOpen = "contact_open"
        case motionDetected = "motion_detected"
        case buttonEvent = "button_event"
    }
}

public protocol HomeNodeServerClientProtocol: Sendable {
    func checkHealth(config: ServerConfig) async throws -> ServerStatus
    func sendMobileBleScan(config: ServerConfig, items: [MobileBleScanItem]) async throws -> (ingested: Int, ignored: Int)
    func claimDevice(config: ServerConfig, id: String, name: String?, room: String?, family: String?) async throws -> Bool
    func fetchRooms(config: ServerConfig) async throws -> [ServerRoom]
    func fetchIgnoredDevices(config: ServerConfig) async throws -> [IgnoredDeviceRecord]
    func ignoreDeviceOnServer(config: ServerConfig, id: String, name: String?, reason: String?) async throws -> Bool
    func unignoreDeviceOnServer(config: ServerConfig, id: String) async throws -> Bool
}

public final class MockHomeNodeServerClient: HomeNodeServerClientProtocol, @unchecked Sendable {
    public var shouldSucceed: Bool = true

    public init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }

    public func checkHealth(config: ServerConfig) async throws -> ServerStatus {
        try await Task.sleep(nanoseconds: 200_000_000)
        if !shouldSucceed {
            throw URLError(.cannotConnectToHost)
        }
        return ServerStatus(
            version: "0.1.0-mock",
            uptimeSeconds: 8400,
            activeMatterNodes: 4,
            activeBLEGateways: 3,
            activeDevices: 42
        )
    }

    public func sendMobileBleScan(config: ServerConfig, items: [MobileBleScanItem]) async throws -> (ingested: Int, ignored: Int) {
        try await Task.sleep(nanoseconds: 300_000_000)
        if !shouldSucceed {
            throw URLError(.cannotConnectToHost)
        }
        return (ingested: items.count, ignored: 0)
    }

    public func claimDevice(config: ServerConfig, id: String, name: String?, room: String?, family: String?) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        return true
    }

    public func fetchRooms(config: ServerConfig) async throws -> [ServerRoom] {
        return [
            ServerRoom(id: "wohnzimmer", name: "Wohnzimmer", floor: "Erdgeschoss", icon: "🛋️"),
            ServerRoom(id: "schlafzimmer", name: "Schlafzimmer", floor: "Obergeschoss", icon: "🛏️"),
            ServerRoom(id: "kueche", name: "Küche", floor: "Erdgeschoss", icon: "🍳"),
            ServerRoom(id: "bad-og", name: "Bad OG", floor: "Obergeschoss", icon: "🛁"),
            ServerRoom(id: "buero", name: "Büro", floor: "Obergeschoss", icon: "💼")
        ]
    }

    public func fetchIgnoredDevices(config: ServerConfig) async throws -> [IgnoredDeviceRecord] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return [
            IgnoredDeviceRecord(id: "E4:5F:01:23:45:67", name: "Neighbor BLU H&T", reason: "Nachbargerät")
        ]
    }

    public func ignoreDeviceOnServer(config: ServerConfig, id: String, name: String?, reason: String?) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        return true
    }

    public func unignoreDeviceOnServer(config: ServerConfig, id: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        return true
    }
}

public final class LiveHomeNodeServerClient: HomeNodeServerClientProtocol {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func checkHealth(config: ServerConfig) async throws -> ServerStatus {
        guard let baseURL = config.baseURL else {
            throw URLError(.badURL)
        }
        let healthURL = baseURL.appendingPathComponent("api/v1/health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 4.0

        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ServerStatus.self, from: data)
    }

    public func sendMobileBleScan(config: ServerConfig, items: [MobileBleScanItem]) async throws -> (ingested: Int, ignored: Int) {
        guard let baseURL = config.baseURL else { throw URLError(.badURL) }
        guard !items.isEmpty else { return (0, 0) }

        let url = baseURL.appendingPathComponent("api/v1/mobile/ble")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(items)

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ingested = dict["ingested"] as? Int {
            let ignored = dict["ignored"] as? Int ?? 0
            return (ingested, ignored)
        }
        return (items.count, 0)
    }

    public func claimDevice(config: ServerConfig, id: String, name: String?, room: String?, family: String?) async throws -> Bool {
        guard let baseURL = config.baseURL else { throw URLError(.badURL) }
        let syncURL = baseURL.appendingPathComponent("api/v1/devices/claim")
        var request = URLRequest(url: syncURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "id": id,
            "name": name ?? "",
            "family": family ?? "",
            "assigned_room": room ?? ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            return false
        }
        return true
    }

    public func fetchRooms(config: ServerConfig) async throws -> [ServerRoom] {
        guard let baseURL = config.baseURL else { throw URLError(.badURL) }
        let url = baseURL.appendingPathComponent("api/rooms")
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([ServerRoom].self, from: data)
    }

    public func fetchIgnoredDevices(config: ServerConfig) async throws -> [IgnoredDeviceRecord] {
        guard let baseURL = config.baseURL else { throw URLError(.badURL) }
        let url = baseURL.appendingPathComponent("api/ignored-devices")
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([IgnoredDeviceRecord].self, from: data)
    }

    public func ignoreDeviceOnServer(config: ServerConfig, id: String, name: String?, reason: String?) async throws -> Bool {
        guard let baseURL = config.baseURL else { throw URLError(.badURL) }
        let escapedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = baseURL.appendingPathComponent("api/devices/\(escapedId)/ignore")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "name": name ?? "",
            "reason": reason ?? "Nachbargerät"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            return false
        }
        return true
    }

    public func unignoreDeviceOnServer(config: ServerConfig, id: String) async throws -> Bool {
        guard let baseURL = config.baseURL else { throw URLError(.badURL) }
        let escapedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = baseURL.appendingPathComponent("api/devices/\(escapedId)/unignore")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4.0
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            return false
        }
        return true
    }
}
