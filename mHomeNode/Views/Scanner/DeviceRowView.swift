import SwiftUI

public struct DeviceRowView: View {
    public let device: DiscoveredDevice

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Family Icon
                Image(systemName: familyIcon)
                    .font(.title3)
                    .foregroundStyle(familyColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if let room = device.assignedRoom, !room.isEmpty {
                        Text("📍 " + room)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(device.family.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Signal indicator
                VStack(alignment: .trailing, spacing: 2) {
                    SignalStrengthView(rssi: device.rssi, bars: device.signalBars)
                    Text("\(device.rssi) dBm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Sensor Readings Badges (if BTHome data decoded)
            if let btHome = device.btHomeData {
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
