import SwiftUI

public struct LightDeviceCard: View {
    public let device: DiscoveredDevice
    public let serverRoom: ServerRoom?
    public let controller: GoveeLightController?
    public let homeKitData: HomeKitAccessoryData?
    public var onSelect: (() -> Void)?
    public var onToggleHybrid: (() -> Void)?

    public init(
        device: DiscoveredDevice,
        serverRoom: ServerRoom? = nil,
        controller: GoveeLightController? = nil,
        homeKitData: HomeKitAccessoryData? = nil,
        onSelect: (() -> Void)? = nil,
        onToggleHybrid: (() -> Void)? = nil
    ) {
        self.device = device
        self.serverRoom = serverRoom
        self.controller = controller
        self.homeKitData = homeKitData
        self.onSelect = onSelect
        self.onToggleHybrid = onToggleHybrid
    }

    private var isLightOn: Bool {
        if let hkPower = homeKitData?.isPowerOn {
            return hkPower
        }
        return controller?.isPowerOn(for: device.id) ?? false
    }

    private var isBusy: Bool {
        controller?.isDeviceBusy(device.id) ?? false
    }

    private var currentBrightness: Int {
        if let hkBright = homeKitData?.brightness {
            return hkBright
        }
        return controller?.getBrightness(for: device.id) ?? 100
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Interactive State Icon / Toggle Button
            Button {
                if let hybrid = onToggleHybrid {
                    hybrid()
                } else {
                    controller?.togglePower(for: device.id)
                }
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isLightOn ? Color.yellow.opacity(0.22) : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)

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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(device.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        // Dual-Interface Badge
                        if homeKitData != nil {
                            Image(systemName: "house.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        if isLightOn && currentBrightness < 100 {
                            Text("\(currentBrightness)%")
                                .font(.caption2.weight(.medium))
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
