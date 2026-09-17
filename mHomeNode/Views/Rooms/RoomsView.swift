import SwiftUI

public struct RoomsView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var selectedRoomName: String = ""
    @State private var selectedDevice: DiscoveredDevice?
    @State private var showSettingsSheet = false
    @State private var detectionToast: String?
    @State private var isDetecting: Bool = false

    public init() {}

    /// All distinct rooms: combines server-configured rooms with any custom device-assigned rooms
    private var availableRooms: [(name: String, serverRoom: ServerRoom?)] {
        var result: [(name: String, serverRoom: ServerRoom?)] = []
        var seenNames = Set<String>()

        // 1. Configured Server Rooms
        for room in viewModel.serverRooms {
            result.append((name: room.name, serverRoom: room))
            seenNames.insert(room.name.lowercased())
        }

        // 2. Any additional custom rooms assigned on devices
        for dev in viewModel.bleService.devices {
            if let assigned = dev.assignedRoom,
               !assigned.isEmpty,
               assigned != "Not Assigned",
               assigned != "Nicht zugeordnet",
               !seenNames.contains(assigned.lowercased()) {
                result.append((name: assigned, serverRoom: nil))
                seenNames.insert(assigned.lowercased())
            }
        }

        return result
    }

    private var currentRoomData: (name: String, serverRoom: ServerRoom?)? {
        if let found = availableRooms.first(where: { $0.name == selectedRoomName }) {
            return found
        }
        return availableRooms.first
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Proximity Detection Toast Banner
                    if let toast = detectionToast {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text(toast)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                withAnimation {
                                    detectionToast = nil
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // MARK: - Horizontal Room Carousel
                    if !availableRooms.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(availableRooms, id: \.name) { item in
                                    let isSelected = (currentRoomData?.name == item.name)

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedRoomName = item.name
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(item.serverRoom?.icon ?? "🏠")
                                                .font(.subheadline)
                                            Text(item.name)
                                                .font(.subheadline.weight(isSelected ? .bold : .regular))

                                            let count = viewModel.bleService.devices.filter {
                                                !$0.isIgnored && $0.assignedRoom == item.name
                                            }.count
                                            if count > 0 {
                                                Text("\(count)")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(isSelected ? Color.white.opacity(0.25) : Color(.tertiarySystemFill))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }

                    // MARK: - Selected Room Detail Content
                    if let current = currentRoomData {
                        RoomDetailView(
                            scannerVM: viewModel,
                            roomName: current.name,
                            serverRoom: current.serverRoom,
                            onSelectDevice: { dev in
                                selectedDevice = dev
                            }
                        )
                    } else {
                        ContentUnavailableView(
                            "No Rooms Available",
                            systemImage: "house",
                            description: Text("Connect to HomeNode Server or assign devices to rooms to view room details.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rooms")
            .refreshable {
                await viewModel.loadServerRooms()
            }
            .toolbar {
                // Hamburger Menu for Settings
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.medium))
                    }
                    .help("Server & Settings")
                }

                // Auto-Detect Room Action
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        detectRoom()
                    } label: {
                        HStack(spacing: 5) {
                            if isDetecting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "location.viewfinder")
                                    .font(.subheadline.bold())
                            }
                            Text("Detect Room")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    .disabled(isDetecting)
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
            .onAppear {
                if selectedRoomName.isEmpty, let first = availableRooms.first {
                    selectedRoomName = first.name
                }
            }
        }
    }

    private func detectRoom() {
        isDetecting = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isDetecting = false
            if let result = viewModel.detectNearestRoom() {
                withAnimation {
                    selectedRoomName = result.roomName
                    detectionToast = "Switched to \(result.roomName) (via \(result.strongestDevice.displayTitle) at \(result.rssi) dBm)"
                }
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                #endif
            } else {
                withAnimation {
                    detectionToast = "No active room devices nearby"
                }
            }

            // Auto-hide toast after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation {
                    if detectionToast != nil {
                        detectionToast = nil
                    }
                }
            }
        }
    }
}
