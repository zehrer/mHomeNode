import Foundation
import SwiftUI

public enum RoomSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case local = "Local"
    case homeNodeServer = "HomeNode Server"
    case philipsHue = "Philips Hue"
    case appleHome = "Apple Home"

    public var id: String { rawValue }

    public var badgeColor: Color {
        switch self {
        case .local: return .secondary
        case .homeNodeServer: return .purple
        case .philipsHue: return .orange
        case .appleHome: return .blue
        }
    }

    public var iconName: String {
        switch self {
        case .local: return "iphone"
        case .homeNodeServer: return "server.rack"
        case .philipsHue: return "lightbulb.fill"
        case .appleHome: return "homekit"
        }
    }
}

public struct ManagedRoom: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var icon: String
    public var colorHex: String?
    public var source: RoomSource
    public var serverRoomId: String?
    public var externalId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "door.left.hand.open",
        colorHex: String? = nil,
        source: RoomSource = .local,
        serverRoomId: String? = nil,
        externalId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.source = source
        self.serverRoomId = serverRoomId
        self.externalId = externalId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return .blue
    }

    /// Maps emoji icons (commonly sent by HomeNode Server) to corresponding SF Symbols
    public static func sfSymbol(for iconOrEmoji: String) -> String {
        let clean = iconOrEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        switch clean {
        case "🛋️", "🛋": return "sofa.fill"
        case "🛏️", "🛏": return "bed.double.fill"
        case "🛁", "🚿": return "bathtub.fill"
        case "🍳", "🍽️", "🍴": return "fork.knife"
        case "💼", "💻", "🖥️": return "laptopcomputer"
        case "🧸": return "figure.child"
        case "🚪": return "door.left.hand.open"
        case "🧖", "🧖‍♂️", "🧖‍♀️": return "shower.fill"
        case "🌳", "🪴", "🌿", "🌱": return "tree.fill"
        case "🏠", "🏡": return "house.fill"
        case "📺": return "tv.fill"
        case "🚗", "🚙": return "car.fill"
        case "📦": return "archivebox.fill"
        case "📚": return "books.vertical.fill"
        case "🔥": return "fireplace.fill"
        case "💡": return "lightbulb.fill"
        case "📍": return "mappin.and.ellipse"
        default:
            if clean.isSFSymbolName {
                return clean
            }
            return "door.left.hand.open"
        }
    }

    /// Converts a ServerRoom into a ManagedRoom
    public static func from(serverRoom: ServerRoom) -> ManagedRoom {
        let mappedIcon = serverRoom.icon.map { sfSymbol(for: $0) } ?? "door.left.hand.open"
        return ManagedRoom(
            id: serverRoom.id,
            name: serverRoom.name,
            icon: mappedIcon,
            colorHex: nil,
            source: .homeNodeServer,
            serverRoomId: serverRoom.id
        )
    }

    /// Converts this ManagedRoom to a ServerRoom representation
    public func toServerRoom(deviceCount: Int? = nil) -> ServerRoom {
        ServerRoom(
            id: serverRoomId ?? id,
            name: name,
            floor: nil,
            icon: icon,
            archetype: nil,
            deviceCount: deviceCount
        )
    }
}

// MARK: - SF Symbol / Emoji Helper & Safe View
extension String {
    public var isSFSymbolName: Bool {
        guard !isEmpty else { return false }
        return allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }
}

public struct RoomIconView: View {
    public let icon: String
    public var size: CGFloat
    public var color: Color

    public init(_ icon: String, size: CGFloat = 16, color: Color = .primary) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    public var body: some View {
        if icon.isSFSymbolName {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(color)
        } else {
            Text(icon)
                .font(.system(size: size))
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    public init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean = String(clean.dropFirst())
        }
        guard clean.count == 6, let intVal = UInt64(clean, radix: 16) else {
            return nil
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    public func toHex() -> String? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
        #elseif canImport(AppKit)
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(rgb.redComponent * 255)), lroundf(Float(rgb.greenComponent * 255)), lroundf(Float(rgb.blueComponent * 255)))
        #else
        return nil
        #endif
    }
}
