import SwiftUI

public struct SaveScanSheet: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scanTitle: String = ""
    @State private var scanNote: String = ""
    @State private var acquiredLocation: ScanLocation?
    @State private var isFetchingLocation: Bool = false
    @State private var locationStatusMessage: String?

    public init() {}

    private var devicesCount: Int {
        viewModel.filteredDevices.isEmpty
            ? viewModel.bleService.devices.filter { !$0.isIgnored }.count
            : viewModel.filteredDevices.count
    }

    private var activeCount: Int {
        viewModel.filteredDevices.isEmpty
            ? viewModel.bleService.devices.filter { !$0.isIgnored && $0.isCurrentlyActive }.count
            : viewModel.filteredDevices.filter { $0.isCurrentlyActive }.count
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Snapshot Info
                Section {
                    TextField("Title (e.g. Living Room, Office, Garden)", text: $scanTitle)
                        .font(.body)

                    TextField("Notes (optional)", text: $scanNote, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Snapshot Details")
                } footer: {
                    Text("Give this scan a memorable title to easily compare readings later.")
                }

                // MARK: - Location Tag
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: acquiredLocation != nil ? "location.fill" : "location.slash")
                            .foregroundColor(acquiredLocation != nil ? .blue : .secondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 3) {
                            if isFetchingLocation {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Acquiring GPS location...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            } else if let loc = acquiredLocation {
                                Text(loc.displayTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)

                                HStack(spacing: 6) {
                                    Text(loc.formattedCoordinates)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary)

                                    if let acc = loc.formattedAccuracy {
                                        Text("• \(acc)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("No Location Attached")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                if let msg = locationStatusMessage {
                                    Text(msg)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            fetchLocation()
                        } label: {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.title3)
                        }
                        .disabled(isFetchingLocation)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Location")
                } footer: {
                    Text("Attaching your location makes it easy to survey signals across different sites and rooms.")
                }

                // MARK: - Device Summary
                Section("Devices In Snapshot") {
                    HStack {
                        Label("\(devicesCount) Devices Included", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.subheadline)
                        Spacer()
                        Text("\(activeCount) active now")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Save BLE Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveCurrentScan(
                            title: scanTitle,
                            note: scanNote,
                            location: acquiredLocation
                        )
                        dismiss()
                    }
                    .bold()
                }
            }
            .task {
                fetchLocation()
            }
        }
    }

    private func fetchLocation() {
        isFetchingLocation = true
        locationStatusMessage = nil

        Task {
            let loc = await viewModel.locationService.fetchCurrentLocation()
            isFetchingLocation = false
            if let l = loc {
                acquiredLocation = l
                // Pre-fill default title with place name if user hasn't typed one
                if scanTitle.isEmpty {
                    if let place = l.placeName, !place.isEmpty {
                        scanTitle = "Scan at \(place)"
                    } else {
                        scanTitle = "Scan (\(Date().formatted(date: .abbreviated, time: .shortened)))"
                    }
                }
            } else {
                locationStatusMessage = "Location unavailable or permission not granted."
                if scanTitle.isEmpty {
                    scanTitle = "Scan (\(Date().formatted(date: .abbreviated, time: .shortened)))"
                }
            }
        }
    }
}
