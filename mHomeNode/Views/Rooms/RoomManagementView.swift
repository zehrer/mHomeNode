import SwiftUI

public struct RoomManagementView: View {
    @Environment(ScannerViewModel.self) private var viewModel
    @State private var showAddSheet = false
    @State private var editingRoom: ManagedRoom?
    @State private var roomToDelete: ManagedRoom?
    @State private var isSyncing = false
    @State private var syncToast: String?

    // Common room icons for quick selection
    public static let availableIcons = [
        "sofa.fill", "bed.double.fill", "fork.knife", "laptopcomputer",
        "bathtub.fill", "tv.fill", "door.left.hand.open", "moon.stars.fill",
        "cup.and.saucer.fill", "refrigerator.fill", "shower.fill", "stairs",
        "tree.fill", "sun.max.fill", "car.fill", "archivebox.fill",
        "books.vertical.fill", "fireplace.fill", "house.fill", "lightbulb.fill"
    ]

    // Accent color palette
    public static let availableColors = [
        "#007AFF", "#34C759", "#FF9500", "#FF2D55",
        "#5856D6", "#5AC8FA", "#AF52DE", "#FFCC00"
    ]

    public init() {}

    public var body: some View {
        List {
            // MARK: - Summary & Sync Section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "door.left.hand.open")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(viewModel.roomManagementService.rooms.count) Configured Room(s)")
                            .font(.headline)
                        if let lastSync = viewModel.roomManagementService.lastSyncedDate {
                            Text("Synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Always saved locally for offline control")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        syncWithServer()
                    } label: {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.bold())
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSyncing)
                }
                .padding(.vertical, 4)

                if let toast = syncToast {
                    HStack {
                        Image(systemName: toast.contains("Error") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(toast.contains("Error") ? .orange : .green)
                        Text(toast)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("OK") {
                            syncToast = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.bold())
                    }
                }
            } header: {
                Text("Room Registry")
            } footer: {
                Text("Rooms persist permanently on your iPhone. When offline, all smart plugs, lights, and climate sensors remain assigned to their rooms.")
            }

            // MARK: - Rooms Grouped by Floor
            let distinctFloors = viewModel.roomManagementService.distinctFloors
            let unassignedRooms = viewModel.roomManagementService.rooms(forFloor: nil)

