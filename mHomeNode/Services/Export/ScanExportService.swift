import Foundation

/// Service for exporting saved BLE scan sessions to CSV, JSON, and human-readable text reports
public final class ScanExportService: Sendable {
    public static let shared = ScanExportService()

    public init() {}

    // MARK: - CSV Export

    /// Standard CSV header row for scan sessions
    public static let csvHeader: String = "Session_ID,Session_Title,Timestamp,Latitude,Longitude,Accuracy_m,Place_Name,Notes,Device_ID,Device_Name,Custom_Name,Family,MAC_Address,RSSI_dBm,Is_Active,Battery_pct,Temperature_C,Humidity_pct,Pressure_hPa,Illuminance_lux,Manufacturer_Data_Hex,Service_UUIDs,Service_Data"

    /// Exports a single session's devices to CSV formatted string
    public func exportCSV(session: SavedScanSession) -> String {
        var rows: [String] = [Self.csvHeader]
        for device in session.devices {
            rows.append(csvRow(for: device, in: session))
        }
        return rows.joined(separator: "\n")
    }

    /// Exports multiple sessions to a consolidated CSV formatted string
    public func exportAllCSV(sessions: [SavedScanSession]) -> String {
        var rows: [String] = [Self.csvHeader]
        for session in sessions {
            for device in session.devices {
                rows.append(csvRow(for: device, in: session))
            }
        }
        return rows.joined(separator: "\n")
    }

    private func csvRow(for device: DiscoveredDevice, in session: SavedScanSession) -> String {
        let sessionId = escapeCSV(session.id.uuidString)
        let sessionTitle = escapeCSV(session.title)
        let timestamp = ISO8601DateFormatter().string(from: session.timestamp)
        let lat = session.location.map { String(format: "%.6f", $0.latitude) } ?? ""
        let lon = session.location.map { String(format: "%.6f", $0.longitude) } ?? ""
        let acc = session.location?.horizontalAccuracy.map { String(format: "%.1f", $0) } ?? ""
        let place = escapeCSV(session.location?.placeName ?? "")
        let notes = escapeCSV(session.note ?? "")

        let devId = escapeCSV(device.id.uuidString)
        let devName = escapeCSV(device.name)
        let customName = escapeCSV(device.customName ?? "")
        let family = escapeCSV(device.family.rawValue)
        let mac = escapeCSV(device.macAddress ?? "")
        let rssi = "\(device.rssi)"
        let isActive = device.isCurrentlyActive ? "true" : "false"

        let battery = device.btHomeData?.battery.map { "\($0)" } ?? ""
        let temp = device.btHomeData?.temperature.map { String(format: "%.2f", $0) } ?? ""
        let hum = device.btHomeData?.humidity.map { String(format: "%.1f", $0) } ?? ""
        let press = device.btHomeData?.pressure.map { String(format: "%.1f", $0) } ?? ""
        let lux = device.btHomeData?.illuminance.map { String(format: "%.0f", $0) } ?? ""

        let mfgHex = escapeCSV(device.manufacturerDataHex ?? "")
        let svcs = escapeCSV(device.serviceUUIDs.joined(separator: ";"))
        let sdataStr = escapeCSV(device.serviceDataHex?.map { "\($0.key)=\($0.value)" }.joined(separator: ";") ?? "")

        return [
            sessionId, sessionTitle, timestamp, lat, lon, acc, place, notes,
            devId, devName, customName, family, mac, rssi, isActive,
            battery, temp, hum, press, lux,
            mfgHex, svcs, sdataStr
        ].joined(separator: ",")
    }

    private func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }

    // MARK: - JSON Export

    /// Exports a single session to formatted JSON Data
    public func exportJSONData(session: SavedScanSession) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(session)
    }

    /// Exports all sessions to formatted JSON Data
    public func exportAllJSONData(sessions: [SavedScanSession]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(sessions)
    }

    // MARK: - Text Summary Export

    /// Generates a comprehensive summary report of all sessions
    public func exportAllSummary(sessions: [SavedScanSession]) -> String {
        var lines: [String] = []
        lines.append("mHomeNode BLE Scan Archive Summary")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Total Sessions: \(sessions.count)")
        let totalDevices = sessions.reduce(0) { $0 + $1.deviceCount }
        lines.append("Total Devices Logged: \(totalDevices)")
        lines.append(String(repeating: "=", count: 64))
        lines.append("")

        for session in sessions {
            lines.append(session.exportSummary())
            lines.append("")
            lines.append(String(repeating: "-", count: 64))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
