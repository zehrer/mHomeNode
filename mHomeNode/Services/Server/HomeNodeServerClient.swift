import Foundation

public struct ServerStatus: Codable, Sendable {
    public let version: String
    public let uptimeSeconds: UInt64
    public let activeMatterNodes: Int
    public let activeBLEGateways: Int

    public init(
        version: String = "0.1.0-alpha",
        uptimeSeconds: UInt64 = 4200,
        activeMatterNodes: Int = 3,
        activeBLEGateways: Int = 2
    ) {
        self.version = version
        self.uptimeSeconds = uptimeSeconds
        self.activeMatterNodes = activeMatterNodes
        self.activeBLEGateways = activeBLEGateways
    }
}

public protocol HomeNodeServerClientProtocol: Sendable {
    func checkHealth(config: ServerConfig) async throws -> ServerStatus
    func syncDevice(config: ServerConfig, device: DiscoveredDevice) async throws -> Bool
}

public final class MockHomeNodeServerClient: HomeNodeServerClientProtocol {
    public init() {}

    public func checkHealth(config: ServerConfig) async throws -> ServerStatus {
        try await Task.sleep(nanoseconds: 600_000_000)
        return ServerStatus(
            version: "0.1.0-dev (Rust)",
            uptimeSeconds: 12450,
            activeMatterNodes: 2,
            activeBLEGateways: 1
        )
    }

    public func syncDevice(config: ServerConfig, device: DiscoveredDevice) async throws -> Bool {
        try await Task.sleep(nanoseconds: 400_000_000)
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
        request.timeoutInterval = 5.0

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

    public func syncDevice(config: ServerConfig, device: DiscoveredDevice) async throws -> Bool {
        guard let baseURL = config.baseURL else {
            throw URLError(.badURL)
        }
        let syncURL = baseURL.appendingPathComponent("api/v1/devices/claim")
        var request = URLRequest(url: syncURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "id": device.id.uuidString,
            "name": device.name,
            "family": device.family.rawValue,
            "assigned_room": device.assignedRoom ?? ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            return false
        }
        return true
    }
}
