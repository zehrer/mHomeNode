import SwiftUI

public struct RoomClimateCard: View {
    public let roomName: String
    public let serverRoom: ServerRoom?
    public let devices: [DiscoveredDevice]
    public var onSelectDevice: ((DiscoveredDevice) -> Void)?

    public init(
        roomName: String,
        serverRoom: ServerRoom?,
        devices: [DiscoveredDevice],
        onSelectDevice: ((DiscoveredDevice) -> Void)? = nil
    ) {
        self.roomName = roomName
        self.serverRoom = serverRoom
        self.devices = devices
        self.onSelectDevice = onSelectDevice
    }

    private var activeDevices: [DiscoveredDevice] {
        devices.filter { !$0.isSignalLost }
    }

    private var averageTemperature: Double? {
        let temps = activeDevices.compactMap { $0.btHomeData?.temperature }
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    private var averageHumidity: Double? {
        let hums = activeDevices.compactMap { $0.btHomeData?.humidity }
        guard !hums.isEmpty else { return nil }
        return hums.reduce(0, +) / Double(hums.count)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Room Header
            HStack(alignment: .center, spacing: 10) {
                Text(serverRoom?.icon ?? (roomName == "Not Assigned" || roomName == "Nicht zugeordnet" ? "❓" : "🏠"))
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(roomName == "Nicht zugeordnet" ? "Not Assigned" : roomName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let floor = serverRoom?.floor, !floor.isEmpty {
                        Text(floor)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if roomName == "Not Assigned" || roomName == "Nicht zugeordnet" {
                        Text("Tap to assign room")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                // Sensor count pill
                Text("\(devices.count) Sensor\(devices.count == 1 ? "" : "s")")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(12)
            }

            // Metric Badges (Primary display for room)
            HStack(spacing: 12) {
                if let temp = averageTemperature {
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.medium")
                            .font(.title3)
                            .foregroundColor(temperatureColor(temp))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%.1f°C", temp))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundColor(.primary)
                            Text(activeDevices.count > 1 ? "Average" : "Temperature")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(temperatureColor(temp).opacity(0.12))
                    .cornerRadius(10)
                }

                if let hum = averageHumidity {
                    HStack(spacing: 8) {
                        Image(systemName: "humidity.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%.0f%%", hum))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundColor(.primary)
                            Text(activeDevices.count > 1 ? "Average" : "Humidity")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(10)
                }

                if averageTemperature == nil && averageHumidity == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("—")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundColor(.secondary)
                            Text("No Signal")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(10)
                }
            }

            // Devices list inside this room
            VStack(spacing: 8) {
                ForEach(devices) { device in
                    Button {
                        onSelectDevice?(device)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(device.isSignalLost ? Color.gray.opacity(0.4) : (device.isCurrentlyActive ? Color.green : Color.orange))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(device.isSignalLost ? .secondary : .primary)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(device.family.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    if device.isSignalLost {
                                        HStack(spacing: 2) {
                                            Image(systemName: "wifi.slash")
                                            Text("No signal")
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    } else {
                                        HStack(spacing: 2) {
                                            Image(systemName: "clock")
                                            Text(device.measurementAgeText)
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }

                                    if let battery = device.btHomeData?.battery {
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 2) {
                                            Image(systemName: batteryIcon(battery))
                                            Text("\(battery)%")
                                        }
                                        .font(.caption2)
                                        .foregroundColor(batteryColor(battery))
                                    }
                                }
                            }

                            Spacer()

                            // Individual metrics if multiple devices
                            if devices.count > 1 {
                                if device.isSignalLost {
                                    Text("—")
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundColor(.secondary)
                                } else {
                                    HStack(spacing: 8) {
                                        if let t = device.btHomeData?.temperature {
                                            Text(String(format: "%.1f°C", t))
                                                .font(.caption.bold().monospacedDigit())
                                                .foregroundColor(.primary)
                                        }
                                        if let h = device.btHomeData?.humidity {
                                            Text(String(format: "%.0f%%", h))
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if device.id != devices.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func temperatureColor(_ temp: Double) -> Color {
        if temp < 18.0 {
            return .blue
        } else if temp <= 23.5 {
            return .green
        } else if temp <= 26.0 {
            return .orange
        } else {
            return .red
        }
    }

    private func batteryIcon(_ level: UInt8) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 10..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ level: UInt8) -> Color {
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .secondary
    }
}
