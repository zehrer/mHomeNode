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

    public var body: some View {
        let isOn = controller.isPowerOn(for: device.id)
        let isBusy = controller.isDeviceBusy(device.id)

        HStack(spacing: 12) {
            Button {
                onSelect?()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isOn ? Color.green.opacity(0.16) : Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)

                        Image(systemName: isOn ? "powerplug.fill" : "powerplug")
                            .font(.system(size: 20))
                            .foregroundColor(isOn ? .green : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.displayTitle)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        HStack(spacing: 6) {
                            Text(isOn ? "ON" : "OFF")
                                .font(.caption2.bold())
                                .foregroundColor(isOn ? .green : .secondary)

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("\(device.rssi) dBm")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if device.isSignalLost {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("No signal")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Switch Toggle
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        controller.setPower(for: device.id, isOn: newValue)
                        #if canImport(UIKit)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        #endif
                    }
                ))
                .labelsHidden()
                .tint(.green)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}
