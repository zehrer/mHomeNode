import SwiftUI

public struct ContentView: View {
    public var body: some View {
        TabView {
            ScannerView()
                .tabItem {
                    Label("BLE Scout", systemImage: "antenna.radiowaves.left.and.right")
                }

            ServerStatusView()
                .tabItem {
                    Label("HomeNode Server", systemImage: "server.rack")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(ScannerViewModel())
}
