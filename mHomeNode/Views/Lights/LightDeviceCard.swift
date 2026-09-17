import SwiftUI

public struct LightDeviceCard: View {
    public let device: DiscoveredDevice
    public let serverRoom: ServerRoom?
    public let controller: GoveeLightController?
    public var onSelect: (() -> Void)?

    public init(
        device: DiscoveredDevice,
        serverRoom: ServerRoom? = nil,
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

    private var currentBrightness: Int {
        controller?.getBrightness(for: device.id) ?? 100
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Main card body (tappable to view details)
            Button {
                onSelect?()
            } label: {
                HStack(spacing: 14) {
                    // Light bulb visual indicator
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLightOn ? Color.yellow.opacity(0.22) : Color(.tertiarySystemFill))
                            .frame(width: 48, height: 48)

                        Image(systemName: isLightOn ? "lightbulb.fill" : "lightbulb")
                            .font(.title2)
                            .foregroundColor(isLightOn ? .yellow : .secondary)
                            .shadow(color: isLightOn ? Color.yellow.opacity(0.6) : Color.clear, radius: 8)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let err = controller?.lastError[device.id] {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        } else {
                            HStack(spacing: 6) {
                                if isLightOn {
                                    Text("On")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.yellow)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(currentBrightness)%")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Off")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)

            // Direct Quick Action Power Button
            if let ctrl = controller {
                Button {
                    ctrl.togglePower(for: device.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isLightOn ? Color.yellow.opacity(0.2) : Color(.tertiarySystemFill))
                            .frame(width: 46, height: 46)

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
