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

    /// Converts a ServerRoom into a ManagedRoom
    public static func from(serverRoom: ServerRoom) -> ManagedRoom {
        ManagedRoom(
            id: serverRoom.id,
            name: serverRoom.name,
            icon: serverRoom.icon ?? "door.left.hand.open",
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
