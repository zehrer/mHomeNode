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
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            } else {
                                Button(role: .destructive) {
                                    vm.ignoreDevice(device, reason: "User Ignored")
                                } label: {
                                    Label("Ignore", systemImage: "nosign")
                                }
                                .tint(.red)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Devices (\(vm.filteredDevices.count) total • \(vm.activeDevicesCount) active)")
                        Spacer()
                        if vm.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("BLE Scout")
            .searchable(text: $vm.searchText, prompt: "Search by name, room, MAC, or UUID")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showSettingsSheet = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .help("Server & Settings")

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
                        .help("Sync active devices to HomeNode Server")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Known Sensors Only", isOn: $vm.onlyKnownDevices)
                        Toggle("Show Ignored Devices", isOn: $vm.showIgnoredDevices)

                        Divider()

                        Picker("Sort By", selection: $vm.sortOrder) {
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
                        vm.isScanning ? "Searching for BLE devices..." : "BLE Scout Ready",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text(vm.isScanning ? "Move your device close to accessories to discover them." : "Tap Scan to start discovering nearby Bluetooth devices.")
                    )
                }
            }
        }
    }
}
