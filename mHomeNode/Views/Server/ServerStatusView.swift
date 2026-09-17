import SwiftUI

public struct ServerStatusView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var connectionStatus: ServerConnectionStatus = .disconnected
    @State private var serverStatus: ServerStatus?
    @State private var isChecking = false
    @State private var isSyncingAll = false
    @State private var lastSyncResult: String?
    @State private var showManualConfig = false
    @State private var showClearConfirm = false

    public var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            Form {
                // MARK: - 1. Bonjour Discovery
                Section {
                    if vm.discoveryService.isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching for HomeNode Server on Wi-Fi (Bonjour)...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if vm.discoveryService.discoveredServers.isEmpty && !vm.discoveryService.isSearching {
                        HStack {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("No HomeNode Server found on local Wi-Fi.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(vm.discoveryService.discoveredServers) { server in
                            Button {
                                vm.selectDiscoveredServer(server)
                                checkConnection()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("\(server.preferredHost):\(server.port)")
                                            .font(.caption)
                                            .monospaced()
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if vm.serverConfig.host == server.preferredHost && vm.serverConfig.port == server.port {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        vm.discoveryService.startBrowsing()
                    } label: {
                        Label("Scan Again on Wi-Fi", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.discoveryService.isSearching)
                } header: {
                    Text("Automatic Server Discovery (Bonjour)")
                } footer: {
                    Text("HomeNode Server broadcasts Bonjour signals (_homenode._tcp). The app connects automatically without manual IP configuration.")
                }

                // MARK: - 2. Server Status
                Section("Connection Status") {
                    HStack {
                        Text("Status")
                        Spacer()
                        statusBadge
                    }

                    LabeledContent("Active Host", value: "\(vm.serverConfig.host):\(vm.serverConfig.port)")

                    if let status = serverStatus {
                        LabeledContent("Server Version", value: status.version)
                        LabeledContent("Active Matter Nodes", value: "\(status.activeMatterNodes)")
                        LabeledContent("BLE Gateways", value: "\(status.activeBLEGateways)")
                        if let dev = status.activeDevices {
                            LabeledContent("Total Active Devices", value: "\(dev)")
                        }
                        LabeledContent("Uptime", value: "\(status.uptimeSeconds / 60) min")
                    }

                    Button {
                        checkConnection()
                    } label: {
                        HStack {
                            Text("Test Connection Now")
                            Spacer()
                            if isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                        }
                    }
                    .disabled(isChecking)
                }

                // MARK: - 3. Scout Synchronization
                Section("Device Synchronization (Mobile Scout)") {
                    Button {
                        syncAllToHomeNodeServer()
                    } label: {
                        HStack {
                            Text("Transfer All Active BLE Devices")
                            Spacer()
                            if isSyncingAll {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                        }
                    }
                    .disabled(isSyncingAll || vm.filteredDevices.isEmpty)

                    if let syncRes = lastSyncResult {
                        Text(syncRes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Uploads all discovered BLE and BTHome sensors to HomeNode Server (POST /api/v1/mobile/ble).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 4. Persistent Storage
                Section("Local Device Storage") {
                    LabeledContent("Persisted Devices in Inventory", value: "\(vm.totalDevicesCount)")

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear Device Inventory (Reset Cache)", systemImage: "trash")
                    }
                    .disabled(vm.totalDevicesCount == 0)
                }

                // MARK: - 5. Ignore List
                Section {
                    NavigationLink(destination: IgnoredDevicesListView()) {
                        HStack {
                            Text("Ignored Devices")
                            Spacer()
                            Text("\(vm.ignoreService.ignoredRecords.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Ignore List")
                } footer: {
                    Text("Devices on the Ignore List will be excluded from automated server uploads and scout listings.")
                }

                // MARK: - 6. Manual Configuration (Advanced)
                Section {
                    DisclosureGroup("Manual Configuration (Advanced)", isExpanded: $showManualConfig) {
                        VStack(spacing: 12) {
                            TextField("Server Host (IP or Hostname)", text: $vm.serverConfig.host)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.roundedBorder)

                            Stepper("Port: \(vm.serverConfig.port)", value: $vm.serverConfig.port, in: 1...65535)

                            Toggle("Use TLS (HTTPS)", isOn: $vm.serverConfig.useTLS)

                            SecureField("API Key (Optional)", text: Binding(
                                get: { vm.serverConfig.apiKey ?? "" },
                                set: { vm.serverConfig.apiKey = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Only needed when using VPN tunnels or custom port forwardings outside your local Wi-Fi.")
                }
            }
            .navigationTitle("Server & Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if connectionStatus == .disconnected {
                    checkConnection()
                }
            }
            .confirmationDialog(
                "Do you really want to clear the local device inventory?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Inventory", role: .destructive) {
                    vm.clear()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(connectionStatus.rawValue)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .error: return .red
        }
    }

    private func checkConnection() {
        isChecking = true
        connectionStatus = .connecting

        Task {
            do {
                let status = try await viewModel.serverClient.checkHealth(config: viewModel.serverConfig)
                await MainActor.run {
                    self.serverStatus = status
                    self.connectionStatus = .connected
                    self.isChecking = false
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = .error
                    self.isChecking = false
                }
            }
        }
    }

    private func syncAllToHomeNodeServer() {
        isSyncingAll = true
        lastSyncResult = nil

        Task {
            await viewModel.syncDevicesToServer()
            await MainActor.run {
                self.lastSyncResult = viewModel.syncMessage
                self.isSyncingAll = false
            }
        }
    }
}
