import Foundation
import IOBluetooth

/// Probe how the transparency LEVEL behaves on the real ACCENTUM: turn transparency
/// on, then push several level values via the candidate commands and read them back.
func runTransTest() {
    let client = SennheiserClient()
    client.debug = true
    guard let dev = SennheiserClient.candidateDevices().first else {
        print("No paired Sennheiser device found."); return
    }
    print("Connecting to \(dev.name ?? "device")…")
    client.connect(to: dev)

    var step = 0
    let steps: [(String, () -> Void)] = [
        ("transparency ON (0x1804 01)",        { client.send(0x1804, [1]) }),
        ("read level 0x1A03 / 0x1803",         { client.send(0x1A03); client.send(0x1803) }),
        ("SET level 0x1A02 = 0",               { client.send(0x1A02, [0]) }),
        ("read 0x1A03",                        { client.send(0x1A03) }),
        ("SET level 0x1A02 = 50",              { client.send(0x1A02, [50]) }),
        ("read 0x1A03",                        { client.send(0x1A03) }),
        ("SET level 0x1A02 = 100",             { client.send(0x1A02, [100]) }),
        ("read 0x1A03",                        { client.send(0x1A03) }),
        ("try SET 0x1802 = 30 (alt cmd)",      { client.send(0x1802, [30]) }),
        ("read 0x1803 / 0x1A03",               { client.send(0x1803); client.send(0x1A03) }),
        ("try SET 0x1800 = 1 (mode)",          { client.send(0x1800, [1]) }),
        ("read 0x1801",                        { client.send(0x1801) }),
    ]

    func fire() {
        guard step < steps.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { CFRunLoopStop(CFRunLoopGetMain()) }
            return
        }
        let (label, action) = steps[step]
        print("\n# step \(step): \(label)")
        action()
        step += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: fire)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fire)
    RunLoop.main.run(until: Date().addingTimeInterval(Double(steps.count) * 1.5 + 5))
    print("\n(transtest done)")
}
