import SwiftUI

public struct SignalStrengthView: View {
    public let rssi: Int
    public let bars: Int

    public init(rssi: Int, bars: Int) {
        self.rssi = rssi
        self.bars = bars
    }

    private var signalColor: Color {
        switch bars {
        case 4: return .green
        case 3: return .mint
        case 2: return .orange
        case 1: return .red
        default: return .gray
        }
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? signalColor : Color.secondary.opacity(0.25))
                    .frame(width: 3.5, height: CGFloat(Double(i) * 3.5 + 4.0))
            }
        }
        .accessibilityLabel("Signal strength: \(rssi) dBm")
    }
}
