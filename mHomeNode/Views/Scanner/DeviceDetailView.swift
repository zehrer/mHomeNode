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

                        Picker("Raum", selection: $selectedRoom) {
                            Text("Nicht zugeordnet").tag("")
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
                                Label("Speichern & Server-Abgleich", systemImage: "arrow.triangle.2.circlepath")
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
                                .foregroundStyle(msg.contains("Erfolgreich") ? Color.green : Color.secondary)
                        }
                    } header: {
                        Text("Gerätename & Raumzuordnung")
                    } footer: {
                        Text("Vergib einen eigenen Gerätenamen und weise das Gerät einem Raum zu. Beim Speichern wird der Name auch direkt an den HomeNode Server übertragen.")
                    }

                    // MARK: - 2. Proximity & Signal Section
                    Section("Signal & Scout Proximity") {
                        HStack {
                            Text("Signalstärke (RSSI)")
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                            SignalStrengthView(rssi: device.rssi, bars: device.signalBars)
                        }

                        HStack {
                            Text("Zuletzt gesehen")
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
                                Text(device.isCurrentlyActive ? "Aktiv" : "Inaktiv")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // MARK: - 3. Decoded BTHome Telemetry
                    if let btHome = device.btHomeData {
                        Section("Sensordaten (BTHome V\(btHome.version))") {
                            if let temp = btHome.temperature {
                                LabeledContent("Temperatur", value: String(format: "%.2f °C", temp))
                            }
                            if let hum = btHome.humidity {
                                LabeledContent("Luftfeuchtigkeit", value: String(format: "%.1f %%", hum))
                            }
                            if let press = btHome.pressure {
                                LabeledContent("Luftdruck", value: String(format: "%.2f hPa", press))
                            }
                            if let lux = btHome.illuminance {
                                LabeledContent("Helligkeit", value: String(format: "%.1f lux", lux))
                            }
                            if let battery = btHome.battery {
                                LabeledContent("Batterie", value: "\(battery) %")
                            }
                            if let door = btHome.isDoorOpen {
                                LabeledContent("Tür / Fenster", value: door ? "Geöffnet" : "Geschlossen")
                            }
                            if let motion = btHome.isMotionDetected {
                                LabeledContent("Bewegung", value: motion ? "Erkannt" : "Keine")
                            }
                            if let button = btHome.buttonEvent {
                                LabeledContent("Taster Event", value: button.rawValue)
                            }
                            if let packetId = btHome.packetId {
                                LabeledContent("Paketzähler", value: "\(packetId)")
                            }
                            LabeledContent("Verschlüsselung", value: btHome.isEncrypted ? "Ja" : "Nein (Klartext)")
                        }
                    }

                    // MARK: - 4. Device Management & Privacy (Block Neighbor Devices)
                    Section("Geräteverwaltung & Filter (Nachbargeräte)") {
                        if device.isIgnored {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Als Nachbargerät blockiert", systemImage: "hand.raised.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)

                                Text("Signale dieses Geräts werden in der Hauptliste ausgeblendet und beim automatischen Server-Sync ignoriert.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    scannerVM.unignoreDevice(device)
                                } label: {
                                    Label("Nicht mehr ignorieren (Wiederherstellen)", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button(role: .destructive) {
                                showingIgnoreAlert = true
                            } label: {
                                Label("🚫 Als Nachbargerät ignorieren", systemImage: "nosign")
                            }
                        }
                    }

                    // MARK: - 5. Technical Details
                    Section("Hardware Metadaten") {
                        LabeledContent("Gerätefamilie", value: device.family.rawValue)
                        if let mac = device.macAddress {
                            LabeledContent("MAC-Adresse", value: mac)
                        }
                        LabeledContent("UUID", value: device.id.uuidString)
                        LabeledContent("Verbindbar", value: device.isConnectable ? "Ja" : "Nein")

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
                ContentUnavailableView("Gerät nicht gefunden", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
        .alert("Nachbargerät ignorieren?", isPresented: $showingIgnoreAlert) {
            Button("Ja, als Nachbargerät ignorieren", role: .destructive) {
                if let dev = device {
                    scannerVM.ignoreDevice(dev, reason: "Nachbargerät")
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieses Gerät wird in der Hauptliste ausgeblendet und Signale werden nicht weiter verarbeitet.")
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
                    ? "Erfolgreich gespeichert und mit HomeNode Server synchronisiert."
                    : "Lokal gespeichert (Server aktuell nicht erreichbar)."
            }
        }
    }
}
