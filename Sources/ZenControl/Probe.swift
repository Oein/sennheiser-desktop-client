import Foundation
import IOBluetooth

/// Headless end-to-end check: connect to the first paired Sennheiser device over
/// RFCOMM/GAIA, query its state, print it, and exit. Used to validate the protocol
/// against real hardware.
func runProbe() {
    let client = SennheiserClient()
    let candidates = SennheiserClient.candidateDevices()
    guard let dev = candidates.first else {
        print("No paired Sennheiser device found.")
        return
    }
    print("Connecting to \(dev.name ?? dev.addressString ?? "device")…")

    var printed = false
    func dump() {
        guard client.isConnected else { return }
        print("""

        ── \(client.modelId.isEmpty ? client.deviceName : client.modelId) ──
        firmware     : \(client.firmware.isEmpty ? "—" : client.firmware)
        battery      : \(client.battery.map { "\($0)%" } ?? "—")
        codec        : \(client.codec)
        noise mode   : \(client.noise.active.rawValue)
          anc on     : \(client.noise.ancOn.map(String.init) ?? "—")
          transparency: \(client.noise.transparencyOn.map(String.init) ?? "—") (level \(client.noise.transparencyLevel))
        smart pause  : \(client.smartPause.map { $0 ? "on" : "off" } ?? "—")
        on-head det. : \(client.onHead.map { $0 ? "on" : "off" } ?? "—")
        """)
    }

    client.onChange = {
        if !client.lastError.isEmpty { print("error: \(client.lastError)") }
    }
    client.connect(to: dev)

    // Give the device time to answer, then dump and quit.
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        dump()
        printed = true
        CFRunLoopStop(CFRunLoopGetMain())
    }
    let deadline = Date().addingTimeInterval(6)
    while !printed && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }
    if !client.isConnected { print("Did not connect (\(client.lastError.isEmpty ? "timeout" : client.lastError)).") }
}
