import Foundation

/// Represents decoded BTHome sensor payload data (V1 and V2)
public struct BTHomeData: Codable, Equatable, Sendable {
    public var version: Int
    public var isEncrypted: Bool
    public var packetId: UInt8?
    public var battery: UInt8?            // percentage 0-100%
    public var temperature: Double?       // °C
    public var humidity: Double?          // %
    public var pressure: Double?          // hPa
    public var illuminance: Double?       // lux
    public var isDoorOpen: Bool?          // Contact sensor (true = open, false = closed)
    public var isMotionDetected: Bool?    // Motion sensor
    public var buttonEvent: ButtonPressEvent?
    public var rotation: Double?          // degrees
    public var genericBoolean: Bool?
    public var rawMeasurements: [String: Double]

    public init(
        version: Int = 2,
        isEncrypted: Bool = false,
        packetId: UInt8? = nil,
        battery: UInt8? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil,
        pressure: Double? = nil,
        illuminance: Double? = nil,
        isDoorOpen: Bool? = nil,
        isMotionDetected: Bool? = nil,
        buttonEvent: ButtonPressEvent? = nil,
        rotation: Double? = nil,
        genericBoolean: Bool? = nil,
        rawMeasurements: [String: Double] = [:]
    ) {
        self.version = version
        self.isEncrypted = isEncrypted
        self.packetId = packetId
        self.battery = battery
        self.temperature = temperature
        self.humidity = humidity
        self.pressure = pressure
        self.illuminance = illuminance
        self.isDoorOpen = isDoorOpen
        self.isMotionDetected = isMotionDetected
        self.buttonEvent = buttonEvent
        self.rotation = rotation
        self.genericBoolean = genericBoolean
        self.rawMeasurements = rawMeasurements
    }
}

public enum ButtonPressEvent: String, Codable, Sendable {
    case press = "Press"
    case doublePress = "Double Press"
    case triplePress = "Triple Press"
    case longPress = "Long Press"

    public static func from(code: UInt8) -> ButtonPressEvent? {
        switch code {
        case 1: return .press
        case 2: return .doublePress
        case 3: return .triplePress
        case 4: return .longPress
        default: return nil
        }
    }
}
