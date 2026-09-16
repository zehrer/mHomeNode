import SwiftUI

public struct ScannerView: View {
    @Environment(ScannerViewModel.self) private var viewModel

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

                Section {
                    ForEach(vm.filteredDevices) { device in
                        NavigationLink(destination: DeviceDetailView(scannerVM: vm, deviceId: device.id)) {
                            DeviceRowView(device: device)
                        }
                    }
                } header: {
                    HStack {
                        Text("Discovered Devices (\(vm.filteredDevices.count))")
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
            .searchable(text: $vm.searchText, prompt: "Search by name, room, or UUID")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        vm.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(vm.filteredDevices.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Known Devices Only", isOn: $vm.onlyKnownDevices)

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
            .overlay {
                if vm.filteredDevices.isEmpty {
                    ContentUnavailableView(
                        vm.isScanning ? "Scanning for BLE Devices..." : "BLE Scout Idle",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text(vm.isScanning ? "Bring your iPhone near sensors to discover BTHome and BLE devices." : "Tap Scan to begin discovering devices.")
                    )
                }
            }
        }
    }
}
