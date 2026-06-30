import Foundation

/// Verifies the GAIA framing/parsing against byte sequences captured from the
/// real Sennheiser Smart Control <-> headphone exchange (no hardware needed).
func runSelfTest() {
    var failures = 0
    func check(_ name: String, _ cond: Bool) {
        print("\(cond ? "✅" : "❌") \(name)")
        if !cond { failures += 1 }
    }
    func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    // --- Outbound request encoding (verified against captured app traffic) ---
    check("GET battery == ff0300000495 0603",
          hex(GAIA.frame(vendor: GAIA.vendorSennheiser, command: SennCmd.batteryGet)) == "ff0300000495 0603".replacingOccurrences(of: " ", with: ""))
    check("GET ANC modes == ff0300000495 1a01",
          hex(GAIA.frame(vendor: GAIA.vendorSennheiser, command: SennCmd.ancModeGet)) == "ff0300000495 1a01".replacingOccurrences(of: " ", with: ""))
    check("GET model id == ff0300000495 1206",
          hex(GAIA.frame(vendor: GAIA.vendorSennheiser, command: SennCmd.modelIdGet)) == "ff0300000495 1206".replacingOccurrences(of: " ", with: ""))
    check("SET ANC adaptive on == ff0300020495 1a00 0301",
          hex(GAIA.frame(vendor: GAIA.vendorSennheiser, command: SennCmd.ancModeSet, payload: [3, 1])) == "ff0300020495 1a00 0301".replacingOccurrences(of: " ", with: ""))
    check("SET transparency level 4 == ff0300010495 1a02 04",
          hex(GAIA.frame(vendor: GAIA.vendorSennheiser, command: SennCmd.transparencySet, payload: [4])) == "ff0300010495 1a02 04".replacingOccurrences(of: " ", with: ""))

    // --- Inbound response parsing ---
    // Battery -> 0x2A = 42%
    let battery: [UInt8] = [0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x07, 0x03, 0x2A]
    let (bp, _) = GAIA.split(battery)
    check("battery frame splits to 1 packet", bp.count == 1)
    check("battery cmd == 0x0703", bp.first?.command == SennCmd.batteryResp)
    check("battery payload == [0x2A]", bp.first?.payload == [0x2A])

    // ANC modes -> 01 02 02 00 03 01  (antiWind=2/auto, transparency=0, adaptive=1/on)
    let anc: [UInt8] = [0xFF, 0x03, 0x00, 0x06, 0x04, 0x95, 0x1B, 0x01, 0x01, 0x02, 0x02, 0x00, 0x03, 0x01]
    let (ap, _) = GAIA.split(anc)
    check("anc payload length 6", ap.first?.payload.count == 6)

    // Model id string "MMMMBT Black\0"
    let model: [UInt8] = [0xFF, 0x03, 0x00, 0x0D, 0x04, 0x95, 0x13, 0x06] + Array("MMMMBT Black".utf8) + [0x00]
    let (mp, _) = GAIA.split(model)
    let name = mp.first.flatMap { String(bytes: $0.payload.prefix { $0 != 0 }, encoding: .utf8) }
    check("model id parses to 'MMMMBT Black'", name == "MMMMBT Black")

    // Concatenated + partial stream handling
    let stream = battery + anc + [0xFF, 0x03, 0x00, 0x04] // trailing incomplete frame
    let (sp, rem) = GAIA.split(stream)
    check("stream yields 2 complete packets", sp.count == 2)
    check("stream keeps 4-byte remainder", rem.count == 4)

    print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
    if failures > 0 { exit(1) }
}
