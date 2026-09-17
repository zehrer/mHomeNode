import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        TabView {
            ClimateView()
                .tabItem {
                    Label("Climate", systemImage: "thermometer.sun.fill")
                }

            LightsView()
                .tabItem {
                    Label("Lights", systemImage: "lightbulb.fill")
                }

            ScannerView()
                .tabItem {
                    Label("Scout", systemImage: "antenna.radiowaves.left.and.right")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(ScannerViewModel())
}
