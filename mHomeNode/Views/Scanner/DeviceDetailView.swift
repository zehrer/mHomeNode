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
    @State private var lanAddressInput = ""
    @State private var isTestingLAN = false
    @State private var lanTestResult: String?

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

                    // MARK: - Smart Plug / Switch Controls
                    if device.isSwitchablePlug {
                        Section {
                            let isPlugOn = scannerVM.shellyController.isPowerOn(for: device.id)
                            let isBusy = scannerVM.shellyController.isDeviceBusy(device.id)

                            // Power Toggle Row
                            HStack {
                                Label {
                                    Text("Socket Power")
                                        .font(.body.weight(.medium))
                                } icon: {
                                    Image(systemName: isPlugOn ? "powerplug.fill" : "powerplug")
                                        .foregroundColor(isPlugOn ? .green : .secondary)
                                }

                                Spacer()

                                if isBusy {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 6)
                                }

                                Toggle("", isOn: Binding(
                                    get: { isPlugOn },
                                    set: { scannerVM.shellyController.setPower(for: device, isOn: $0) }
                                ))
                                .labelsHidden()
                                .tint(.green)
                                .disabled(isBusy)
                            }

                            // Active Interface Row
                            HStack {
                                Text("Control Interface")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                let active = scannerVM.shellyController.getActiveInterface(for: device.id)
                                let isServer = active == .server
                                let isLan = active == .lan || (active == nil && device.lanAddress != nil)
                                HStack(spacing: 4) {
                                    if isServer {
                                        Image(systemName: "server.rack")
                                        Text("HomeNode Server")
                                    } else if isLan {
                                        Image(systemName: "network")
                                        Text("Wi-Fi / LAN HTTP")
                                    } else {
                                        Image(systemName: "point.3.connected.trianglepath.dotted")
                                        Text("Direct Bluetooth LE")
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundColor(isServer ? .purple : (isLan ? .blue : .secondary))
                            }

                            if let error = scannerVM.shellyController.lastError[device.id] {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        } header: {
                            Text("Smart Plug Controls")
                        } footer: {
                            Text("Multi-interface control: uses HomeNode Server if connected, direct local Wi-Fi/LAN if reachable, or direct Bluetooth Low Energy as fallback.")
                        }
                    }

                    // MARK: - Apple HomeKit Status & Live Telemetry
                    let homeKitData = scannerVM.findHomeKitData(for: device)
                    if device.isHomeKitAccessory || homeKitData != nil {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "house.fill")
                                        .font(.title3)
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(homeKitData?.name ?? "Apple HomeKit Zubehör")
                                            .font(.headline)
                                        Text(homeKitData != nil ? "Verbunden via Apple HomeKit Framework" : (device.isHomeKitPaired ? "In Apple Home eingebunden (HAP over BLE)" : "Bereit für Apple Home Kopplung"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if let hk = homeKitData {
                                    if let room = hk.roomName {
                                        HStack {
                                            Label("Apple Home Raum", systemImage: "door.left.hand.open")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(room)
                                                .font(.subheadline.weight(.medium))
                                        }
                                    }

                                    if let floor = hk.floorName {
                                        HStack {
                                            Label("Etage / Zone", systemImage: "stairs")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(floor)
                                                .font(.subheadline.weight(.medium))
                                        }
                                    }

                                    HStack {
                                        Label("Status", systemImage: hk.isReachable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundColor(hk.isReachable ? .green : .secondary)
                                        Spacer()
                                        Text(hk.isReachable ? "Erreichbar" : "Nicht erreichbar")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(hk.isReachable ? .green : .secondary)
                                    }

                                    // Decrypted live measurements from Apple HomeKit
                                    if hk.temperature != nil || hk.humidity != nil || hk.batteryLevel != nil {
                                        Divider()

                                        Text("Entschlüsselte Live-Messwerte (Apple Home):")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)

                                        HStack(spacing: 8) {
                                            if let t = hk.temperature {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "thermometer.medium")
                                                        .foregroundColor(.orange)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text("TEMP")
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundColor(.secondary)
                                                        Text(String(format: "%.1f °C", t))
                                                            .font(.subheadline.bold())
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(Color(.tertiarySystemFill))
                                                .cornerRadius(8)
                                            }

                                            if let h = hk.humidity {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "humidity.fill")
                                                        .foregroundColor(.teal)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text("FEUCHTE")
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundColor(.secondary)
                                                        Text(String(format: "%.0f %%", h))
                                                            .font(.subheadline.bold())
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(Color(.tertiarySystemFill))
                                                .cornerRadius(8)
                                            }

                                            if let b = hk.batteryLevel {
                                                HStack(spacing: 6) {
                                                    Image(systemName: b > 20 ? "battery.100" : "battery.25")
                                                        .foregroundColor(b > 20 ? .green : .red)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text("BATTERIE")
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundColor(.secondary)
                                                        Text("\(b) %")
                                                            .font(.subheadline.bold())
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(Color(.tertiarySystemFill))
                                                .cornerRadius(8)
                                            }
                                        }
                                    }

                                    if hk.isSwitchable {
                                        Divider()

                                        HStack {
                                            Label("Schaltzustand", systemImage: hk.isPowerOn == true ? "power.circle.fill" : "power.circle")
                                                .font(.subheadline)
                                                .foregroundColor(hk.isPowerOn == true ? .green : .secondary)
                                            Spacer()
                                            Button(hk.isPowerOn == true ? "Ausschalten" : "Einschalten") {
                                                Task {
                                                    await scannerVM.toggleHomeKitPower(for: hk.id)
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(hk.isPowerOn == true ? .red : .green)
                                            .controlSize(.small)
                                        }
                                    }
                                } else {
                                    Text("Dieses Gerät kommuniziert über das verschlüsselte Apple HomeKit Accessory Protocol (HAP). Die Sensorwerte (Temperatur & Feuchtigkeit) werden kryptografisch geschützt übertragen.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)

                                    Divider()

                                    HStack {
                                        Label("Verschlüsselung", systemImage: device.isHomeKitPaired ? "lock.fill" : "lock.open.fill")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(device.isHomeKitPaired ? "Aktiv (ChaCha20-Poly1305)" : "Keine")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(device.isHomeKitPaired ? .orange : .blue)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text("Apple Home")
                        } footer: {
                            if homeKitData != nil {
                                Text("Messwerte werden live über das Apple HomeKit Framework (HMHomeManager) von iOS synchronisiert und entschlüsselt.")
                            } else {
                                Text("Über die Apple HomeKit Integration kann mHomeNode die Live-Messwerte direkt und entschlüsselt über das HomeKit-Framework (HMHomeManager) von iOS synchronisieren.")
                            }
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
                            ForEach(scannerVM.roomManagementService.rooms) { room in
                                if room.icon.isSFSymbolName {
                                    Label(room.name, systemImage: room.icon)
                                        .tag(room.name)
                                } else {
                                    Text("\(room.icon) \(room.name)")
                                        .tag(room.name)
                                }
                            }
                            ForEach(scannerVM.serverRooms.filter { sr in
                                !scannerVM.roomManagementService.rooms.contains(where: { $0.name.lowercased() == sr.name.lowercased() })
                            }) { sRoom in
                                Text("\(sRoom.icon ?? "🏠") \(sRoom.name)")
                                    .tag(sRoom.name)
                            }
                            if !selectedRoom.isEmpty &&
                               !scannerVM.roomManagementService.rooms.contains(where: { $0.name.lowercased() == selectedRoom.lowercased() }) &&
                               !scannerVM.serverRooms.contains(where: { $0.name.lowercased() == selectedRoom.lowercased() }) {
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

                    // MARK: - Wi-Fi & LAN Settings (for Shellys & Network Plugs)
                    if device.isSwitchablePlug || device.family == .shellyBlu {
                        Section {
                            HStack {
                                Text("IP / Host")
                                    .frame(width: 80, alignment: .leading)
                                TextField("192.168.178.xx oder .local", text: $lanAddressInput)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    #if canImport(UIKit)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    #endif
                            }

                            let resolved = scannerVM.shellyController.lanDiscovery.lookupHost(macAddress: device.macAddress, name: device.name)
                            if let res = resolved, !res.isEmpty, lanAddressInput != res {
                                HStack {
                                    Text("Discovered via mDNS:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(res)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.blue)
                                    Button("Use") {
                                        lanAddressInput = res
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption.bold())
                                }
                            }

                            Button {
                                testLANConnection(device: device)
                            } label: {
                                HStack {
                                    Label("Test LAN Connection", systemImage: "network")
                                        .fontWeight(.medium)
                                    Spacer()
                                    if isTestingLAN {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                            }
                            .disabled(isTestingLAN || (lanAddressInput.isEmpty && resolved == nil))

                            if let testRes = lanTestResult {
                                Text(testRes)
                                    .font(.caption)
                                    .foregroundColor(testRes.contains("Reachable") ? .green : .orange)
                            }
                        } header: {
                            Text("Wi-Fi & LAN Settings")
                        } footer: {
                            Text("When connected to your local home network, commands are sent directly via HTTP RPC over Wi-Fi, bypassing Bluetooth distance limits.")
                        }
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
                    } else if let hk = homeKitData, (hk.temperature != nil || hk.humidity != nil || hk.batteryLevel != nil) {
                        Section("Sensor Telemetry (Apple HomeKit)") {
                            if let temp = hk.temperature {
                                LabeledContent("Temperature", value: String(format: "%.2f °C", temp))
                            }
                            if let hum = hk.humidity {
                                LabeledContent("Humidity", value: String(format: "%.1f %%", hum))
                            }
                            if let battery = hk.batteryLevel {
                                LabeledContent("Battery", value: "\(battery) %")
                            }
                            LabeledContent("Source", value: "Apple HomeKit (Decrypted HAP)")
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
                                // Status banner
                                HStack(spacing: 8) {
                                    Image(systemName: info.isProtected ? "lock.shield.fill" : (info.modelNumber != nil ? "checkmark.circle.fill" : "info.circle.fill"))
                                        .foregroundColor(info.isProtected ? .orange : (info.modelNumber != nil ? .green : .blue))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(info.statusSummary ?? "Inspection Completed")
                                            .font(.subheadline.weight(.semibold))
                                        Text(info.inspectedAt.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)

                                // Standard Device Information rows
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
                                if let sw = info.softwareRevision {
                                    LabeledContent("Software Revision", value: sw)
                                }
                                if let serial = info.serialNumber {
                                    LabeledContent("Serial Number", value: serial)
                                }
                                if let bat = info.batteryLevel {
                                    LabeledContent("GATT Battery Level", value: "\(bat)%")
                                }

                                // Discovered GATT Services Explorer
                                if !info.discoveredServices.isEmpty {
                                    DisclosureGroup("Discovered GATT Services (\(info.discoveredServices.count))") {
                                        ForEach(info.discoveredServices) { s in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(s.name ?? "Service")
                                                        .font(.subheadline.bold())
                                                    Spacer()
                                                    Text(s.uuid)
                                                        .font(.system(.caption2, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                }
                                                if s.characteristics.isEmpty {
                                                    Text("No characteristics found")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                } else {
                                                    ForEach(s.characteristics) { c in
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            HStack {
                                                                Text(c.name ?? c.uuid)
                                                                    .font(.caption.weight(.medium))
                                                                Spacer()
                                                                Text(c.properties.joined(separator: ", "))
                                                                    .font(.caption2)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            if let val = c.valueText {
                                                                Text(val)
                                                                    .font(.system(.caption, design: .monospaced))
                                                                    .foregroundColor(.blue)
                                                            } else if let hex = c.valueHex {
                                                                Text("0x\(hex)")
                                                                    .font(.system(.caption2, design: .monospaced))
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            if let err = c.error {
                                                                Text(err)
                                                                    .font(.caption2)
                                                                    .foregroundColor(.orange)
                                                            }
                                                        }
                                                        .padding(.leading, 8)
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                }
                            }

                            if scannerVM.isInspecting {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Connecting & exploring GATT services...")
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
                                        device.inspectionInfo == nil ? "Inspect Device (Read GATT Services)" : "Re-inspect Device",
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

                            if device.rssi < -75 {
                                Label("Signal is weak (\(device.rssi) dBm). Move within 1–2 meters of the device for a stable connection.", systemImage: "antenna.radiowaves.left.and.right.slash")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if device.isHomeKitAccessory {
                                Label("Tipp: Wenn der Sensor im Thread-Mesh arbeitet oder schläft, drücke kurz die Taste am Sensor, um die BLE-Schnittstelle für die Inspektion aufzuwecken.", systemImage: "info.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Text("Active GATT Deep Inspection")
                        } footer: {
                            Text("Establishes a temporary connection to inspect standard and proprietary GATT services, models, and capabilities.")
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
                    lanAddressInput = device.lanAddress ?? ""
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

    private func testLANConnection(device: DiscoveredDevice) {
        let host = lanAddressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? scannerVM.shellyController.lanDiscovery.lookupHost(macAddress: device.macAddress, name: device.name)
            : lanAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let targetHost = host, !targetHost.isEmpty else {
            lanTestResult = "No IP or hostname specified"
            return
        }

        isTestingLAN = true
        lanTestResult = nil

        Task {
            let reachable = await scannerVM.shellyController.lanClient.probe(host: targetHost)
            await MainActor.run {
                self.isTestingLAN = false
                self.lanTestResult = reachable
                    ? "✅ Reachable at \(targetHost)"
                    : "⚠️ No response from \(targetHost). Ensure you are connected to the same Wi-Fi."
            }
        }
    }

    private func saveAndSync(device: DiscoveredDevice) {
        isSaving = true
        syncStatusMessage = nil

        let trimmedName = customNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmedName.isEmpty ? nil : trimmedName
        let newRoom = selectedRoom.isEmpty ? nil : selectedRoom
        let trimmedLan = lanAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLan = trimmedLan.isEmpty ? nil : trimmedLan

        scannerVM.updateDeviceLANAddress(id: device.id, lanAddress: newLan)

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
