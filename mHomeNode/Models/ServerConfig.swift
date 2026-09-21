import Foundation

public struct ServerConfig: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public var useTLS: Bool
    public var apiKey: String?
    public var isAutoSyncEnabled: Bool

    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        useTLS: Bool = false,
        apiKey: String? = nil,
        isAutoSyncEnabled: Bool = false
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.apiKey = apiKey
        self.isAutoSyncEnabled = isAutoSyncEnabled
    }

    public var baseURL: URL? {
        let scheme = useTLS ? "https" : "http"
        return URL(string: "\(scheme)://\(host):\(port)")
    }

    /// Whether the host is the unconfigured default or loopback address
    public var isLocalhost: Bool {
        host == "127.0.0.1" || host == "localhost" || host.isEmpty
    }

    private static let userDefaultsKey = "homenode_saved_server_config"

    public static func load() -> ServerConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data) else {
            return ServerConfig()
        }
        return config
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ServerConfig.userDefaultsKey)
        }
    }
}

public enum ServerConnectionStatus: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Connection Error"
}
