import Foundation
import OSLog

public struct DiscoveredHomeNodeServer: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public var hostName: String
    public var port: Int
    public var ipAddresses: [String]
    public var isResolved: Bool

    public init(
        id: String,
        name: String,
        hostName: String = "",
        port: Int = 8080,
        ipAddresses: [String] = [],
        isResolved: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostName = hostName
        self.port = port
        self.ipAddresses = ipAddresses
        self.isResolved = isResolved
    }

    /// Best host to connect to (prefers direct IPv4 address if available, otherwise Bonjour hostname)
    public var preferredHost: String {
        if let ipv4 = ipAddresses.first(where: { !$0.contains(":") && !$0.starts(with: "127.") }) {
            return ipv4
        }
        let clean = hostName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return clean.isEmpty ? "127.0.0.1" : clean
    }
}

@Observable
@MainActor
public final class HomeNodeDiscoveryService: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    public static let shared = HomeNodeDiscoveryService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "Discovery")
    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []

    public var isSearching: Bool = false
    public var discoveredServers: [DiscoveredHomeNodeServer] = []
    public var activeServer: DiscoveredHomeNodeServer?
    public var discoveryError: String?

    public var onServerDiscovered: (@MainActor (DiscoveredHomeNodeServer) -> Void)?

    public override init() {
        super.init()
    }

    public func startBrowsing() {
        stopBrowsing()

        let b = NetServiceBrowser()
        b.delegate = self
        self.browser = b
        self.isSearching = true
        self.discoveryError = nil
        logger.info("Starting Bonjour discovery for _homenode._tcp on local domain...")
        b.searchForServices(ofType: "_homenode._tcp.", inDomain: "local.")
    }

    public func stopBrowsing() {
        browser?.stop()
        browser = nil
        for s in resolvingServices {
            s.stop()
        }
        resolvingServices.removeAll()
        isSearching = false
    }

    // MARK: - NetServiceBrowserDelegate

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logger.info("Found Bonjour service: \(service.name)")

        let serverId = "\(service.name).\(service.type)\(service.domain)"
        if !discoveredServers.contains(where: { $0.id == serverId }) {
            let record = DiscoveredHomeNodeServer(
                id: serverId,
                name: service.name,
                isResolved: false
            )
            discoveredServers.append(record)
        }

        // Start resolving address and port
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5.0)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logger.info("Removed Bonjour service: \(service.name)")
        let serverId = "\(service.name).\(service.type)\(service.domain)"
        discoveredServers.removeAll(where: { $0.id == serverId })
        if activeServer?.id == serverId {
            activeServer = nil
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        isSearching = false
        discoveryError = "Bonjour search failed: \(errorDict)"
        logger.error("Bonjour search error: \(errorDict)")
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let serverId = "\(sender.name).\(sender.type)\(sender.domain)"
        let rawHost = sender.hostName ?? ""
        let cleanHost = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let port = sender.port

        var ips: [String] = []
        if let addresses = sender.addresses {
            for addrData in addresses {
                addrData.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return }
                    let sockaddrPtr = base.assumingMemoryBound(to: sockaddr.self)
                    if sockaddrPtr.pointee.sa_family == UInt8(AF_INET) {
                        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sockaddrPtr, socklen_t(addrData.count), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = String(cString: buffer)
                            if !ips.contains(ip) {
                                ips.append(ip)
                            }
                        }
                    }
                }
            }
        }

        logger.info("Resolved HomeNode Server '\(sender.name)': host=\(cleanHost), port=\(port), IPs=\(ips)")

        let resolved = DiscoveredHomeNodeServer(
            id: serverId,
            name: sender.name,
            hostName: cleanHost,
            port: port > 0 ? port : 8080,
            ipAddresses: ips,
            isResolved: true
        )

        if let idx = discoveredServers.firstIndex(where: { $0.id == serverId }) {
            discoveredServers[idx] = resolved
        } else {
            discoveredServers.append(resolved)
        }

        if activeServer == nil {
            activeServer = resolved
            onServerDiscovered?(resolved)
        }

        resolvingServices.removeAll(where: { $0 == sender })
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        logger.warning("Failed to resolve NetService '\(sender.name)': \(errorDict)")
        resolvingServices.removeAll(where: { $0 == sender })
    }
}
