import Foundation
import CoreBluetooth

public enum DeviceFingerprinter {
    public static func identify(
        advertisedName: String?,
        serviceUUIDs: [CBUUID]?,
        serviceData: [CBUUID: Data]?,
        manufacturerData: Data?
    ) -> (family: DeviceFamily, btHomeData: BTHomeData?) {
        let name = advertisedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parsedBTHome: BTHomeData?

        // Check for BTHome V2 in Service Data (0xFCD2)
        if let serviceData = serviceData {
            for (uuid, data) in serviceData {
                let uuidStr = uuid.uuidString.uppercased()
                if uuidStr.contains("FCD2") {
                    parsedBTHome = BTHomeParser.parseV2(data: data)
                    break
                }
            }
        }

        // Identify Shelly BLU devices
        if name.lowercased().starts(with: "shelly") || name.lowercased().contains("blu") {
            return (.shellyBlu, parsedBTHome)
        }

        // Identify QingPing / ClearGrass devices
        if name.lowercased().contains("qingping") || name.lowercased().contains("cleargrass") || name.lowercased().contains("cgg1") {
            return (.qingping, parsedBTHome)
        }

        if let serviceUUIDs = serviceUUIDs {
            for uuid in serviceUUIDs {
                let uuidStr = uuid.uuidString.uppercased()
                if uuidStr.contains("FDCD") {
                    // Qingping service UUID
                    return (.qingping, parsedBTHome)
                }
                if uuidStr.contains("FCD2") {
                    return (.btHomeGeneric, parsedBTHome)
                }
            }
        }

        if parsedBTHome != nil {
            return (.btHomeGeneric, parsedBTHome)
        }

        return (.standardBLE, nil)
    }
}
