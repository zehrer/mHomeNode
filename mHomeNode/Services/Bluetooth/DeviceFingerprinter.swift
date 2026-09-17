import Foundation
import CoreBluetooth

public struct DeviceIdentificationResult: Sendable {
    public let family: DeviceFamily
    public let btHomeData: BTHomeData?
    public let resolvedName: String?
    public let macAddress: String?

    public init(
        family: DeviceFamily,
        btHomeData: BTHomeData? = nil,
        resolvedName: String? = nil,
        macAddress: String? = nil
    ) {
        self.family = family
        self.btHomeData = btHomeData
        self.resolvedName = resolvedName
        self.macAddress = macAddress
    }
}

public enum DeviceFingerprinter {
    /// Full identification with sensor telemetry, brand family, model name and hardware MAC (if broadcast)
    public static func identifyDetails(
        advertisedName: String?,
        serviceUUIDs: [CBUUID]?,
        serviceData: [CBUUID: Data]?,
        manufacturerData: Data?
    ) -> DeviceIdentificationResult {
        let name = advertisedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parsedBTHome: BTHomeData?
        var resolvedName: String?
        var resolvedMac: String?
        var family: DeviceFamily = .standardBLE

        // 1. Check for Qingping (UUID 0xFDCD) in Service Data
        if let serviceData = serviceData {
            for (uuid, data) in serviceData {
                let uuidStr = uuid.uuidString.uppercased()
                if uuidStr.contains("FDCD") {
                    if let qp = QingpingParser.parse(data: data) {
                        return DeviceIdentificationResult(
                            family: .qingping,
                            btHomeData: qp.toBTHomeData(),
                            resolvedName: qp.modelName,
                            macAddress: qp.macAddress
                        )
                    } else {
                        return DeviceIdentificationResult(
                            family: .qingping,
                            btHomeData: nil,
                            resolvedName: "Qingping Thermometer",
                            macAddress: nil
                        )
                    }
                }

                // 2. Check for BTHome V2 in Service Data (0xFCD2)
                if uuidStr.contains("FCD2") {
                    parsedBTHome = BTHomeParser.parseV2(data: data)
                    family = .btHomeGeneric
                }
            }
        }

        // 3. Check for Qingping manufacturer ID 0x088B (little endian: [0x8B, 0x08])
        if let mfg = manufacturerData, mfg.count >= 2 {
            let mfgId = UInt16(mfg[0]) | (UInt16(mfg[1]) << 8)
            if mfgId == 0x088B {
                family = .qingping
                resolvedName = "Qingping Device"
                if mfg.count >= 8 {
                    let macSlice = Array(mfg[2...7].reversed())
                    resolvedMac = macSlice.map { String(format: "%02X", $0) }.joined(separator: ":")
                }
            }
        }

        // 4. Identify Shelly BLU devices by name
        let lowerName = name.lowercased()
        if lowerName.starts(with: "shelly") || lowerName.contains("blu") {
            return DeviceIdentificationResult(
                family: .shellyBlu,
                btHomeData: parsedBTHome,
                resolvedName: name.isEmpty ? "Shelly BLU" : name,
                macAddress: nil
            )
        }

        // 5. Identify QingPing / ClearGrass devices by name
        if lowerName.contains("qingping") || lowerName.contains("cleargrass") || lowerName.contains("cgg1") || lowerName.contains("cgdk2") || lowerName.contains("cgd1") {
            return DeviceIdentificationResult(
                family: .qingping,
                btHomeData: parsedBTHome,
                resolvedName: name.isEmpty ? "Qingping Sensor" : name,
                macAddress: resolvedMac
            )
        }

        // 6. Identify SwitchBot via Service Data (0xFD3D) or Service UUIDs
        let hasSwitchBotService = serviceUUIDs?.contains { $0.uuidString.uppercased().contains("FD3D") } ?? false
        let hasSwitchBotData = serviceData?.keys.contains { $0.uuidString.uppercased().contains("FD3D") } ?? false
        if hasSwitchBotService || hasSwitchBotData {
            return DeviceIdentificationResult(
                family: .switchBot,
                btHomeData: parsedBTHome,
                resolvedName: resolvedName ?? "SwitchBot Device",
                macAddress: resolvedMac
            )
        }

        // 7. Identify Nuki Smart Lock
        if lowerName.starts(with: "nuki") {
            return DeviceIdentificationResult(
                family: .nuki,
                btHomeData: nil,
                resolvedName: "Nuki Smart Lock (\(name))",
                macAddress: resolvedMac
            )
        }

        // 8. Identify EcoFlow Power Systems
        if lowerName.starts(with: "ef-") || lowerName.contains("ecoflow") {
            return DeviceIdentificationResult(
                family: .ecoflow,
                btHomeData: nil,
                resolvedName: "EcoFlow Device (\(name))",
                macAddress: resolvedMac
            )
        }

        // 9. Identify Govee Devices (Outdoor lights, thermometers)
        if lowerName.starts(with: "govee") {
            var goveeModel = "Govee Device (\(name))"
            if lowerName.contains("h70b5") {
                goveeModel = "Govee Outdoor Lights (H70B5)"
            } else if lowerName.contains("h70b3") {
                goveeModel = "Govee Outdoor String Lights (H70B3)"
            } else if lowerName.contains("h5075") || lowerName.contains("h5074") {
                goveeModel = "Govee Thermo-Hygrometer"
            }
            return DeviceIdentificationResult(
                family: .govee,
                btHomeData: parsedBTHome,
                resolvedName: goveeModel,
                macAddress: resolvedMac
            )
        }

        // 10. Identify Apple Devices (HomePod, AirTags, Continuity)
        if let mfg = manufacturerData, mfg.count >= 2 {
            let mfgId = UInt16(mfg[0]) | (UInt16(mfg[1]) << 8)
            if mfgId == 0x004C {
                var appleName = resolvedName ?? (name.isEmpty ? "Apple Device" : name)
                if mfg.count >= 3 && mfg[2] == 0x12 {
                    appleName = name.isEmpty ? "Find My / AirTag" : name
                } else if lowerName.contains("homepod") {
                    appleName = name
                } else if lowerName.contains("watch") {
                    appleName = "Apple Watch (\(name))"
                }
                return DeviceIdentificationResult(
                    family: .apple,
                    btHomeData: nil,
                    resolvedName: appleName,
                    macAddress: resolvedMac
                )
            }
        }

        // 11. Check Service UUIDs for hints
        if let serviceUUIDs = serviceUUIDs {
            for uuid in serviceUUIDs {
                let uuidStr = uuid.uuidString.uppercased()
                if uuidStr.contains("FDCD") {
                    return DeviceIdentificationResult(
                        family: .qingping,
                        btHomeData: parsedBTHome,
                        resolvedName: resolvedName ?? "Qingping Sensor",
                        macAddress: resolvedMac
                    )
                }
                if uuidStr.contains("FCD2") {
                    family = .btHomeGeneric
                }
            }
        }

        if parsedBTHome != nil {
            return DeviceIdentificationResult(
                family: family == .standardBLE ? .btHomeGeneric : family,
                btHomeData: parsedBTHome,
                resolvedName: resolvedName,
                macAddress: resolvedMac
            )
        }

        return DeviceIdentificationResult(
            family: family,
            btHomeData: nil,
            resolvedName: resolvedName,
            macAddress: resolvedMac
        )
    }

    /// Backwards compatible helper returning standard (family, btHomeData)
    public static func identify(
        advertisedName: String?,
        serviceUUIDs: [CBUUID]?,
        serviceData: [CBUUID: Data]?,
        manufacturerData: Data?
    ) -> (family: DeviceFamily, btHomeData: BTHomeData?) {
        let result = identifyDetails(
            advertisedName: advertisedName,
            serviceUUIDs: serviceUUIDs,
            serviceData: serviceData,
            manufacturerData: manufacturerData
        )
        return (result.family, result.btHomeData)
    }
}
