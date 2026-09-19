import SwiftUI

public struct ScannerView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var showSettingsSheet = false
    @State private var showSaveScanSheet = false
    @State private var showSavedScansList = false

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

                if let autoMsg = vm.autoScanBanner {
                    Section {
                        HStack {
                            Label(autoMsg, systemImage: "sparkles")
                                .font(.footnote)
                                .foregroundColor(.accentColor)
                            Spacer()
                            Button("OK") {
                                vm.autoScanBanner = nil
                            }
                            .buttonStyle(.borderless)
                        }
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

                if vm.isAutoLocationScanEnabled {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Scan on Move Active")
                                    .font(.subheadline.bold())
                                Text("Archives & restarts scan after moving \(Int(vm.autoScanDistanceThreshold))m")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let lastPlace = vm.lastAutoScanLocation?.displayTitle {
                                Text(lastPlace)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
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
                    HStack(spacing: 12) {
                        Button {
                            showSaveScanSheet = true
                        } label: {
                            Image(systemName: "camera.viewfinder")
                        }
                        .disabled(vm.filteredDevices.isEmpty && vm.bleService.devices.isEmpty)
                        .help("Save current scan snapshot")

                        Button {
                            showSavedScansList = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "archivebox")
                                if !vm.savedScans.isEmpty {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 2, y: -2)
                                }
                            }
                        }
                        .help("View saved scan archive")

                        Menu {
                            Section("Location Auto-Scan") {
                                Toggle("Auto-Scan on Move", isOn: $vm.isAutoLocationScanEnabled)
                                if vm.isAutoLocationScanEnabled {
                                    Picker("Distance Trigger", selection: $vm.autoScanDistanceThreshold) {
                                        Text("50 m").tag(50.0)
                                        Text("100 m").tag(100.0)
                                        Text("250 m").tag(250.0)
                                        Text("500 m").tag(500.0)
                                    }
                                }
                            }

                            Section("Filters") {
                                Toggle("Known Sensors Only", isOn: $vm.onlyKnownDevices)
                                Toggle("Show Ignored Devices", isOn: $vm.showIgnoredDevices)
                            }

                            Divider()

                            Picker("Sort By", selection: $vm.sortOrder) {
                                ForEach(DeviceSortOrder.allCases) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                        } label: {
                            Image(systemName: vm.isAutoLocationScanEnabled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
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
            .sheet(isPresented: $showSaveScanSheet) {
                SaveScanSheet()
            }
            .sheet(isPresented: $showSavedScansList) {
                SavedScansListView()
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
