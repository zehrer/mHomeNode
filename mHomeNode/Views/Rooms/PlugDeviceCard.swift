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
        HStack(spacing: 10) {
            // Interactive State Icon / Toggle Button
            Button {
                controller.togglePower(for: device)
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? Color.green.opacity(0.22) : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)

                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isOn ? "powerplug.fill" : "powerplug")
                            .font(.headline)
                            .foregroundColor(isOn ? .green : .secondary)
                            .shadow(color: isOn ? Color.green.opacity(0.5) : Color.clear, radius: 6)
                    }
                }
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)

            // Main card body (tappable to view details)
            Button {
                onSelect?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let err = controller.lastError[device.id] {
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
}
