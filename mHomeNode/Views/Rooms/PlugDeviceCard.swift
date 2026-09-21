import SwiftUI

public struct PlugDeviceCard: View {
    public let device: DiscoveredDevice
    public let controller: ShellyPlugController
    public var onSelect: (() -> Void)?

    public init(
        device: DiscoveredDevice,
        controller: ShellyPlugController,
        onSelect: (() -> Void)? = nil
    ) {
        self.device = device
        self.controller = controller
        self.onSelect = onSelect
    }

    private var isOn: Bool {
        controller.isPowerOn(for: device.id)
    }

    private var isBusy: Bool {
        controller.isDeviceBusy(device.id)
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Main card body (tappable to view details)
            Button {
                onSelect?()
            } label: {
                HStack(spacing: 14) {
                    // Plug visual indicator
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isOn ? Color.green.opacity(0.22) : Color(.tertiarySystemFill))
                            .frame(width: 48, height: 48)

                        Image(systemName: isOn ? "powerplug.fill" : "powerplug")
                            .font(.title2)
                            .foregroundColor(isOn ? .green : .secondary)
                            .shadow(color: isOn ? Color.green.opacity(0.6) : Color.clear, radius: 8)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let err = controller.lastError[device.id] {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        } else {
                            Text(isOn ? "On" : "Off")
                                .font(.subheadline)
                                .foregroundColor(isOn ? .green : .secondary)
                        }
                    }

                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)

            // Direct Quick Action Power Button (identical round style as LightDeviceCard)
            Button {
                controller.togglePower(for: device)
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            } label: {
                ZStack {
                    Circle()
                        .fill(isOn ? Color.green.opacity(0.2) : Color(.tertiarySystemFill))
                        .frame(width: 46, height: 46)

                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "power")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(isOn ? .green : .secondary)
                    }
                }
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
