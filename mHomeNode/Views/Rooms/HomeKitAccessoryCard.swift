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
            HStack(spacing: 12) {
                // Interactive State Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? activeColor.opacity(0.22) : Color(.tertiarySystemFill))
                        .frame(width: 40, height: 40)

                    Image(systemName: iconName)
                        .font(.headline)
                        .foregroundColor(isOn ? activeColor : .secondary)
                        .shadow(color: isOn ? activeColor.opacity(0.5) : Color.clear, radius: 6)
                }

                HStack(spacing: 6) {
                    Text(accessory.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Image(systemName: "house.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
