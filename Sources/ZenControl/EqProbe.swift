import Foundation
import IOBluetooth

/// Discovery tool for the Equalizer protocol. Registers every Sennheiser
/// notification feature id (1…20) so the device pushes its current state for each,
/// and logs all inbound frames. Whatever command id carries EQ band data will show
/// up here — read-only and safe. Run `ZenControl --eqprobe` with the device connected.
func runEqProbe() {
    let client = SennheiserClient()
    client.debug = true
    guard let dev = SennheiserClient.candidateDevices().first else {
        print("No paired Sennheiser device found."); return
    }
    print("Connecting to \(dev.name ?? "device")…")
    client.connect(to: dev)

    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        print("\n-- registering notification feature ids 1…20 --")
        for fid in UInt8(1)...20 {
            client.send(SennCmd.registerNotification, [fid])
        }
        print("\n-- candidate EQ GET sweeps --")
        // educated guesses for an EQ get/state command in the Sennheiser range
        for cmd: UInt16 in [0x0A00, 0x0A01, 0x0A02, 0x1000, 0x1001, 0x1100, 0x1101,
                            0x0C00, 0x0C02, 0x1A06, 0x1A07] {
            client.send(cmd)
        }
        print("\n>>> watch the '<<' lines for unknown command ids carrying band/EQ data <<<\n")
    }
    RunLoop.main.run(until: Date().addingTimeInterval(12))
    print("\n(eqprobe done)")
}
