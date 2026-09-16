import SwiftUI

@main
struct mHomeNodeApp: App {
    @State private var scannerViewModel = ScannerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scannerViewModel)
        }
    }
}
