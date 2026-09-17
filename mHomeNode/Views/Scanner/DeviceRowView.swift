import SwiftUI

public struct DeviceRowView: View {
    public let device: DiscoveredDevice

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Family Icon with activity badge
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: familyIcon)
                        .font(.title3)
                        .foregroundStyle(device.isIgnored ? .gray : familyColor)
                        .frame(width: 28, height: 28)

                    Circle()
                        .fill(device.isCurrentlyActive ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(device.isIgnored ? .secondary : .primary)

                        if device.isIgnored {
                            Text("🚫 Ignoriert")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        if let mac = device.macAddress {
                            Text(mac)
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        } else {
                            Text(device.family.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let room = device.assignedRoom, !room.isEmpty {
                            Text("• 📍 " + room)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Signal indicator & activity time
                VStack(alignment: .trailing, spacing: 2) {
                    SignalStrengthView(rssi: device.rssi, bars: device.signalBars)
                    HStack(spacing: 4) {
                        Text("\(device.rssi) dBm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.5))

                        Text(relativeTimeString(for: device.lastSeen))
                            .font(.caption2)
                            .foregroundStyle(device.isCurrentlyActive ? .green : .secondary)
                    }
                }
            }

            // Sensor Readings Badges (if BTHome/Qingping data decoded)
            if let btHome = device.btHomeData, !device.isIgnored {
                HStack(spacing: 6) {
                    if let temp = btHome.temperature {
                        SensorMetricBadge(
                            icon: "thermometer.medium",
                            text: String(format: "%.1f °C", temp),
                            color: .orange
                        )
                    }
                    if let hum = btHome.humidity {
                        SensorMetricBadge(
                            icon: "humidity",
                            text: String(format: "%.0f%%", hum),
                            color: .blue
                        )
                    }
                    if let battery = btHome.battery {
                        SensorMetricBadge(
                            icon: "battery.100",
                            text: "\(battery)%",
                            color: battery < 20 ? .red : .green
                        )
                    }
                    if let press = btHome.pressure {
                        SensorMetricBadge(
                            icon: "barometer",
                            text: String(format: "%.0f hPa", press),
                            color: .purple
                        )
                    }
                    if let door = btHome.isDoorOpen {
                        SensorMetricBadge(
                            icon: door ? "door.left.hand.open" : "door.left.hand.closed",
                            text: door ? "Open" : "Closed",
                            color: door ? .orange : .green
                        )
                    }
                    if let motion = btHome.isMotionDetected, motion {
                        SensorMetricBadge(
                            icon: "figure.walk.motion",
                            text: "Motion",
                            color: .purple
                        )
                    }
                    if let button = btHome.buttonEvent {
                        SensorMetricBadge(
                            icon: "button.programmable",
                            text: button.rawValue,
                            color: .indigo
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .opacity(device.isIgnored ? 0.6 : (device.isCurrentlyActive ? 1.0 : 0.75))
    }

    private func relativeTimeString(for date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 10 {
            return "jetzt"
        } else if diff < 60 {
            return "\(diff)s"
        } else if diff < 3600 {
            return "\(diff / 60)m"
        } else {
            return "\(diff / 3600)h"
        }
    }

    private var familyIcon: String {
        switch device.family {
        case .shellyBlu: return "sensor.tag.radiowaves.forward"
        case .qingping: return "thermometer.sun"
        case .btHomeGeneric: return "dot.radiowaves.left.and.right"
        case .standardBLE: return "antenna.radiowaves.left.and.right"
        }
    }

    private var familyColor: Color {
        switch device.family {
        case .shellyBlu: return .cyan
        case .qingping: return .teal
        case .btHomeGeneric: return .blue
        case .standardBLE: return .secondary
        }
    }
}
