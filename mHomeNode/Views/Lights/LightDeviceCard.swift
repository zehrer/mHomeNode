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
        HStack(spacing: 12) {
            // Interactive State Icon / Toggle Button
            Button {
                controller?.togglePower(for: device.id)
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isLightOn ? Color.yellow.opacity(0.22) : Color(.tertiarySystemFill))
                        .frame(width: 40, height: 40)

                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isLightOn ? "lightbulb.fill" : "lightbulb")
                            .font(.headline)
                            .foregroundColor(isLightOn ? .yellow : .secondary)
                            .shadow(color: isLightOn ? Color.yellow.opacity(0.5) : Color.clear, radius: 6)
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
                        HStack(spacing: 6) {
                            Text(device.displayTitle)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if isLightOn && currentBrightness < 100 {
                                Text("\(currentBrightness)%")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let err = controller?.lastError[device.id] {
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
