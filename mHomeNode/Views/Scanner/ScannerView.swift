import SwiftUI

public struct ScannerView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var showSettingsSheet = false

    public init() {}

    public var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            List {
                if let error = vm.bleService.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let syncMsg = vm.syncMessage {
                    Section {
                        HStack {
                            Label(syncMsg, systemImage: "cloud.fill")
                                .font(.footnote)
                            Spacer()
                            Button("OK") {
                                vm.syncMessage = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section {
                    ForEach(vm.filteredDevices) { device in
                        NavigationLink(destination: DeviceDetailView(scannerVM: vm, deviceId: device.id)) {
                            DeviceRowView(device: device)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if device.isIgnored {
                                Button {
                                    vm.unignoreDevice(device)
                                } label: {
                                    Label("Wiederherstellen", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            } else {
                                Button(role: .destructive) {
                                    vm.ignoreDevice(device, reason: "Nachbargerät")
                                } label: {
                                    Label("Ignorieren", systemImage: "nosign")
                                }
                                .tint(.red)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Geräte (\(vm.filteredDevices.count) total • \(vm.activeDevicesCount) aktiv)")
                        Spacer()
                        if vm.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("HomeNode Scout")
            .searchable(text: $vm.searchText, prompt: "Name, Raum, MAC oder UUID suchen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showSettingsSheet = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .help("Server & Einstellungen")

                        Button(role: .destructive) {
                            vm.clear()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(vm.filteredDevices.isEmpty)

                        Button {
                            Task {
                                await vm.syncDevicesToServer()
                            }
                        } label: {
                            if vm.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                            }
                        }
                        .disabled(vm.isSyncing || vm.filteredDevices.isEmpty)
                        .help("Aktive Geräte mit HomeNode Server synchronisieren")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Nur bekannte Sensoren", isOn: $vm.onlyKnownDevices)
                        Toggle("Ignorierte Nachbarn anzeigen", isOn: $vm.showIgnoredDevices)

                        Divider()

                        Picker("Sortierung", selection: $vm.sortOrder) {
                            ForEach(DeviceSortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.toggleScan()
                    } label: {
                        Label(
                            vm.isScanning ? "Stop" : "Scan",
                            systemImage: vm.isScanning ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .tint(vm.isScanning ? .red : .accentColor)
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                ServerStatusView()
            }
            .overlay {
                if vm.filteredDevices.isEmpty {
                    ContentUnavailableView(
                        vm.isScanning ? "Suche nach BLE-Geräten..." : "BLE Scout Bereit",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text(vm.isScanning ? "Bewege dein Gerät in die Nähe von Sensoren, um BTHome und Qingping Geräte zu erfassen." : "Tippe auf Scan, um die Geräteaufzeichnung zu starten.")
                    )
                }
            }
        }
    }
}
