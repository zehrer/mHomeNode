import Foundation
import OSLog

public struct ShellyLANRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public var hostName: String
    public var ipAddresses: [String]
    public var macSuffix: String?

    public init(
        id: String,
        name: String,
        hostName: String = "",
        ipAddresses: [String] = [],
        macSuffix: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostName = hostName
        self.ipAddresses = ipAddresses
        self.macSuffix = macSuffix
    }

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
public final class ShellyLANDiscoveryService: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    public static let shared = ShellyLANDiscoveryService()

    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "ShellyLANDiscovery")
    private var httpBrowser: NetServiceBrowser?
    private var shellyBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []

    public var isSearching: Bool = false
    public var discoveredShellys: [ShellyLANRecord] = []

    // Callback when a new Shelly LAN endpoint is resolved
    public var onShellyResolved: (@MainActor (ShellyLANRecord) -> Void)?

    public override init() {
        super.init()
    }

    public func startBrowsing() {
        stopBrowsing()

        isSearching = true
        logger.info("Starting Bonjour discovery for Shelly devices (_http._tcp and _shelly._tcp)...")

        let b1 = NetServiceBrowser()
        b1.delegate = self
        self.httpBrowser = b1
        b1.searchForServices(ofType: "_http._tcp.", inDomain: "local.")

        let b2 = NetServiceBrowser()
        b2.delegate = self
        self.shellyBrowser = b2
        b2.searchForServices(ofType: "_shelly._tcp.", inDomain: "local.")
    }

    public func stopBrowsing() {
        httpBrowser?.stop()
        httpBrowser = nil
        shellyBrowser?.stop()
        shellyBrowser = nil
        for s in resolvingServices {
            s.stop()
        }
        resolvingServices.removeAll()
        isSearching = false
    }

    /// Extracts the hex MAC identifier from a Shelly mDNS name (e.g. "shellyplusplugs-a0a3b3xxxxxx" -> "a0a3b3xxxxxx")
    private func extractMacSuffix(from name: String) -> String? {
        let lower = name.lowercased()
        guard lower.contains("shelly") else { return nil }

        // Look for trailing hex block after hyphen or space
        let parts = lower.components(separatedBy: CharacterSet(charactersIn: "-_ "))
        if let last = parts.last, last.count >= 6, last.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil {
            return last.uppercased()
        }
        return nil
    }

    /// Tries to find a resolved LAN host for a given device by matching MAC address, name, or explicit ID
    public func lookupHost(macAddress: String?, name: String?) -> String? {
        // 1. Direct match by normalized MAC address (last 6 or full 12 chars)
        if let mac = macAddress {
            let cleanMac = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
            for record in discoveredShellys {
                if let suffix = record.macSuffix?.uppercased(), !suffix.isEmpty {
                    if cleanMac.hasSuffix(suffix) || suffix.hasSuffix(cleanMac) {
                        return record.preferredHost
                    }
                }
            }
        }

        // 2. Match by device name suffix
        if let devName = name?.lowercased() {
            for record in discoveredShellys {
                let recName = record.name.lowercased()
                if recName == devName || devName.contains(recName) || recName.contains(devName) {
                    return record.preferredHost
                }
            }
        }

        return nil
    }

    // MARK: - NetServiceBrowserDelegate

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let nameLower = service.name.lowercased()
        // Only resolve services that belong to Shelly devices
        guard nameLower.contains("shelly") else { return }

        logger.info("Discovered potential Shelly on LAN: \(service.name)")
        let id = "\(service.name).\(service.type)\(service.domain)"

        if !discoveredShellys.contains(where: { $0.id == id }) {
            let macSuffix = extractMacSuffix(from: service.name)
            let record = ShellyLANRecord(
                id: id,
                name: service.name,
                macSuffix: macSuffix
            )
            discoveredShellys.append(record)
        }

        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 4.0)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = "\(service.name).\(service.type)\(service.domain)"
        discoveredShellys.removeAll { $0.id == id }
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let host = sender.hostName ?? ""
        var ipList: [String] = []

        if let addresses = sender.addresses {
            for addrData in addresses {
                addrData.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return }
                    let sockaddrPtr = baseAddress.assumingMemoryBound(to: sockaddr.self)
                    if sockaddrPtr.pointee.sa_family == UInt8(AF_INET) {
                        var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let sock4Ptr = baseAddress.assumingMemoryBound(to: sockaddr_in.self)
                        var inAddr = sock4Ptr.pointee.sin_addr
                        inet_ntop(AF_INET, &inAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                        let ip = String(cString: ipBuffer)
                        if !ip.isEmpty && !ipList.contains(ip) {
                            ipList.append(ip)
                        }
                    }
                }
            }
        }

        let id = "\(sender.name).\(sender.type)\(sender.domain)"
        if let idx = discoveredShellys.firstIndex(where: { $0.id == id }) {
            discoveredShellys[idx].hostName = host
            discoveredShellys[idx].ipAddresses = ipList
            let resolved = discoveredShellys[idx]
            logger.info("Resolved Shelly \(sender.name) -> IP: \(resolved.preferredHost)")
            onShellyResolved?(resolved)
        }

        resolvingServices.removeAll { $0 == sender }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logger.debug("Could not resolve address for Shelly \(sender.name)")
        resolvingServices.removeAll { $0 == sender }
    }
}
