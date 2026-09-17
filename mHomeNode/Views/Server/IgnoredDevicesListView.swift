import SwiftUI

public struct IgnoredDevicesListView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var isSyncing = false

    public init() {}

    public var body: some View {
        let records = viewModel.ignoreService.ignoredRecords

        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "Keine ignorierten Geräte",
                    systemImage: "checkmark.shield",
                    description: Text("Fremde BLE-Sensoren vom Nachbarn können im Scanner als 'Ignorieren' markiert werden.")
                )
            } else {
                Section {
                    ForEach(records) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name ?? "Unbenanntes Gerät")
                                    .font(.headline)
                                Spacer()
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(Capsule())
                            }

                            Text(item.id)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text("Blockiert seit: \(item.ignoredAt)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                unignore(item.id)
                            } label: {
                                Label("Wiederherstellen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    Text("Blockierte Nachbargeräte (\(records.count))")
                } footer: {
                    Text("Nach links wischen, um ein Gerät wieder in der Geräteliste freizugeben.")
                }
            }
        }
        .navigationTitle("Ignorierte Geräte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    syncWithServer()
                } label: {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
            }
        }
    }

    private func unignore(_ id: String) {
        viewModel.ignoreService.unignore(id: id)
        if let uuid = UUID(uuidString: id) {
            viewModel.bleService.setDeviceIgnored(id: uuid, isIgnored: false)
        }
        Task {
            let _ = try? await viewModel.serverClient.unignoreDeviceOnServer(config: viewModel.serverConfig, id: id)
        }
    }

    private func syncWithServer() {
        isSyncing = true
        Task {
            await viewModel.ignoreService.syncWithServer(client: viewModel.serverClient, config: viewModel.serverConfig)
            await MainActor.run {
                self.isSyncing = false
            }
        }
    }
}
