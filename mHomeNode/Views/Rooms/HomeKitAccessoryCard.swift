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
        HStack(spacing: 14) {
            // Accessory icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? activeColor.opacity(0.22) : Color(.tertiarySystemFill))
                    .frame(width: 48, height: 48)

                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(isOn ? activeColor : .secondary)
                    .shadow(color: isOn ? activeColor.opacity(0.6) : Color.clear, radius: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(accessory.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Apple Home")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    if let model = accessory.model, !model.isEmpty {
                        Text("• \(model)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(isOn ? "On" : "Off")
                        .font(.subheadline)
                        .foregroundColor(isOn ? activeColor : .secondary)
                }
            }

            Spacer(minLength: 8)

            // Direct Quick Action Power Button
            Button {
                onToggle()
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            } label: {
                ZStack {
                    Circle()
                        .fill(isOn ? activeColor.opacity(0.2) : Color(.tertiarySystemFill))
                        .frame(width: 46, height: 46)

                    Image(systemName: "power")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(isOn ? activeColor : .secondary)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
