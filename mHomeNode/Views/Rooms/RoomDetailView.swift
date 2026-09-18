import SwiftUI

public struct RoomDetailView: View {
    @Bindable var scannerVM: ScannerViewModel
    public let roomName: String
    public let serverRoom: ServerRoom?
    public var onSelectDevice: ((DiscoveredDevice) -> Void)?

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

    private var otherDevices: [DiscoveredDevice] {
        roomDevices.filter { dev in
            !dev.isLightingDevice && dev.btHomeData?.temperature == nil && dev.btHomeData?.humidity == nil
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
                Text(serverRoom?.icon ?? "🏠")
                    .font(.system(size: 38))
                    .frame(width: 58, height: 58)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)

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

            // MARK: - Climate Telemetry Cards (if any)
            if avgTemp != nil || avgHumidity != nil {
                HStack(spacing: 12) {
                    if let temp = avgTemp {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "thermometer.medium")
                                    .foregroundColor(.orange)
                                Text("TEMPERATURE")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                            }
                            Text(String(format: "%.1f°C", temp))
                                .font(.title.bold().monospacedDigit())
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
                    }

                    if let hum = avgHumidity {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "humidity.fill")
                                    .foregroundColor(.teal)
                                Text("HUMIDITY")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                            }
                            Text(String(format: "%.1f%%", hum))
                                .font(.title.bold().monospacedDigit())
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
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

            // MARK: - Climate Sensors Individual Cards
            if !climateDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Sensors (\(climateDevices.count))", systemImage: "sensor.tag.radiowaves.forward.fill")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(climateDevices) { device in
                        Button {
                            onSelectDevice?(device)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 42, height: 42)
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
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
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
                    description: Text("Assign Bluetooth sensors and lights to \(roomName) from the Scout or Lights tabs.")
                )
                .padding(.top, 40)
            }
        }
    }
}
