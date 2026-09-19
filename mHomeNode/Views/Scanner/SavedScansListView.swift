import SwiftUI

public struct SavedScansListView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    public init() {}

    private var filteredSessions: [SavedScanSession] {
        if searchText.isEmpty {
            return viewModel.savedScans
        }
        let q = searchText.lowercased()
        return viewModel.savedScans.filter { s in
            s.title.lowercased().contains(q) ||
            (s.note?.lowercased().contains(q) ?? false) ||
            (s.location?.displayTitle.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                if filteredSessions.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Saved Scans" : "No Matching Scans",
                        systemImage: "archivebox",
                        description: Text(searchText.isEmpty
                            ? "Save scan snapshots in BLE Scout to review device signals and telemetry later."
                            : "No scans found matching \"\(searchText)\".")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredSessions) { session in
                        NavigationLink(destination: SavedScanDetailView(session: session)) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(session.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(session.deviceCount) dev")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.secondarySystemFill))
                                        .clipShape(Capsule())
                                }

                                HStack(spacing: 8) {
                                    Label(
                                        session.timestamp.formatted(date: .abbreviated, time: .shortened),
                                        systemImage: "calendar"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                    if let loc = session.location {
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 2) {
                                            Image(systemName: "mappin.and.ellipse")
                                            Text(loc.displayTitle)
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                    }
                                }

                                if let note = session.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteSavedScan(id: session.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Saved Scans")
            .searchable(text: $searchText, prompt: "Search saved scans by title or location")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.savedScans.isEmpty {
                        Menu {
                            if let jsonURL = viewModel.exportAllJSONFileURL() {
                                ShareLink(item: jsonURL) {
                                    Label("Export All as JSON File", systemImage: "curlybraces")
                                }
                            } else if let json = viewModel.exportAllJSON() {
                                ShareLink(item: json, subject: Text("mHomeNode_all_scans.json")) {
                                    Label("Export All as JSON (Backup)", systemImage: "curlybraces")
                                }
                            }

                            if let csvURL = viewModel.exportAllCSVFileURL() {
                                ShareLink(item: csvURL) {
                                    Label("Export All as CSV File (Excel)", systemImage: "tablecells")
                                }
                            } else {
                                ShareLink(item: viewModel.exportAllCSV(), subject: Text("mHomeNode_all_scans.csv")) {
                                    Label("Export All as CSV (Excel)", systemImage: "tablecells")
                                }
                            }

                            ShareLink(item: viewModel.exportAllSummary(), subject: Text("mHomeNode_scans_summary.txt")) {
                                Label("Export All as Summary Text", systemImage: "doc.text")
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
