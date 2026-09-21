import SwiftUI

public struct RoomsView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var selectedRoomName: String = ""
    @State private var selectedDevice: DiscoveredDevice?
    @State private var showSettingsSheet = false
    @State private var showRoomManagementSheet = false
    @State private var detectionToast: String?
    @State private var isDetecting: Bool = false

    public init() {}

    /// All distinct rooms: combines persistent roomManagementService rooms with server rooms and any device assignments
    private var availableRooms: [(name: String, serverRoom: ServerRoom?, managedRoom: ManagedRoom?)] {
        var result: [(name: String, serverRoom: ServerRoom?, managedRoom: ManagedRoom?)] = []
        var seenNames = Set<String>()

        // 1. Persistent Unified Rooms (always available offline)
        for room in viewModel.roomManagementService.rooms {
            let sRoom = viewModel.serverRooms.first(where: {
                $0.id == room.serverRoomId || $0.name.lowercased() == room.name.lowercased()
            })
            result.append((name: room.name, serverRoom: sRoom ?? room.toServerRoom(), managedRoom: room))
            seenNames.insert(room.name.lowercased())
        }

        // 2. Any rooms from active location's persistent device registry
        for reg in viewModel.locationManagementService.activeLocation.devices {
            if let assigned = reg.assignedRoom,
               !assigned.isEmpty,
               assigned != "Not Assigned",
               assigned != "Nicht zugeordnet",
               !seenNames.contains(assigned.lowercased()) {
                result.append((name: assigned, serverRoom: nil, managedRoom: nil))
                seenNames.insert(assigned.lowercased())
            }
        }

        // 4. Any additional custom rooms assigned on currently discovered devices
        for dev in viewModel.bleService.devices {
            if let assigned = dev.assignedRoom,
               !assigned.isEmpty,
               assigned != "Not Assigned",
               assigned != "Nicht zugeordnet",
               !seenNames.contains(assigned.lowercased()) {
                result.append((name: assigned, serverRoom: nil, managedRoom: nil))
                seenNames.insert(assigned.lowercased())
            }
        }

        return result
    }

    private var currentRoomData: (name: String, serverRoom: ServerRoom?, managedRoom: ManagedRoom?)? {
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

                    // MARK: - Selected Room Detail Content (with integrated room selector in Hero Banner)
                    if let current = currentRoomData {
                        RoomDetailView(
                            scannerVM: viewModel,
                            roomName: current.name,
                            serverRoom: current.serverRoom,
                            availableRooms: availableRooms,
                            onSelectRoom: { newName in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedRoomName = newName
                                }
                            },
                            onSelectDevice: { dev in
                                selectedDevice = dev
                            }
                        )
                    } else {
                        VStack(spacing: 14) {
                            ContentUnavailableView(
                                "No Rooms Available",
                                systemImage: "house",
                                description: Text("Create a room or sync with HomeNode Server to organize your home accessories.")
                            )
                            Button {
                                showRoomManagementSheet = true
                            } label: {
                                Label("Manage Rooms", systemImage: "door.left.hand.open")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 60)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showRoomManagementSheet) {
                NavigationStack {
                    RoomManagementView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showRoomManagementSheet = false
                                }
                            }
                        }
                }
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
