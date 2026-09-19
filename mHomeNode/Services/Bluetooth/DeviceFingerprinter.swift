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

                // 2. Check for Xiaomi / MiBeacon in Service Data (0xFE95)
                if uuidStr.contains("FE95") {
                    if let mi = MiBeaconParser.parse(data: data) {
                        return DeviceIdentificationResult(
                            family: .xiaomi,
                            btHomeData: mi.toBTHomeData(),
                            resolvedName: mi.modelName,
                            macAddress: mi.macAddress
                        )
                    } else {
                        return DeviceIdentificationResult(
                            family: .xiaomi,
                            btHomeData: nil,
                            resolvedName: "Xiaomi Mijia Sensor",
                            macAddress: nil
                        )
                    }
                }

                // 3. Check for BTHome V2 in Service Data (0xFCD2)
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

        // 6. Identify Xiaomi / Mijia / LYWSD sensors by name
        if lowerName.contains("mj_ht") || lowerName.contains("lywsd") || lowerName.contains("mijia") {
            let resolved = lowerName.contains("01zm") || lowerName.contains("mj_ht_v1") || lowerName.contains("lywsdcgq")
                ? "Xiaomi Mijia Temp & RH (LYWSDCGQ)"
                : (lowerName.contains("lywsd03") ? "Xiaomi Mijia Temp & RH (LYWSD03MMC)" : (name.isEmpty ? "Xiaomi Mijia Sensor" : name))
            return DeviceIdentificationResult(
                family: .xiaomi,
                btHomeData: parsedBTHome,
                resolvedName: resolved,
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

        // 10. Identify Apple Devices (Mac, iPad, iPhone, HomePod, AirTags, Continuity)
        if lowerName.contains("macbook") || lowerName.contains("imac") || lowerName.contains("mac mini") || lowerName.contains("mac studio") || lowerName.contains("iphone") || lowerName.contains("ipad") || lowerName.contains("apple watch") || lowerName.contains("airpods") {
            return DeviceIdentificationResult(
                family: .apple,
                btHomeData: nil,
                resolvedName: name,
                macAddress: resolvedMac
            )
        }
        if lowerName.contains("find my") || lowerName.contains("airtag") {
            return DeviceIdentificationResult(
                family: .apple,
                btHomeData: nil,
                resolvedName: name.isEmpty ? "Find My Accessory" : name,
                macAddress: resolvedMac
            )
        }

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

            // 11. Identify Samsung / SmartThings (Company ID 0x0075)
            if mfgId == 0x0075 {
                var samsungName = "Samsung Smart Device"
                if lowerName.contains("washer") {
                    samsungName = "Samsung Smart Washer"
                } else if lowerName.contains("fridge") {
                    samsungName = "Samsung Smart Refrigerator"
                } else if lowerName.contains("tv") || lowerName.contains("crystal") || lowerName.contains("qled") || lowerName.contains("uhd") {
                    samsungName = name.isEmpty ? "Samsung Smart TV" : name
                } else if !name.isEmpty && name != "Unknown" {
                    samsungName = "Samsung (\(name))"
                } else if mfg.count >= 4 && mfg[2] == 0x42 && mfg[3] == 0x04 {
                    samsungName = "Samsung SmartThings Device"
                }
                return DeviceIdentificationResult(
                    family: .samsung,
                    btHomeData: parsedBTHome,
                    resolvedName: samsungName,
                    macAddress: resolvedMac
                )
            }

            // 12. Identify Microsoft Windows PCs (Company ID 0x0006)
            if mfgId == 0x0006 {
                let msftName: String
                if mfg.count >= 4 && mfg[2] == 0x01 && mfg[3] == 0x09 {
                    msftName = "Windows PC (Swift Pair)"
                } else if !name.isEmpty && name != "Unknown" {
                    msftName = "Microsoft Device (\(name))"
                } else {
                    msftName = "Microsoft Windows Device"
                }
                return DeviceIdentificationResult(
                    family: .microsoft,
                    btHomeData: parsedBTHome,
                    resolvedName: msftName,
                    macAddress: resolvedMac
                )
            }

            // 13. Identify ELK-BLEDDM / Elk Products (Company ID 0x0642)
            if mfgId == 0x0642 {
                return DeviceIdentificationResult(
                    family: .smartLight,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "ELK-BLEDDM LED Controller" : name,
                    macAddress: resolvedMac
                )
            }

            // 14. Identify JBL / Harman Audio (Company ID 0x2982)
            if mfgId == 0x2982 {
                return DeviceIdentificationResult(
                    family: .audio,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "JBL Audio Device" : name,
                    macAddress: resolvedMac
                )
            }

            // 15. Identify RuuviTag Environmental Sensors (Company ID 0x0499)
            if mfgId == 0x0499 {
                var ruuviBTHome = parsedBTHome
                var ruuviMac = resolvedMac
                // Ruuvi Format 5 (RAWv2)
                if mfg.count >= 16 && mfg[2] == 0x05 {
                    let tempRaw = (Int16(mfg[3]) << 8) | Int16(mfg[4])
                    let humRaw = (UInt16(mfg[5]) << 8) | UInt16(mfg[6])
                    let pressRaw = (UInt16(mfg[7]) << 8) | UInt16(mfg[8])
                    let powerRaw = (UInt16(mfg[15]) << 8) | UInt16(mfg[16])

                    let tempC = Double(tempRaw) * 0.005
                    let humPct = Double(humRaw) * 0.0025
                    let pressHpa = (Double(pressRaw) + 50000.0) / 100.0
                    let batteryMv = Int((powerRaw >> 5) + 1600)
                    let batPct = UInt8(min(100, max(0, Int((Double(batteryMv) - 2200.0) / (3000.0 - 2200.0) * 100.0))))

                    ruuviBTHome = BTHomeData(
                        battery: batPct,
                        temperature: (tempC >= -40.0 && tempC <= 85.0) ? tempC : nil,
                        humidity: (humPct >= 0 && humPct <= 100) ? humPct : nil,
                        pressure: (pressHpa >= 500 && pressHpa <= 1200) ? pressHpa : nil
                    )

                    if mfg.count >= 24 {
                        let macBytes = Array(mfg[18...23])
                        ruuviMac = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
                    }
                }
                return DeviceIdentificationResult(
                    family: .ruuvi,
                    btHomeData: ruuviBTHome,
                    resolvedName: name.isEmpty ? "RuuviTag Sensor" : name,
                    macAddress: ruuviMac
                )
            }

            // 16. Identify Google (Company ID 0x00E0)
            if mfgId == 0x00E0 {
                let googleName = name.isEmpty ? "Google Device" : name
                return DeviceIdentificationResult(
                    family: .google,
                    btHomeData: parsedBTHome,
                    resolvedName: googleName,
                    macAddress: resolvedMac
                )
            }

            // 17. Identify Sony (Company ID 0x0046)
            if mfgId == 0x0046 {
                let isSonyAudio = lowerName.contains("wh-") || lowerName.contains("wf-") || lowerName.contains("srs-") || lowerName.contains("head")
                let sonyName = isSonyAudio ? (name.isEmpty ? "Sony Audio Device" : name) : (name.isEmpty ? "Sony Device" : name)
                return DeviceIdentificationResult(
                    family: isSonyAudio ? .audio : .sony,
                    btHomeData: parsedBTHome,
                    resolvedName: sonyName,
                    macAddress: resolvedMac
                )
            }

            // 18. Identify Bose (Company ID 0x009E)
            if mfgId == 0x009E {
                return DeviceIdentificationResult(
                    family: .audio,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "Bose Audio Device" : name,
                    macAddress: resolvedMac
                )
            }

            // 19. Identify Garmin (Company ID 0x0087)
            if mfgId == 0x0087 {
                return DeviceIdentificationResult(
                    family: .garmin,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "Garmin Device" : name,
                    macAddress: resolvedMac
                )
            }

            // 20. Identify Xiaomi / Huami (Company ID 0x0157 or 0x038F)
            if mfgId == 0x0157 || mfgId == 0x038F {
                return DeviceIdentificationResult(
                    family: .xiaomi,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "Xiaomi / Huami Device" : name,
                    macAddress: resolvedMac
                )
            }

            // 21. Identify Govee / Intellirocks (Company ID 0xEC88)
            if mfgId == 0xEC88 {
                return DeviceIdentificationResult(
                    family: .govee,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "Govee Smart Device" : name,
                    macAddress: resolvedMac
                )
            }

            // 22. Identify Nordic Semiconductor (Company ID 0x0059)
            if mfgId == 0x0059 {
                return DeviceIdentificationResult(
                    family: .nordic,
                    btHomeData: parsedBTHome,
                    resolvedName: name.isEmpty ? "Nordic nRF Device" : name,
                    macAddress: resolvedMac
                )
            }
        }

        // 15. Identify Smart Light controllers by name
        if lowerName.contains("elk-ble") || lowerName.contains("bleddm") || lowerName.contains("triones") || lowerName.contains("lednet") || lowerName.contains("melpo") || lowerName.contains("rgb_light") {
            return DeviceIdentificationResult(
                family: .smartLight,
                btHomeData: parsedBTHome,
                resolvedName: name.isEmpty ? "RGB LED Controller" : name,
                macAddress: resolvedMac
            )
        }

        // 16. Identify Audio Devices by name or Airoha BLE service
        let isAirohaService = serviceUUIDs?.contains { $0.uuidString.uppercased().contains("5052494D") } ?? false
        if lowerName.starts(with: "jbl") || lowerName.contains("sony") || lowerName.contains("bose") || lowerName.contains("sennheiser") || lowerName.contains("beats") || isAirohaService {
            return DeviceIdentificationResult(
                family: .audio,
                btHomeData: parsedBTHome,
                resolvedName: name.isEmpty ? "Wireless Audio Device" : name,
                macAddress: resolvedMac
            )
        }

        // 17. Identify Tuya / Telink (OUI A4:C1:38 and/or Service 0xFFF0)
        let hasTuyaService = serviceUUIDs?.contains { $0.uuidString.uppercased().contains("FFF0") } ?? false
        let isTelinkMfg = manufacturerData.map { m in
            m.count >= 6 && m[0] == 0xA4 && m[1] == 0xC1 && m[2] == 0x38
        } ?? false

        if isTelinkMfg || (hasTuyaService && lowerName.contains("tuya")) || (hasTuyaService && isTelinkMfg) {
            let tuyaMac = (manufacturerData != nil && manufacturerData!.count >= 6)
                ? manufacturerData![0..<6].map { String(format: "%02X", $0) }.joined(separator: ":")
                : resolvedMac
            return DeviceIdentificationResult(
                family: .tuya,
                btHomeData: parsedBTHome,
                resolvedName: name.isEmpty || name == "Unknown" ? "Tuya / Telink Smart Device" : name,
                macAddress: tuyaMac
            )
        }

        // 18. Check Service UUIDs for hints
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
                if uuidStr.contains("FE2C") {
                    return DeviceIdentificationResult(
                        family: .google,
                        btHomeData: parsedBTHome,
                        resolvedName: resolvedName ?? "Google Fast Pair Device",
                        macAddress: resolvedMac
                    )
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
