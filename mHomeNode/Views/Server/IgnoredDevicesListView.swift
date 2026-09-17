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
                    "No Ignored Devices",
                    systemImage: "checkmark.shield",
                    description: Text("Unwanted BLE accessories can be marked as 'Ignored' from their detail page or scout swipe actions.")
                )
            } else {
                Section {
                    ForEach(records) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name ?? "Unnamed Device")
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

                            Text("Ignored since: \(item.ignoredAt)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                unignore(item.id)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    Text("Ignored Devices (\(records.count))")
                } footer: {
                    Text("Swipe left to restore a device back to active discovery.")
                }
            }
        }
        .navigationTitle("Ignore List")
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
                .help("Sync Ignore List with HomeNode Server")
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
