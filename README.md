# mHomeNode

> Native iOS & macOS companion app for [homenodes.io](https://homenodes.io) — BLE scanner, BTHome sensor decoder, and HomeNode server bridge.

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat&logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](https://developer.apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Overview

**mHomeNode** connects your Apple devices with the HomeNode smart home ecosystem. It serves as both a standalone Bluetooth Low Energy (BLE) sensor monitor and a gateway scout that can claim and forward sensor data to a central **HomeNode Server**.

With native support for the open [BTHome](https://bthome.io/) protocol, `mHomeNode` decodes broadcasted advertisement data from low-power smart home sensors without pairing or cloud dependencies.

---

## Features

- 📡 **BLE Scout / Scanner**
  - Real-time scanning for nearby Bluetooth Low Energy devices using `CoreBluetooth`.
  - Device discovery and automatic fingerprinting.
  - Signal strength visualization (RSSI signal bars and historical tracking).
  - Filter devices by name, service UUID, or device family.

- 🌡️ **BTHome V1 & V2 Protocol Decoder**
  - Parses unencrypted BTHome V2 service data (`0xFCD2`).
  - Decodes live telemetry metrics:
    - Temperature (°C)
    - Relative Humidity (%)
    - Atmospheric Pressure (hPa)
    - Illuminance (lux)
    - Battery percentage & voltage
    - Door / Window contact states (open/closed)
    - Motion detection
    - Button press events (single, double, triple, long press)
    - Rotation angle (degrees)

- 🏷️ **Device Fingerprinting**
  - Automatically identifies device families:
    - **Shelly BLU** (Door/Window, Motion, Button, etc.)
    - **QingPing / ClearGrass** (Temp & RH monitors)
    - **Generic BTHome devices**
    - **Standard BLE peripherals**

- 🖥️ **HomeNode Server Integration**
  - Connects to a local or remote HomeNode server via REST API.
  - Health check monitor: displays server uptime, version, active Matter nodes, and BLE gateway counts.
  - Device claiming & synchronization (`/api/v1/devices/claim`).
  - Configurable endpoints with optional TLS and Bearer token authentication.

- 🎨 **Modern SwiftUI Interface**
  - Adaptive design supporting both iOS and macOS.
  - Detail inspection with raw hex payloads, advertisement data, and assigned room management.

---

## Supported Hardware & Devices

| Device Family | Protocols / Services | Supported Telemetry |
| :--- | :--- | :--- |
| **Shelly BLU** | BTHome V2 (`0xFCD2`) | Motion, Contact, Button presses, Battery |
| **QingPing / ClearGrass** | BLE Broadcast (`0xFDCD`) | Temperature, Humidity, Battery |
| **BTHome V1 / V2** | BTHome Standard (`0xFCD2`, `0x181C`) | Temperature, Humidity, Pressure, Lux, Motion, Contact |
| **Standard BLE** | Generic Bluetooth LE | RSSI, Advertised Services, Manufacturer Data |

---

## Project Structure

```text
mHomeNode/
├── mHomeNode/
│   ├── mHomeNodeApp.swift                # Application entry point
│   ├── Models/
│   │   ├── BTHomeData.swift              # BTHome payload model & button events
│   │   ├── DiscoveredDevice.swift        # Discovered device & family enum
│   │   └── ServerConfig.swift            # HomeNode server connection settings
│   ├── Services/
│   │   ├── Bluetooth/
│   │   │   ├── BLEScannerService.swift   # CoreBluetooth central manager wrapper
│   │   │   ├── BTHomeParser.swift        # BTHome binary payload decoder
│   │   │   └── DeviceFingerprinter.swift # Device brand & family identification
│   │   └── Server/
│   │       └── HomeNodeServerClient.swift# HomeNode REST API client (live & mock)
│   ├── ViewModels/
│   │   └── ScannerViewModel.swift        # Scanner and server orchestration view model
│   ├── Views/
│   │   ├── ContentView.swift             # Main tab view navigation
│   │   ├── Components/
│   │   │   ├── SensorMetricBadge.swift   # Sensor value display card
│   │   │   └── SignalStrengthView.swift  # RSSI signal bars component
│   │   ├── Scanner/
│   │   │   ├── DeviceDetailView.swift    # Device details and raw packet inspector
│   │   │   ├── DeviceRowView.swift       # List item view with live metrics
│   │   │   └── ScannerView.swift         # Main scanner list view & controls
│   │   └── Server/
│   │       └── ServerStatusView.swift    # Server settings & connection status
│   ├── Assets.xcassets                   # App icons and color assets
│   └── Info.plist                        # App permissions (Bluetooth peripheral usage)
└── mHomeNodeTests/
    ├── BTHomeParserTests.swift           # Unit tests for BTHome payload parsing
    └── DeviceFingerprinterTests.swift    # Unit tests for device identification
```

---

## Requirements

- **macOS** 14.0+ / **iOS** 17.0+
- **Xcode** 16.0+
- **Swift** 6.0+
- Bluetooth LE enabled device

---

## Getting Started

### 1. Clone the repository

```bash
git clone git@github.com:zehrer/mHomeNode.git
cd mHomeNode
```

### 2. Open in Xcode

```bash
open mHomeNode.xcodeproj
```

### 3. Build & Run

Select your target run destination (Mac or iOS Simulator/Device) and press **⌘ + R** to run.

> **Note**: Scanning for live BLE peripherals requires running on physical iOS hardware or a Mac with Bluetooth permissions enabled in System Settings.

---

## Testing

Unit tests cover the BTHome payload parser and device fingerprinting logic:

```bash
xcodebuild test \
  -scheme mHomeNode \
  -destination 'platform=macOS'
```

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
