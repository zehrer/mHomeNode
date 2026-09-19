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
                    // MARK: - Light Controls
                    if device.isLightingDevice {
                        Section {
                            let isLightOn = scannerVM.lightController.isPowerOn(for: device.id)
                            let isBusy = scannerVM.lightController.isDeviceBusy(device.id)

                            // Power Toggle Row
                            HStack {
                                Label {
                                    Text("Power")
                                        .font(.body.weight(.medium))
                                } icon: {
                                    Image(systemName: isLightOn ? "lightbulb.fill" : "lightbulb")
                                        .foregroundColor(isLightOn ? .yellow : .secondary)
                                }

                                Spacer()

                                if isBusy {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 6)
                                }

                                Toggle("", isOn: Binding(
                                    get: { isLightOn },
                                    set: { scannerVM.lightController.setPower(for: device.id, isOn: $0) }
                                ))
                                .labelsHidden()
                                .disabled(isBusy)
                            }

                            // Brightness Slider
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Brightness", systemImage: "sun.max.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(scannerVM.lightController.getBrightness(for: device.id))%")
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(scannerVM.lightController.getBrightness(for: device.id)) },
                                        set: { scannerVM.lightController.setBrightness(for: device.id, percent: Int($0)) }
                                    ),
                                    in: 1...100,
                                    step: 1
                                )
                                .tint(.yellow)
                                .disabled(!isLightOn || isBusy)
                            }
                            .padding(.vertical, 4)

                            // Colors & Scenes Presets
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Colors & Scenes")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(lightPresetColors, id: \.name) { preset in
                                            Button {
                                                scannerVM.lightController.setColor(
                                                    for: device.id,
                                                    red: preset.r,
                                                    green: preset.g,
                                                    blue: preset.b
                                                )
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Circle()
                                                        .fill(preset.color)
                                                        .frame(width: 34, height: 34)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                                        )
                                                    Text(preset.name)
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!isLightOn || isBusy)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, 4)

                            if let error = scannerVM.lightController.lastError[device.id] {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        } header: {
                            Text("Light Controls")
                        } footer: {
                            Text("Direct Bluetooth Low Energy control. Commands are sent directly to the device without cloud dependency.")
                        }
                    }

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

                    // MARK: - 5. Active GATT Deep Inspection
                    if device.isConnectable {
                        Section {
                            if let info = device.inspectionInfo {
                                if let mfg = info.manufacturerName {
                                    LabeledContent("Manufacturer", value: mfg)
                                }
                                if let model = info.modelNumber {
                                    LabeledContent("Model Number", value: model)
                                }
                                if let dname = info.deviceName {
                                    LabeledContent("GATT Device Name", value: dname)
                                }
                                if let cat = info.appearanceCategory {
                                    LabeledContent("Appearance Category", value: cat)
                                }
                                if let fw = info.firmwareRevision {
                                    LabeledContent("Firmware Revision", value: fw)
                                }
                                if let hw = info.hardwareRevision {
                                    LabeledContent("Hardware Revision", value: hw)
                                }
                                if let serial = info.serialNumber {
                                    LabeledContent("Serial Number", value: serial)
                                }
                                if let bat = info.batteryLevel {
                                    LabeledContent("GATT Battery Level", value: "\(bat)%")
                                }
                                LabeledContent("Inspected", value: info.inspectedAt, format: .dateTime)
                            }

                            if scannerVM.isInspecting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Connecting & reading GATT characteristics...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else {
                                Button {
                                    Task {
                                        _ = await scannerVM.inspectDevice(id: device.id)
                                    }
                                } label: {
                                    Label(
                                        device.inspectionInfo == nil ? "Inspect Device (Read GATT Info)" : "Re-inspect Device",
                                        systemImage: "magnifyingglass.circle"
                                    )
                                }
                                .buttonStyle(.borderless)
                            }

                            if let err = scannerVM.inspectionError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        } header: {
                            Text("Active GATT Deep Inspection")
                        } footer: {
                            Text("Connects briefly to query standard Device Information and Generic Access characteristics.")
                        }
                    }

                    // MARK: - 6. Technical Details
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

                        if let sdata = device.serviceDataHex, !sdata.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Service Data Payloads")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(sdata.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                                    HStack {
                                        Text(key)
                                            .font(.system(.caption, design: .monospaced).bold())
                                        Spacer()
                                        Text(val)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
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

private struct LightPresetColor {
    let name: String
    let color: Color
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

private let lightPresetColors: [LightPresetColor] = [
    LightPresetColor(name: "Warm", color: Color(red: 1.0, green: 0.85, blue: 0.6), r: 255, g: 216, b: 153),
    LightPresetColor(name: "Daylight", color: Color(red: 1.0, green: 0.96, blue: 0.92), r: 255, g: 245, b: 235),
    LightPresetColor(name: "Cool", color: Color(red: 0.85, green: 0.92, blue: 1.0), r: 216, g: 235, b: 255),
    LightPresetColor(name: "Amber", color: .orange, r: 255, g: 140, b: 0),
    LightPresetColor(name: "Red", color: .red, r: 255, g: 30, b: 30),
    LightPresetColor(name: "Green", color: .green, r: 30, g: 220, b: 60),
    LightPresetColor(name: "Blue", color: .blue, r: 30, g: 100, b: 255),
    LightPresetColor(name: "Purple", color: .purple, r: 160, g: 32, b: 240)
]
