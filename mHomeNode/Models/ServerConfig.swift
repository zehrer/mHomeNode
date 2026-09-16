import Foundation

public struct ServerConfig: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public var useTLS: Bool
    public var apiKey: String?
    public var isAutoSyncEnabled: Bool

    public init(
        host: String = "homenode.local",
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
}

public enum ServerConnectionStatus: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Connection Error"
}
