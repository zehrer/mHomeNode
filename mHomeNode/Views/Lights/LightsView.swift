import SwiftUI

public struct LightsView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var showSettingsSheet = false
    @State private var selectedDevice: DiscoveredDevice?

    public init() {}

    private var lightDevices: [DiscoveredDevice] {
        viewModel.bleService.devices.filter { device in
            !device.isIgnored && device.isLightingDevice
        }
    }

    private var activeLightsCount: Int {
        lightDevices.filter { $0.isCurrentlyActive }.count
    }

    private var groupedRooms: [(roomName: String, serverRoom: ServerRoom?, devices: [DiscoveredDevice])] {
        let grouped = Dictionary(grouping: lightDevices) { dev in
            dev.assignedRoom ?? "Not Assigned"
        }

        var assignedGroups: [(roomName: String, serverRoom: ServerRoom?, devices: [DiscoveredDevice])] = []
        var unassignedGroup: (roomName: String, serverRoom: ServerRoom?, devices: [DiscoveredDevice])?

        for (name, devs) in grouped {
            let sRoom = viewModel.serverRooms.first(where: { $0.name.lowercased() == name.lowercased() })
            if name == "Not Assigned" || name == "Nicht zugeordnet" {
                unassignedGroup = (roomName: "Not Assigned", serverRoom: nil, devices: devs)
            } else {
                assignedGroups.append((roomName: name, serverRoom: sRoom, devices: devs))
            }
        }

        assignedGroups.sort { g1, g2 in
            g1.roomName.localizedStandardCompare(g2.roomName) == .orderedAscending
        }

        if let unassigned = unassignedGroup {
            assignedGroups.append(unassigned)
        }

        return assignedGroups
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !lightDevices.isEmpty {
                        // Summary Metrics Banner
                        summaryBanner
                            .padding(.horizontal)
                            .padding(.top, 6)

                        // Room-grouped Light Cards
                        LazyVStack(spacing: 16) {
                            ForEach(groupedRooms, id: \.roomName) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Text(group.serverRoom?.icon ?? (group.roomName == "Not Assigned" ? "❓" : "🏠"))
                                            .font(.subheadline)
                                        Text(group.roomName)
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        if let floor = group.serverRoom?.floor, !floor.isEmpty {
                                            Text("(\(floor))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text("\(group.devices.count)")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color(.tertiarySystemFill))
                                            .clipShape(Capsule())
                                    }
                                    .padding(.horizontal, 4)

                                    ForEach(group.devices) { device in
                                        LightDeviceCard(
                                            device: device,
                                            serverRoom: group.serverRoom,
                                            controller: viewModel.lightController,
                                            onSelect: {
                                                selectedDevice = device
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "No Lights Discovered",
                            systemImage: "lightbulb.slash",
                            description: Text("Govee outdoor lights, LED strips, and smart bulbs will appear here automatically when discovered nearby.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lights")
            .refreshable {
                await viewModel.loadServerRooms()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.medium))
                    }
                    .help("Server & Settings")
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            for dev in lightDevices {
                                viewModel.setLightPower(for: dev, isOn: true)
                            }
                        } label: {
                            Label("Turn All On", systemImage: "lightbulb.fill")
                        }

                        Button {
                            for dev in lightDevices {
                                viewModel.setLightPower(for: dev, isOn: false)
                            }
                        } label: {
                            Label("Turn All Off", systemImage: "lightbulb.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                    }
                    .disabled(lightDevices.isEmpty)
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                ServerStatusView()
            }
            .sheet(item: $selectedDevice) { dev in
                NavigationStack {
                    DeviceDetailView(scannerVM: viewModel, deviceId: dev.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    selectedDevice = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private var summaryBanner: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text("\(activeLightsCount)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            HStack(spacing: 10) {
                Image(systemName: "lightbulb.2.fill")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text("\(lightDevices.count)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            HStack(spacing: 10) {
                Image(systemName: "square.split.2x2")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ROOMS")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text("\(groupedRooms.filter { $0.roomName != "Not Assigned" }.count)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}
