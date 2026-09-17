import SwiftUI

public struct DeviceDetailView: View {
    @Bindable var scannerVM: ScannerViewModel
    let deviceId: UUID

    @State private var customNameInput = ""
    @State private var selectedRoom = ""
    @State private var isCustomRoom = false
    @State private var customRoomInput = ""
    @State private var showingIgnoreAlert = false
    @State private var isSaving = false
    @State private var syncStatusMessage: String?

    private var device: DiscoveredDevice? {
        scannerVM.bleService.devices.first(where: { $0.id == deviceId })
    }

    public var body: some View {
        Group {
            if let device = device {
                List {
                    // MARK: - 1. Name & Room Assignment Section
                    Section {
                        HStack {
                            Text("Name")
                                .frame(width: 80, alignment: .leading)
                            TextField("z.B. Wohnzimmer Thermometer", text: $customNameInput)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                        }

                        Picker("Room", selection: $selectedRoom) {
                            Text("Not Assigned").tag("")
                            ForEach(scannerVM.serverRooms) { room in
                                Text("\(room.icon ?? "🏠") \(room.name)\(room.floor.map { " (\($0))" } ?? "")")
                                    .tag(room.name)
                            }
                            if !selectedRoom.isEmpty && !scannerVM.serverRooms.contains(where: { $0.name == selectedRoom }) {
                                Text("📍 \(selectedRoom)").tag(selectedRoom)
                            }
                        }

                        Button {
                            saveAndSync(device: device)
                        } label: {
                            HStack {
                                Label("Save & Sync to Server", systemImage: "arrow.triangle.2.circlepath")
                                    .fontWeight(.medium)
                                Spacer()
                                if isSaving {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(isSaving)

                        if let msg = syncStatusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(msg.contains("Successfully") ? Color.green : Color.secondary)
                        }
                    } header: {
                        Text("Device Name & Room Assignment")
                    } footer: {
                        Text("Assign a friendly name and link this device to a room. Changes are saved locally and synced directly to HomeNode Server.")
                    }

                    // MARK: - 2. Proximity & Signal Section
                    Section("Signal & Scout Proximity") {
                        HStack {
                            Text("Signal Strength (RSSI)")
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                            SignalStrengthView(rssi: device.rssi, bars: device.signalBars)
                        }

                        HStack {
                            Text("Last Seen")
                            Spacer()
                            Text(device.lastSeen, style: .relative)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Status")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(device.isCurrentlyActive ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(device.isCurrentlyActive ? "Active" : "Idle")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // MARK: - 3. Decoded BTHome Telemetry
                    if let btHome = device.btHomeData {
                        Section("Sensor Telemetry (BTHome V\(btHome.version))") {
                            if let temp = btHome.temperature {
                                LabeledContent("Temperature", value: String(format: "%.2f °C", temp))
                            }
                            if let hum = btHome.humidity {
                                LabeledContent("Humidity", value: String(format: "%.1f %%", hum))
                            }
                            if let press = btHome.pressure {
                                LabeledContent("Pressure", value: String(format: "%.2f hPa", press))
                            }
                            if let lux = btHome.illuminance {
                                LabeledContent("Illuminance", value: String(format: "%.1f lux", lux))
                            }
                            if let battery = btHome.battery {
                                LabeledContent("Battery", value: "\(battery) %")
                            }
                            if let door = btHome.isDoorOpen {
                                LabeledContent("Door / Window", value: door ? "Open" : "Closed")
                            }
                            if let motion = btHome.isMotionDetected {
                                LabeledContent("Motion", value: motion ? "Detected" : "Clear")
                            }
                            if let button = btHome.buttonEvent {
                                LabeledContent("Button Event", value: button.rawValue)
                            }
                            if let packetId = btHome.packetId {
                                LabeledContent("Packet Counter", value: "\(packetId)")
                            }
                            LabeledContent("Encryption", value: btHome.isEncrypted ? "Yes" : "No (Plaintext)")
                        }
                    }

                    // MARK: - 4. Device Management & Ignore List
                    Section("Device Management & Ignore List") {
                        if device.isIgnored {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Device Ignored", systemImage: "hand.raised.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)

                                Text("Signals from this device are hidden from scout lists and excluded from server sync.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    scannerVM.unignoreDevice(device)
                                } label: {
                                    Label("Restore Device", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button(role: .destructive) {
                                showingIgnoreAlert = true
                            } label: {
                                Label("🚫 Add to Ignore List", systemImage: "nosign")
                            }
                        }
                    }

                    // MARK: - 5. Technical Details
                    Section("Hardware Metadata") {
                        LabeledContent("Device Family", value: device.family.rawValue)
                        if let mac = device.macAddress {
                            LabeledContent("MAC Address", value: mac)
                        }
                        LabeledContent("UUID", value: device.id.uuidString)
                        LabeledContent("Connectable", value: device.isConnectable ? "Yes" : "No")

                        if let mfgHex = device.manufacturerDataHex {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manufacturer Data (Hex)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(mfgHex)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }

                        if !device.serviceUUIDs.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Advertised Service UUIDs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(device.serviceUUIDs, id: \.self) { uuid in
                                    Text(uuid)
                                        .font(.system(.footnote, design: .monospaced))
                                }
                            }
                        }
                    }
                }
                .navigationTitle(device.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    customNameInput = device.customName ?? (device.name == "Unknown" ? "" : device.name)
                    selectedRoom = device.assignedRoom ?? ""
                }
            } else {
                ContentUnavailableView("Device Not Found", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
        .alert("Add to Ignore List?", isPresented: $showingIgnoreAlert) {
            Button("Yes, Ignore Device", role: .destructive) {
                if let dev = device {
                    scannerVM.ignoreDevice(dev, reason: "User Ignored")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device will be hidden from discovery lists and its signals will be ignored.")
        }
    }

    private func saveAndSync(device: DiscoveredDevice) {
        isSaving = true
        syncStatusMessage = nil

        let trimmedName = customNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmedName.isEmpty ? nil : trimmedName
        let newRoom = selectedRoom.isEmpty ? nil : selectedRoom

        Task {
            let success = await scannerVM.renameAndClaimDevice(device, newName: newName, newRoom: newRoom)
            await MainActor.run {
                self.isSaving = false
                self.syncStatusMessage = success
                    ? "Successfully saved and synced with HomeNode Server."
                    : "Saved locally (Server currently unreachable)."
            }
        }
    }
}
