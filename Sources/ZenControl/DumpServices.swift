import Foundation
import IOBluetooth

/// Lists every SDP service record (name, RFCOMM channel, service-class UUIDs) of
/// each paired Sennheiser device — used to discover which channel carries GAIA.
func dumpServices() {
    let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    let targets = paired.filter { ($0.name ?? "").uppercased().contains("ACCENTUM")
        || ($0.name ?? "").uppercased().contains("MOMENTUM")
        || ($0.name ?? "").uppercased().contains("SENNHEISER") }

    for dev in targets {
        print("Device: \(dev.name ?? "?")  [\(dev.addressString ?? "?")]")
        _ = dev.performSDPQuery(nil)
        // performSDPQuery is async; wait briefly for the cache to populate.
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))

        guard let records = dev.services as? [IOBluetoothSDPServiceRecord], !records.isEmpty else {
            print("  (no SDP records)")
            continue
        }
        for rec in records {
            var channel: BluetoothRFCOMMChannelID = 0
            let hasRFCOMM = rec.getRFCOMMChannelID(&channel) == kIOReturnSuccess
            let name = rec.getServiceName() ?? "(unnamed)"
            var uuids: [String] = []
            if let attr = rec.getAttributeDataElement(0x0001), // ServiceClassIDList
               let list = attr.getArrayValue() as? [IOBluetoothSDPDataElement] {
                for e in list {
                    if let u = e.getUUIDValue() { uuids.append(u.description) }
                }
            }
            print(String(format: "  • %-26@  rfcomm=%@  uuids=[%@]",
                         name as NSString,
                         hasRFCOMM ? "\(channel)" : "—",
                         uuids.joined(separator: ", ") as NSString))
        }
        print("")
    }
}
