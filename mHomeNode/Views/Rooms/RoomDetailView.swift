import SwiftUI

public struct RoomDetailView: View {
    @Bindable var scannerVM: ScannerViewModel
    public let roomName: String
    public let serverRoom: ServerRoom?
    public var onSelectDevice: ((DiscoveredDevice) -> Void)?

    @State private var showSensorsDetail: Bool = false

    public init(
        scannerVM: ScannerViewModel,
        roomName: String,
        serverRoom: ServerRoom?,
        onSelectDevice: ((DiscoveredDevice) -> Void)? = nil
    ) {
        self.scannerVM = scannerVM
        self.roomName = roomName
        self.serverRoom = serverRoom
        self.onSelectDevice = onSelectDevice
    }

    private var roomDevices: [DiscoveredDevice] {
        scannerVM.bleService.devices.filter { dev in
            !dev.isIgnored && dev.assignedRoom == roomName
        }
    }

    private var climateDevices: [DiscoveredDevice] {
        roomDevices.filter { $0.btHomeData?.temperature != nil || $0.btHomeData?.humidity != nil }
    }

    private var lightDevices: [DiscoveredDevice] {
        roomDevices.filter { $0.isLightingDevice }
    }

    private var plugDevices: [DiscoveredDevice] {
        roomDevices.filter { $0.isSwitchablePlug }
    }

    private var otherDevices: [DiscoveredDevice] {
        roomDevices.filter { dev in
            !dev.isLightingDevice && !dev.isSwitchablePlug && dev.btHomeData?.temperature == nil && dev.btHomeData?.humidity == nil
        }
    }

    private var activeClimateDevices: [DiscoveredDevice] {
        climateDevices.filter { !$0.isSignalLost }
    }

    private var avgTemp: Double? {
        let temps = activeClimateDevices.compactMap { $0.btHomeData?.temperature }
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    private var avgHumidity: Double? {
        let hums = activeClimateDevices.compactMap { $0.btHomeData?.humidity }
        guard !hums.isEmpty else { return nil }
        return hums.reduce(0, +) / Double(hums.count)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // MARK: - Room Hero Banner
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
                    RoomIconView(serverRoom?.icon ?? "door.left.hand.open", size: 26, color: .primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(roomName)
                        .font(.title2.bold())
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if let floor = serverRoom?.floor, !floor.isEmpty {
                            Text(floor)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(roomDevices.count) \(roomDevices.count == 1 ? "device" : "devices")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let activeCount = roomDevices.filter { $0.isCurrentlyActive }.count
                        if activeCount > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("\(activeCount) active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal)

            // MARK: - Compact Climate Telemetry Cards (Clickable to reveal/hide sensors)
            if avgTemp != nil || avgHumidity != nil {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showSensorsDetail.toggle()
                    }
                    #if canImport(UIKit)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                } label: {
                    HStack(spacing: 10) {
                        if let temp = avgTemp {
                            HStack(spacing: 8) {
                                Image(systemName: "thermometer.medium")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("TEMP")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f°C", temp))
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundColor(.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
                        }

                        if let hum = avgHumidity {
                            HStack(spacing: 8) {
                                Image(systemName: "humidity.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.teal)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("HUMIDITY")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f%%", hum))
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundColor(.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
                        }

                        // Sensor Expand/Collapse Badge
                        HStack(spacing: 4) {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.caption2)
                            Text("\(climateDevices.count)")
                                .font(.caption2.bold())
                            Image(systemName: showSensorsDetail ? "chevron.up" : "chevron.down")
                                .font(.caption2.bold())
                        }
                        .foregroundColor(showSensorsDetail ? .blue : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .background(showSensorsDetail ? Color.blue.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }

            // MARK: - Climate Sensors Individual Cards (Toggled by Climate Bar)
            if showSensorsDetail && !climateDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Sensors in \(roomName) (\(climateDevices.count))", systemImage: "sensor.tag.radiowaves.forward.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    ForEach(climateDevices) { device in
                        Button {
                            onSelectDevice?(device)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "thermometer.sun")
                                        .foregroundColor(.blue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.displayTitle)
                                        .font(.subheadline.bold())
                                        .foregroundColor(device.isSignalLost ? .secondary : .primary)

                                    HStack(spacing: 6) {
                                        if device.isSignalLost {
                                             HStack(spacing: 2) {
                                                Image(systemName: "wifi.slash")
                                                Text("No signal")
                                            }
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        } else {
                                            HStack(spacing: 2) {
                                                Image(systemName: "clock")
                                                Text(device.measurementAgeText)
                                            }
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                            if let bth = device.btHomeData {
                                                if let t = bth.temperature {
                                                    Text("•")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(String(format: "%.1f°C", t))
                                                        .font(.caption.bold())
                                                        .foregroundColor(.primary)
                                                }
                                                if let h = bth.humidity {
                                                    Text(String(format: "%.0f%%", h))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                if let bat = bth.battery {
                                                    Text("🔋 \(bat)%")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // MARK: - Smart Plugs / Switches Section (Shelly Plugs)
            if !plugDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Plugs & Sockets (\(plugDevices.count))", systemImage: "powerplug.fill")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        if plugDevices.count > 1 {
                            HStack(spacing: 8) {
                                Button("On") {
                                    for dev in plugDevices {
                                        scannerVM.setPlugPower(for: dev, isOn: true)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(.green)

                                Button("Off") {
                                    for dev in plugDevices {
                                        scannerVM.setPlugPower(for: dev, isOn: false)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                            }
                        }
                    }

                    ForEach(plugDevices) { device in
                        PlugDeviceCard(
                            device: device,
                            controller: scannerVM.shellyController,
                            onSelect: {
                                onSelectDevice?(device)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }

            // MARK: - Lights Section
            if !lightDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Lights (\(lightDevices.count))", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        // Room-level Quick Actions
                        HStack(spacing: 8) {
                            Button("On") {
                                for dev in lightDevices {
                                    scannerVM.setLightPower(for: dev, isOn: true)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(.yellow)

                            Button("Off") {
                                for dev in lightDevices {
                                    scannerVM.setLightPower(for: dev, isOn: false)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                    }

                    ForEach(lightDevices) { device in
                        LightDeviceCard(
                            device: device,
                            serverRoom: serverRoom,
                            controller: scannerVM.lightController,
                            onSelect: {
                                onSelectDevice?(device)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }

            // MARK: - Other Devices in Room
            if !otherDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Other Devices (\(otherDevices.count))", systemImage: "cpu")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(otherDevices) { device in
                        Button {
                            onSelectDevice?(device)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.secondary)

                                Text(device.displayTitle)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Empty state if room has no devices
            if roomDevices.isEmpty {
                ContentUnavailableView(
                    "No Devices Assigned",
                    systemImage: "house.circle",
                    description: Text("Assign Bluetooth sensors and lights to \(roomName) from the BLE or Lights tabs.")
                )
                .padding(.top, 40)
            }
        }
    }
}
