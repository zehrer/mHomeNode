import SwiftUI

public struct DeviceDetailView: View {
    @Bindable var scannerVM: ScannerViewModel
    let deviceId: UUID

    @State private var showingRoomPicker = false
    @State private var roomInput = ""

    private var device: DiscoveredDevice? {
        scannerVM.bleService.devices.first(where: { $0.id == deviceId })
    }

    public var body: some View {
        Group {
            if let device = device {
                List {
                    // Proximity & Signal Section
                    Section("Signal & Scout Proximity") {
                        HStack {
                            Text("Current RSSI")
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                            SignalStrengthView(rssi: device.rssi, bars: device.signalBars)
                        }

                        HStack {
                            Text("Room Assignment")
                            Spacer()
                            Text(device.assignedRoom ?? "Not Assigned")
                                .foregroundStyle(.secondary)
                            Button("Edit") {
                                roomInput = device.assignedRoom ?? ""
                                showingRoomPicker = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        HStack {
                            Text("Last Seen")
                            Spacer()
                            Text(device.lastSeen, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Decoded BTHome Telemetry
                    if let btHome = device.btHomeData {
                        Section("Decoded Sensor Data (BTHome V\(btHome.version))") {
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
                            LabeledContent("Encrypted", value: btHome.isEncrypted ? "Yes" : "No (Plaintext)")
                        }
                    }

                    // Technical Details
                    Section("Hardware Metadata") {
                        LabeledContent("Device Family", value: device.family.rawValue)
                        LabeledContent("Identifier", value: device.id.uuidString)
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
            } else {
                ContentUnavailableView("Device Not Found", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
        .alert("Assign Room", isPresented: $showingRoomPicker) {
            TextField("e.g. Living Room, Kitchen", text: $roomInput)
            Button("Save") {
                scannerVM.bleService.updateRoom(for: deviceId, room: roomInput.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
