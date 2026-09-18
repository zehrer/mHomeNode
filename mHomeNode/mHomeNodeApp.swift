import SwiftUI

@main
struct mHomeNodeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var scannerViewModel = ScannerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scannerViewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                scannerViewModel.resumeScanning()
            } else {
                scannerViewModel.pauseScanning()
            }
        }
    }
}
