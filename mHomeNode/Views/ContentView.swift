import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        TabView {
            ClimateView()
                .tabItem {
                    Label("Klima", systemImage: "thermometer.sun.fill")
                }

            ScannerView()
                .tabItem {
                    Label("BLE Scout", systemImage: "antenna.radiowaves.left.and.right")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(ScannerViewModel())
}
