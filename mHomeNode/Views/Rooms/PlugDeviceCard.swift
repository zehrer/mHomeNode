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
        HStack(spacing: 12) {
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
                        .frame(width: 40, height: 40)

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
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let err = controller.lastError[device.id] {
                            Text(err)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if onSelect != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
}
