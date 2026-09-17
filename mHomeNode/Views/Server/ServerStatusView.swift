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
                            Text("Suche nach HomeNode Server im WLAN (Bonjour)...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if vm.discoveryService.discoveredServers.isEmpty && !vm.discoveryService.isSearching {
                        HStack {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("Kein HomeNode Server im WLAN gefunden.")
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
                        Label("Im WLAN neu suchen", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.discoveryService.isSearching)
                } header: {
                    Text("Automatischer Server-Suchlauf (Bonjour)")
                } footer: {
                    Text("HomeNode Server sendet Bonjour-Signale (_homenode._tcp). Das iPhone erkennt den Server vollautomatisch ohne manuelle IP-Eingabe.")
                }

                // MARK: - 2. Server Status
                Section("Verbindungsstatus") {
                    HStack {
                        Text("Status")
                        Spacer()
                        statusBadge
                    }

                    LabeledContent("Aktiver Host", value: "\(vm.serverConfig.host):\(vm.serverConfig.port)")

                    if let status = serverStatus {
                        LabeledContent("Server Version", value: status.version)
                        LabeledContent("Active Matter Nodes", value: "\(status.activeMatterNodes)")
                        LabeledContent("BLE Gateways", value: "\(status.activeBLEGateways)")
                        if let dev = status.activeDevices {
                            LabeledContent("Aktive Geräte gesamt", value: "\(dev)")
                        }
                        LabeledContent("Laufzeit", value: "\(status.uptimeSeconds / 60) min")
                    }

                    Button {
                        checkConnection()
                    } label: {
                        HStack {
                            Text("Verbindung jetzt testen")
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
                Section("Geräte-Synchronisation (Mobile Scout)") {
                    Button {
                        syncAllToHomeNodeServer()
                    } label: {
                        HStack {
                            Text("Alle aktiven BLE-Geräte übertragen")
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

                    Text("Überträgt alle erfassten BLE- und BTHome-Sensoren an den HomeNode Server (POST /api/v1/mobile/ble).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 4. Persistent Storage
                Section("Lokaler Gerätespeicher") {
                    LabeledContent("Gespeicherte Geräte im Inventar", value: "\(vm.totalDevicesCount)")

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Geräteinventar leeren (Cache löschen)", systemImage: "trash")
                    }
                    .disabled(vm.totalDevicesCount == 0)
                }

                // MARK: - 5. Neighbor Device Blocklist
                Section("Nachbargeräte & Filter") {
                    NavigationLink(destination: IgnoredDevicesListView()) {
                        HStack {
                            Text("Ignorierte Nachbargeräte")
                            Spacer()
                            Text("\(vm.ignoreService.ignoredRecords.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - 6. Manual Configuration (Advanced)
                Section {
                    DisclosureGroup("Manuelle Konfiguration (Erweitert)", isExpanded: $showManualConfig) {
                        VStack(spacing: 12) {
                            TextField("Server Host (IP oder Hostname)", text: $vm.serverConfig.host)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.roundedBorder)

                            Stepper("Port: \(vm.serverConfig.port)", value: $vm.serverConfig.port, in: 1...65535)

                            Toggle("TLS verwenden (HTTPS)", isOn: $vm.serverConfig.useTLS)

                            SecureField("API Key (Optional)", text: Binding(
                                get: { vm.serverConfig.apiKey ?? "" },
                                set: { vm.serverConfig.apiKey = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Nur nötig bei VPN-Verbindungen oder individuellen Portweiterleitungen außerhalb des heimischen WLANs.")
                }
            }
            .navigationTitle("Server & Discovery")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
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
                "Möchtest du das gesamte lokale Geräteinventar wirklich löschen?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Inventar löschen", role: .destructive) {
                    vm.clear()
                }
                Button("Abbrechen", role: .cancel) {}
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
