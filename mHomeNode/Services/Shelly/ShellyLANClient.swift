import Foundation
import OSLog

public struct ShellySwitchStatus: Sendable, Equatable {
    public let isOn: Bool
    public let activePowerW: Double?
    public let voltageV: Double?
    public let currentA: Double?
    public let totalEnergyKWh: Double?

    public init(
        isOn: Bool,
        activePowerW: Double? = nil,
        voltageV: Double? = nil,
        currentA: Double? = nil,
        totalEnergyKWh: Double? = nil
    ) {
        self.isOn = isOn
        self.activePowerW = activePowerW
        self.voltageV = voltageV
        self.currentA = currentA
        self.totalEnergyKWh = totalEnergyKWh
    }
}

public protocol ShellyLANClientProtocol: Sendable {
    func setPower(host: String, isOn: Bool, channel: Int) async throws -> Bool
    func getStatus(host: String, channel: Int) async throws -> ShellySwitchStatus
    func probe(host: String) async -> Bool
}

public final class ShellyLANClient: ShellyLANClientProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "ShellyLANClient")
    private let session: URLSession
    public var timeoutInterval: TimeInterval

    public init(session: URLSession? = nil, timeoutInterval: TimeInterval = 2.5) {
        if let s = session {
            self.session = s
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = timeoutInterval
            config.timeoutIntervalForResource = timeoutInterval
            self.session = URLSession(configuration: config)
        }
        self.timeoutInterval = timeoutInterval
    }

    private func cleanHost(_ host: String) -> String {
        var clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("http://") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("https://") {
            clean = String(clean.dropFirst(8))
        }
        if clean.hasSuffix("/") {
            clean = String(clean.dropLast())
        }
        return clean
    }

    /// Sets the power state of a Shelly switch over LAN (tries Gen2/Gen3 RPC first, then falls back to Gen1)
    public func setPower(host: String, isOn: Bool, channel: Int = 0) async throws -> Bool {
        let cleaned = cleanHost(host)
        guard !cleaned.isEmpty else {
            throw URLError(.badURL)
        }

        // Try Gen2/Gen3 RPC: POST http://<host>/rpc
        if let rpcURL = URL(string: "http://\(cleaned)/rpc") {
            var request = URLRequest(url: rpcURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = timeoutInterval

            let payload: [String: Any] = [
                "id": 1,
                "src": "mHomeNode",
                "method": "Switch.Set",
                "params": [
                    "id": channel,
                    "on": isOn
                ]
            ]

            if let httpBody = try? JSONSerialization.data(withJSONObject: payload) {
                request.httpBody = httpBody
                do {
                    let (data, response) = try await session.data(for: request)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           json["error"] == nil {
                            logger.info("Successfully set Shelly power via Gen2 RPC to \(isOn ? "ON" : "OFF") on \(cleaned)")
                            return true
                        }
                    }
                } catch {
                    logger.debug("Gen2 RPC POST failed on \(cleaned), attempting GET fallback: \(error.localizedDescription)")
                }
            }

            // Fallback Gen2 GET: http://<host>/rpc/Switch.Set?id=0&on=true
            if let getRPCURL = URL(string: "http://\(cleaned)/rpc/Switch.Set?id=\(channel)&on=\(isOn)") {
                var getReq = URLRequest(url: getRPCURL)
                getReq.timeoutInterval = timeoutInterval
                do {
                    let (data, response) = try await session.data(for: getReq)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           json["error"] == nil {
                            logger.info("Successfully set Shelly power via Gen2 GET RPC to \(isOn ? "ON" : "OFF") on \(cleaned)")
                            return true
                        }
                    }
                } catch {
                    logger.debug("Gen2 GET RPC failed on \(cleaned), trying Gen1: \(error.localizedDescription)")
                }
            }
        }

        // Try Gen1 API: GET http://<host>/relay/<channel>?turn=<on|off>
        if let gen1URL = URL(string: "http://\(cleaned)/relay/\(channel)?turn=\(isOn ? "on" : "off")") {
            var request = URLRequest(url: gen1URL)
            request.timeoutInterval = timeoutInterval
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let state = json["ison"] as? Bool {
                logger.info("Successfully set Shelly power via Gen1 API to \(state ? "ON" : "OFF") on \(cleaned)")
                return state == isOn
            }
            return true
        }

        throw URLError(.cannotConnectToHost)
    }

    /// Queries live status (output on/off, power in Watts, energy in kWh) from the Shelly device
    public func getStatus(host: String, channel: Int = 0) async throws -> ShellySwitchStatus {
        let cleaned = cleanHost(host)
        guard !cleaned.isEmpty else { throw URLError(.badURL) }

        // 1. Try Gen2/Gen3: GET http://<host>/rpc/Switch.GetStatus?id=<channel>
        if let gen2URL = URL(string: "http://\(cleaned)/rpc/Switch.GetStatus?id=\(channel)") {
            var request = URLRequest(url: gen2URL)
            request.timeoutInterval = timeoutInterval
            if let (data, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let isOn = (json["output"] as? Bool) ?? false
                let power = json["apower"] as? Double
                let voltage = json["voltage"] as? Double
                let current = json["current"] as? Double

                var totalKWh: Double? = nil
                if let aenergy = json["aenergy"] as? [String: Any],
                   let totalMWh = aenergy["total"] as? Double {
                    // Shelly reports aenergy.total in Watt-minutes (mWh)
                    totalKWh = totalMWh / 60000.0
                }

                return ShellySwitchStatus(
                    isOn: isOn,
                    activePowerW: power,
                    voltageV: voltage,
                    currentA: current,
                    totalEnergyKWh: totalKWh
                )
            }
        }

        // 2. Try Gen1: GET http://<host>/status
        if let gen1URL = URL(string: "http://\(cleaned)/status") {
            var request = URLRequest(url: gen1URL)
            request.timeoutInterval = timeoutInterval
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.badServerResponse)
            }

            var isOn = false
            var power: Double? = nil
            var totalKWh: Double? = nil

            if let relays = json["relays"] as? [[String: Any]], relays.indices.contains(channel) {
                isOn = (relays[channel]["ison"] as? Bool) ?? false
            }
            if let meters = json["meters"] as? [[String: Any]], meters.indices.contains(channel) {
                power = meters[channel]["power"] as? Double
                if let totalWm = meters[channel]["total"] as? Double {
                    totalKWh = totalWm / 60000.0
                }
            }

            return ShellySwitchStatus(
                isOn: isOn,
                activePowerW: power,
                voltageV: nil,
                currentA: nil,
                totalEnergyKWh: totalKWh
            )
        }

        throw URLError(.cannotConnectToHost)
    }

    /// Quickly probes if a Shelly device is reachable on LAN
    public func probe(host: String) async -> Bool {
        let cleaned = cleanHost(host)
        guard !cleaned.isEmpty else { return false }

        // Test Shelly info endpoint
        if let url = URL(string: "http://\(cleaned)/shelly") {
            var req = URLRequest(url: url)
            req.timeoutInterval = min(timeoutInterval, 1.5)
            if let (_, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
        }

        // Test Gen2 RPC info endpoint
        if let url = URL(string: "http://\(cleaned)/rpc/Shelly.GetDeviceInfo") {
            var req = URLRequest(url: url)
            req.timeoutInterval = min(timeoutInterval, 1.5)
            if let (_, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
        }

        return false
    }
}

public final class MockShellyLANClient: ShellyLANClientProtocol, @unchecked Sendable {
    public var shouldSucceed: Bool = true
    public var lastSetHost: String?
    public var lastSetPower: Bool?
    public var mockStatus: ShellySwitchStatus = ShellySwitchStatus(isOn: true, activePowerW: 15.0)

    public init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }

    public func setPower(host: String, isOn: Bool, channel: Int = 0) async throws -> Bool {
        lastSetHost = host
        lastSetPower = isOn
        if !shouldSucceed {
            throw URLError(.cannotConnectToHost)
        }
        return true
    }

    public func getStatus(host: String, channel: Int = 0) async throws -> ShellySwitchStatus {
        if !shouldSucceed {
            throw URLError(.cannotConnectToHost)
        }
        return mockStatus
    }

    public func probe(host: String) async -> Bool {
        return shouldSucceed
    }
}
