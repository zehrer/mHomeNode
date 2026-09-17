import SwiftUI

public struct LightDeviceCard: View {
    public let device: DiscoveredDevice
    public let serverRoom: ServerRoom?
    public var onSelect: (() -> Void)?

    public init(
        device: DiscoveredDevice,
        serverRoom: ServerRoom?,
        onSelect: (() -> Void)? = nil
    ) {
        self.device = device
        self.serverRoom = serverRoom
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            onSelect?()
        } label: {
            HStack(spacing: 14) {
                // Light bulb icon with subtle background
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(device.isCurrentlyActive ? 0.18 : 0.08))
                        .frame(width: 44, height: 44)

                    Image(systemName: "lightbulb.led.fill")
                        .font(.title3)
                        .foregroundColor(device.isCurrentlyActive ? .orange : .secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(serverRoom?.icon ?? "💡")
                            .font(.caption2)

                        Text(device.assignedRoom ?? "Not Assigned")
                            .font(.caption)
                            .foregroundColor(device.assignedRoom != nil ? .secondary : .orange)

                        if let floor = serverRoom?.floor, !floor.isEmpty {
                            Text("• \(floor)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(device.family.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Signal and activity indicator
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(device.isCurrentlyActive ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)

                        Text(device.isCurrentlyActive ? "Active" : "Idle")
                            .font(.caption2.bold())
                            .foregroundColor(device.isCurrentlyActive ? .green : .secondary)
                    }

                    HStack(spacing: 4) {
                        Text("\(device.rssi) dBm")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        SignalStrengthView(rssi: device.rssi, bars: device.signalBars)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