            if viewModel.roomManagementService.rooms.isEmpty {
                Section {
                    Text("No rooms configured yet. Tap + to add a room.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(distinctFloors, id: \.self) { floor in
                    let floorRooms = viewModel.roomManagementService.rooms(forFloor: floor)
                    Section {
                        ForEach(floorRooms) { room in
                            roomRow(room)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "stairs")
                                .font(.caption2)
                            Text("\(floor) (\(floorRooms.count))")
                        }
                    }
                }

                if !unassignedRooms.isEmpty {
                    Section {
                        ForEach(unassignedRooms) { room in
                            roomRow(room)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.folder")
                                .font(.caption2)
                            Text("Ohne Etage (\(unassignedRooms.count))")
                        }
                    }
                }
            }
        }
        .navigationTitle("Room Management")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Room", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            RoomEditSheet(
                title: "New Room",
                room: nil,
                onSave: { name, floor, icon, colorHex in
                    Task {
                        await viewModel.saveRoom(
                            name: name,
                            floor: floor,
                            icon: icon,
                            colorHex: colorHex
                        )
                    }
                }
            )
        }
        .sheet(item: $editingRoom) { room in
            RoomEditSheet(
                title: "Edit Room",
                room: room,
                onSave: { name, floor, icon, colorHex in
                    Task {
                        await viewModel.saveRoom(
                            name: name,
                            floor: floor,
                            icon: icon,
                            colorHex: colorHex,
                            existingRoom: room
                        )
                    }
                }
            )
        }
        .confirmationDialog(
            "Delete Room?",
            isPresented: Binding(
                get: { roomToDelete != nil },
                set: { if !$0 { roomToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = roomToDelete {
                Button("Delete '\(target.name)'", role: .destructive) {
                    Task {
                        await viewModel.deleteRoom(target)
                    }
                    roomToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    roomToDelete = nil
                }
            }
        } message: {
            Text("Are you sure? Devices assigned to this room will become unassigned.")
        }
    }

    private func roomRow(_ room: ManagedRoom) -> some View {
        Button {
            editingRoom = room
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(room.displayColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    RoomIconView(room.icon, size: 16, color: room.displayColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(room.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        syncStatusBadge(for: room)
                    }

                    let devCount = deviceCount(for: room.name)
                    Text("\(devCount) device\(devCount == 1 ? "" : "s") assigned")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                roomToDelete = room
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                editingRoom = room
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func syncStatusBadge(for room: ManagedRoom) -> some View {
        HStack(spacing: 4) {
            if room.serverRoomId != nil {
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
            }
            if room.externalId != nil {
                Image(systemName: "link")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
    }

    private func deviceCount(for roomName: String) -> Int {
        viewModel.bleService.devices.filter {
            !$0.isIgnored && $0.assignedRoom?.lowercased() == roomName.lowercased()
        }.count
    }

    private func syncWithServer() {
        isSyncing = true
        syncToast = nil

        Task {
            await viewModel.loadServerRooms()
            viewModel.syncAppleHomeRooms()
            await MainActor.run {
                self.isSyncing = false
                self.syncToast = "Rooms synchronized with HomeNode Server & Apple Home."
            }
        }
    }
}

// MARK: - Room Edit Sheet
public struct RoomEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let title: String
    public let room: ManagedRoom?
    public let onSave: (String, String?, String, String?) -> Void

    @State private var roomName: String = ""
    @State private var selectedFloor: String = ""
    @State private var selectedIcon: String = "sofa.fill"
    @State private var selectedColorHex: String = "#007AFF"

    public init(
        title: String,
        room: ManagedRoom?,
        onSave: @escaping (String, String?, String, String?) -> Void
    ) {
        self.title = title
        self.room = room
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Preview Card
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill((Color(hex: selectedColorHex) ?? .blue).opacity(0.15))
                                .frame(width: 50, height: 50)
                            RoomIconView(selectedIcon, size: 22, color: Color(hex: selectedColorHex) ?? .blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(roomName.isEmpty ? "Room Name" : roomName)
                                .font(.title3.bold())
                                .foregroundColor(roomName.isEmpty ? .secondary : .primary)
                            Text(selectedFloor.isEmpty ? "Keine Etage zugewiesen" : selectedFloor)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Name Input
                Section("Room Details") {
                    TextField("z.B. Wohnzimmer, Schlafzimmer...", text: $roomName)
                        .autocorrectionDisabled()
                }

                // Floor / Level
                Section("Etage / Floor") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ManagedRoom.standardFloors, id: \.self) { preset in
                                Button {
                                    if selectedFloor == preset {
                                        selectedFloor = ""
                                    } else {
                                        selectedFloor = preset
                                    }
                                } label: {
                                    Text(preset)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedFloor == preset ? (Color(hex: selectedColorHex) ?? .blue) : Color(.tertiarySystemFill))
                                        .foregroundColor(selectedFloor == preset ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    HStack {
                        Image(systemName: "stairs")
                            .foregroundColor(.secondary)
                        TextField("Oder eigene Etage (z.B. 2. OG, Studio...)", text: $selectedFloor)
                            .autocorrectionDisabled()
                    }
                }

                // Icon Palette
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                        ForEach(RoomManagementView.availableIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedIcon == icon ? (Color(hex: selectedColorHex) ?? .blue).opacity(0.2) : Color(.tertiarySystemFill))
                                        .frame(height: 44)
                                    RoomIconView(icon, size: 16, color: selectedIcon == icon ? (Color(hex: selectedColorHex) ?? .blue) : .primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Color Palette
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(RoomManagementView.availableColors, id: \.self) { hex in
                            Button {
                                selectedColorHex = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .blue)
                                        .frame(width: 32, height: 32)
                                    if selectedColorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let clean = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanFloor = selectedFloor.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            onSave(clean, cleanFloor.isEmpty ? nil : cleanFloor, selectedIcon, selectedColorHex)
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let r = room {
                    roomName = r.name
                    selectedFloor = r.floor ?? ""
                    selectedIcon = r.icon
                    selectedColorHex = r.colorHex ?? "#007AFF"
                }
            }
        }
    }
}
