import SwiftUI

public struct HomeKitAccessoryCard: View {
    public let accessory: HomeKitAccessoryData
    public let onToggle: () -> Void

    public init(accessory: HomeKitAccessoryData, onToggle: @escaping () -> Void) {
        self.accessory = accessory
        self.onToggle = onToggle
    }

    private var isOn: Bool {
        accessory.isPowerOn == true
    }

    private var iconName: String {
        if accessory.isLight {
            return isOn ? "lightbulb.fill" : "lightbulb"
        } else {
            return isOn ? "powerplug.fill" : "powerplug"
        }
    }

    private var activeColor: Color {
        accessory.isLight ? .yellow : .green
    }

    public var body: some View {
        Button {
            onToggle()
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
        } label: {
            HStack(spacing: 10) {
                // Interactive State Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? activeColor.opacity(0.22) : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)

                    Image(systemName: iconName)
                        .font(.headline)
                        .foregroundColor(isOn ? activeColor : .secondary)
                        .shadow(color: isOn ? activeColor.opacity(0.5) : Color.clear, radius: 6)
                }

                HStack(spacing: 4) {
                    Text(accessory.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Image(systemName: "house.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apple Home Service Group Card

public struct HomeKitGroupCard: View {
    public let group: HomeKitServiceGroupData
    public let onToggle: () -> Void

    public init(group: HomeKitServiceGroupData, onToggle: @escaping () -> Void) {
        self.group = group
        self.onToggle = onToggle
    }

    private var isOn: Bool {
        group.isPowerOn == true
    }

    private var iconName: String {
        if group.isLight {
            return isOn ? "lightbulb.fill" : "lightbulb"
        } else {
            return isOn ? "powerplug.fill" : "powerplug"
        }
    }

    private var activeColor: Color {
        group.isLight ? .yellow : .green
    }

    public var body: some View {
        Button {
            onToggle()
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
        } label: {
            HStack(spacing: 10) {
                // Interactive State Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? activeColor.opacity(0.22) : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)

                    Image(systemName: iconName)
                        .font(.headline)
                        .foregroundColor(isOn ? activeColor : .secondary)
                        .shadow(color: isOn ? activeColor.opacity(0.5) : Color.clear, radius: 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Image(systemName: "house.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }

                    if group.serviceCount > 1 {
                        Text("\(group.serviceCount) Geräte")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
