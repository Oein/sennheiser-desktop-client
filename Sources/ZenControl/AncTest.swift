import Foundation
import IOBluetooth

/// Experiment: drive the candidate ANC/transparency commands one at a time and watch
/// which responses/notifications the real ACCENTUM emits, so we learn the correct
/// control opcodes. Restores ANC-on at the end.
func runAncTest() {
    let client = SennheiserClient()
    client.debug = true
    guard let dev = SennheiserClient.candidateDevices().first else {
        print("No paired Sennheiser device found."); return
    }
    print("Connecting to \(dev.name ?? "device")…")
    client.connect(to: dev)

    var step = 0
    let steps: [(String, () -> Void)] = [
        ("read transparency status 0x1805", { client.send(0x1805) }),
        ("read transparency status 0x1803", { client.send(0x1803) }),
        ("SET ANC off  (0x1A04 00)",        { client.send(0x1A04, [0]) }),
        ("read ANC status 0x1A05",          { client.send(0x1A05) }),
        ("SET ANC on   (0x1A04 01)",        { client.send(0x1A04, [1]) }),
        ("read ANC status 0x1A05",          { client.send(0x1A05) }),
        ("SET transparency on (0x1804 01)", { client.send(0x1804, [1]) }),
        ("read ANC 0x1A05 + transp 0x1805", { client.send(0x1A05); client.send(0x1805) }),
        ("SET transparency off (0x1804 00)",{ client.send(0x1804, [0]) }),
        ("SET ANC on   (0x1A04 01) restore",{ client.send(0x1A04, [1]) }),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: fire)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fire)
    RunLoop.main.run(until: Date().addingTimeInterval(Double(steps.count) * 1.4 + 5))
    print("\n(anctest done)")
}
