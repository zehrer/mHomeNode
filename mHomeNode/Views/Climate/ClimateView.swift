import SwiftUI

public struct ClimateView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var showSettingsSheet = false
    @State private var selectedDevice: DiscoveredDevice?

    public init() {}

    private var climateDevices: [DiscoveredDevice] {
        viewModel.bleService.devices.filter { device in
            !device.isIgnored &&
            (device.btHomeData?.temperature != nil || device.btHomeData?.humidity != nil)
        }
    }

    private var groupedRooms: [(roomName: String, serverRoom: ServerRoom?, devices: [DiscoveredDevice])] {
        let grouped = Dictionary(grouping: climateDevices) { dev in
            dev.assignedRoom ?? "Not Assigned"
        }

        // Separate assigned rooms and unassigned
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

        // Sort assigned rooms alphabetically by name (or floor)
        assignedGroups.sort { g1, g2 in
            if let f1 = g1.serverRoom?.floor, let f2 = g2.serverRoom?.floor, f1 != f2 {
                return f1 < f2
            }
            return g1.roomName.localizedStandardCompare(g2.roomName) == .orderedAscending
        }

        if let unassigned = unassignedGroup {
            assignedGroups.append(unassigned)
        }

        return assignedGroups
    }

    private var activeClimateDevices: [DiscoveredDevice] {
        climateDevices.filter { !$0.isSignalLost }
    }

    private var overallAverageTemperature: Double? {
        let temps = activeClimateDevices.compactMap { $0.btHomeData?.temperature }
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    private var overallAverageHumidity: Double? {
        let hums = activeClimateDevices.compactMap { $0.btHomeData?.humidity }
        guard !hums.isEmpty else { return nil }
        return hums.reduce(0, +) / Double(hums.count)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !climateDevices.isEmpty {
                        // Summary Banner
                        overviewHeader
                            .padding(.horizontal)
                            .padding(.top, 6)

                        // Room Cards
                        LazyVStack(spacing: 14) {
                            ForEach(groupedRooms, id: \.roomName) { group in
                                RoomClimateCard(
                                    roomName: group.roomName,
                                    serverRoom: group.serverRoom,
                                    devices: group.devices,
                                    onSelectDevice: { dev in
                                        selectedDevice = dev
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "No Climate Sensors Discovered",
                            systemImage: "thermometer.snowflake",
                            description: Text("BTHome and Qingping sensors periodically broadcast temperature and humidity.\nBLE Scout scans continuously in the background.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Climate")
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
                    HStack(spacing: 8) {
                        if viewModel.isScanning {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        Text("\(climateDevices.count) Sensors")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
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

    private var overviewHeader: some View {
        HStack(spacing: 12) {
            if let avgTemp = overallAverageTemperature {
                HStack(spacing: 10) {
                    Image(systemName: "thermometer.sun.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AVG TEMP")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f°C", avgTemp))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if let avgHum = overallAverageHumidity {
                HStack(spacing: 10) {
                    Image(systemName: "humidity.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AVG HUM")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", avgHum))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            VStack(alignment: .center, spacing: 2) {
                Text("ROOMS")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(groupedRooms.filter { $0.roomName != "Not Assigned" && $0.roomName != "Nicht zugeordnet" }.count)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundColor(.primary)
            }
            .frame(width: 65)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}
