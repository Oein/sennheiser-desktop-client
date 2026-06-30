import Foundation
import IOBluetooth

/// Connects with raw-frame logging enabled, fires a battery of ANC/feature queries,
/// then keeps the link open so you can physically toggle ANC on the headset and watch
/// the notification frames the device emits. Run: `ZenControl --sniff`.
func runSniff() {
    let client = SennheiserClient()
    client.debug = true
    guard let dev = SennheiserClient.candidateDevices().first else {
        print("No paired Sennheiser device found."); return
    }
    print("Connecting to \(dev.name ?? "device")… (raw frame log)")
    client.connect(to: dev)

    // After the link is up, probe a range of ANC-related commands.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        print("\n-- explicit queries --")
        client.send(vendor: GAIA.vendorQualcomm, 0x0001)   // Core: GetSupportedFeatures
        client.send(0x1A01)                                 // ANC mode get
        client.send(0x1A05)                                 // ANC on/off get
        client.send(0x1A03)                                 // transparency level get
        print("\n>>> Now toggle ANC / transparency on the headphones; watch '<<' lines. <<<\n")
    }

    // Keep running ~20s to capture user-initiated notifications.
    RunLoop.main.run(until: Date().addingTimeInterval(20))
    print("\n(sniff done)")
}
