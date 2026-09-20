import SwiftUI

public struct LocationsManagementView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false
    @State private var locationToEdit: ManagedLocation?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // Current Live Detection Banner
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.activeLocationState.iconName)
                            .font(.title2)
                            .foregroundColor(viewModel.activeLocationState.isAtHome ? .green : .blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Current Presence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(viewModel.activeLocationState.title)
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Live Detection")
                } footer: {
                    Text("mHomeNode automatically detects when you are at Home via Bonjour discovery of your HomeNode server in WLAN and your GPS coordinates.")
                }

                // Configured Locations List
                Section {
                    ForEach(viewModel.locationManagementService.locations) { loc in
                        LocationRowView(
                            location: loc,
                            isActive: (viewModel.activeLocation.id == loc.id),
                            onTap: {
                                locationToEdit = loc
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let loc = viewModel.locationManagementService.locations[idx]
                            viewModel.locationManagementService.deleteLocation(id: loc.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Configured Locations")
                        Spacer()
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.caption.bold())
                        }
                    }
                }
            }
            .navigationTitle("Locations & Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                EditLocationSheet(location: ManagedLocation(id: UUID(), name: "New Location", radiusMeters: 150.0)) { newLoc in
                    viewModel.locationManagementService.saveLocation(newLoc)
                }
            }
            .sheet(item: $locationToEdit) { loc in
                EditLocationSheet(location: loc) { updatedLoc in
                    viewModel.locationManagementService.saveLocation(updatedLoc)
                }
            }
        }
    }
}

private struct LocationRowView: View {
    let location: ManagedLocation
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(location.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if location.isDefault {
                        Text("Default")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    // Server indicator
                    if let srv = location.associatedServerHost, !srv.isEmpty {
                        Label(srv, systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label("No Server Linked", systemImage: "network.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // GPS indicator
                    if location.latitude != nil && location.longitude != nil {
                        Label("Geofenced (±\(Int(location.radiusMeters))m)", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label("No GPS Set", systemImage: "location.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Device count
                Text("\(location.devices.count) registered device(s) & rooms")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct EditLocationSheet: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State var location: ManagedLocation
    let onSave: (ManagedLocation) -> Void

    @State private var isCalibratingGPS = false

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Location Name", text: $location.name)
                    Toggle("Default Location", isOn: $location.isDefault)
                }

                Section("HomeNode Server Connection") {
                    if let srv = location.associatedServerHost, !srv.isEmpty {
                        LabeledContent("Associated Server", value: srv)
                    } else {
                        Text("No server linked to this location.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }

                    let activeHost = viewModel.serverConfig.host
                    if !activeHost.isEmpty {
                        Button {
                            location.associatedServerHost = activeHost
                            location.associatedServerPort = viewModel.serverConfig.port
                        } label: {
                            Label("Link Current Server (\(activeHost))", systemImage: "link")
                        }
                    } else {
                        Text("Connect to a HomeNode Server via WLAN to link it automatically.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Geofence & GPS Coordinates") {
                    if let lat = location.latitude, let lon = location.longitude {
                        LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", lat, lon))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Geofence Radius: \(Int(location.radiusMeters)) meters")
                                .font(.subheadline)
                            Slider(value: $location.radiusMeters, in: 50...1000, step: 25)
                        }
                    } else {
                        Text("No coordinates assigned yet.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }

                    Button {
                        isCalibratingGPS = true
                        Task {
                            if let gps = await viewModel.locationService.fetchCurrentLocation() {
                                location.latitude = gps.latitude
                                location.longitude = gps.longitude
                            }
                            isCalibratingGPS = false
                        }
                    } label: {
                        HStack {
                            Label("Use Current GPS Location", systemImage: "location.viewfinder")
                            if isCalibratingGPS {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                Section("Registered Devices & Rooms (\(location.devices.count))") {
                    if location.devices.isEmpty {
                        Text("No devices registered to this location yet. When you assign a room or custom name to a device, it is saved here permanently.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(location.devices) { dev in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(dev.displayTitle)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    if let room = dev.assignedRoom, !room.isEmpty {
                                        Text(room)
                                            .font(.caption.bold())
                                            .foregroundColor(.blue)
                                    }
                                }
                                Text("ID: \(dev.id) • Family: \(dev.vendorFamily)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            location.devices.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(location)
                        dismiss()
                    }
                }
            }
        }
    }
}
