import SwiftUI
import MapKit

public struct SavedScanDetailView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    public let session: SavedScanSession
    @State private var searchText: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var isSyncingToServer: Bool = false
    @State private var syncResultBanner: String?

    public init(session: SavedScanSession) {
        self.session = session
    }

    private var filteredDevices: [DiscoveredDevice] {
        if searchText.isEmpty {
            return session.devices
        }
        let q = searchText.lowercased()
        return session.devices.filter { dev in
            dev.name.lowercased().contains(q) ||
            dev.displayTitle.lowercased().contains(q) ||
            (dev.macAddress?.lowercased().contains(q) ?? false) ||
            dev.family.rawValue.lowercased().contains(q)
        }
    }

    public var body: some View {
        List {
            // MARK: - Header Info
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(.title2.bold())
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Label(session.timestamp.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Label("\(session.deviceCount) Devices", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let note = session.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Geolocation & Map
            if let loc = session.location {
                Section("Location") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(.red)

                            VStack(alignment: .leading, spacing: 2) {
                                if let place = loc.placeName, !place.isEmpty {
                                    Text(place)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                }

                                Text(loc.formattedCoordinates)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)

                                if let acc = loc.formattedAccuracy {
                                    Text("Accuracy: \(acc)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Mini Map
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        ))) {
                            Marker(loc.placeName ?? session.title, coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude))
                                .tint(.red)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: - Server Sync Result
            if let result = syncResultBanner {
                Section {
                    HStack {
                        Label(result, systemImage: "cloud.fill")
                            .font(.footnote)
                        Spacer()
                        Button("OK") {
                            syncResultBanner = nil
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            // MARK: - Captured Devices
            Section {
                ForEach(filteredDevices) { device in
                    DeviceRowView(device: device)
                }
            } header: {
                HStack {
                    Text("Captured Devices (\(filteredDevices.count))")
                    Spacer()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scan Snapshot")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter devices in snapshot")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: session.exportSummary(),
                        subject: Text(session.title),
                        message: Text("mHomeNode BLE Scan Report")
                    ) {
                        Label("Share Text Report", systemImage: "square.and.arrow.up")
                    }

                    if let jsonData = session.exportJSONData(), let jsonString = String(data: jsonData, encoding: .utf8) {
                        ShareLink(
                            item: jsonString,
                            subject: Text("\(session.title).json"),
                            message: Text("mHomeNode Scan JSON")
                        ) {
                            Label("Share JSON", systemImage: "curlybraces")
                        }
                    }

                    Button {
                        syncSnapshotToServer()
                    } label: {
                        Label("Sync Devices to Server", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    .disabled(isSyncingToServer)

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Snapshot", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete Scan Snapshot?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Snapshot", role: .destructive) {
                viewModel.deleteSavedScan(id: session.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to permanently delete \"\(session.title)\"?")
        }
    }

    private func syncSnapshotToServer() {
        isSyncingToServer = true
        syncResultBanner = nil
        Task {
            if let res = await viewModel.syncSavedScanToServer(session) {
                syncResultBanner = "\(res.ingested) device(s) transferred to Server."
            } else {
                syncResultBanner = viewModel.syncMessage ?? "Sync completed."
            }
            isSyncingToServer = false
        }
    }
}
