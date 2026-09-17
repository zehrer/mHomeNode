import SwiftUI

public struct LightDeviceCard: View {
    public let device: DiscoveredDevice
    public let serverRoom: ServerRoom?
    public let controller: GoveeLightController?
    public var onSelect: (() -> Void)?

    public init(
        device: DiscoveredDevice,
        serverRoom: ServerRoom?,
        controller: GoveeLightController? = nil,
        onSelect: (() -> Void)? = nil
    ) {
        self.device = device
        self.serverRoom = serverRoom
        self.controller = controller
        self.onSelect = onSelect
    }

    private var isLightOn: Bool {
        controller?.isPowerOn(for: device.id) ?? false
    }

    private var isBusy: Bool {
        controller?.isDeviceBusy(device.id) ?? false
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Main card body (tappable to view details)
            Button {
                onSelect?()
            } label: {
                HStack(spacing: 12) {
                    // Light bulb visual indicator
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLightOn ? Color.yellow.opacity(0.22) : (device.isCurrentlyActive ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08)))
                            .frame(width: 46, height: 46)

                        Image(systemName: isLightOn ? "lightbulb.fill" : "lightbulb")
                            .font(.title3)
                            .foregroundColor(isLightOn ? .yellow : (device.isCurrentlyActive ? .orange : .secondary))
                            .shadow(color: isLightOn ? Color.yellow.opacity(0.6) : Color.clear, radius: 6)
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

                        if let err = controller?.lastError[device.id] {
                            Text(err)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // Signal & live status
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
                }
            }
            .buttonStyle(.plain)

            // Direct Quick Action Power Button
            if let ctrl = controller {
                Divider()
                    .frame(height: 36)

                Button {
                    ctrl.togglePower(for: device.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isLightOn ? Color.yellow.opacity(0.2) : Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)

                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "power")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(isLightOn ? .yellow : .secondary)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isBusy)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
