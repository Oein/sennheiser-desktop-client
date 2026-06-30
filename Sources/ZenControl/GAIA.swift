import Foundation

// MARK: - GAIA V3 framing (Sennheiser / Sonova over Qualcomm GAIA)
//
// Wire format of a single GAIA V3 frame, as used by Sennheiser Smart Control:
//
//   byte 0   : 0xFF                 protocol version / start-of-frame
//   byte 1   : 0x03                 flags
//   byte 2-3 : payload length       (big-endian, number of payload bytes)
//   byte 4-5 : vendor id            (big-endian)   0x0495 = Sennheiser, 0x001D = Qualcomm core
//   byte 6-7 : command id           (big-endian)
//   byte 8.. : payload
//
// Command-id low-level convention (observed):
//   SET/GET requests use one id, the device answers with id|0x0100 (response),
//   asynchronous notifications use id|0x0080, errors use id|0x0180.
//
// Verified against captured exchanges, e.g.:
//   GET battery   FF 03 00 00 04 95 06 03         -> FF 03 00 01 04 95 07 03 2A      (0x2A = 42%)
//   GET ANC modes FF 03 00 00 04 95 1A 01         -> FF 03 00 06 04 95 1B 01 01 02 02 00 03 01
//   GET model id  FF 03 00 00 04 95 12 06         -> FF 03 00 0D 04 95 13 06 "MMMMBT Black\0"

enum GAIA {
    static let sof: UInt8 = 0xFF
    static let flags: UInt8 = 0x03

    static let vendorSennheiser: UInt16 = 0x0495
    static let vendorQualcomm: UInt16 = 0x001D

    /// Build a GAIA V3 frame.
    static func frame(vendor: UInt16, command: UInt16, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [sof, flags]
        let len = payload.count
        bytes.append(UInt8((len >> 8) & 0xFF))
        bytes.append(UInt8(len & 0xFF))
        bytes.append(UInt8((vendor >> 8) & 0xFF))
        bytes.append(UInt8(vendor & 0xFF))
        bytes.append(UInt8((command >> 8) & 0xFF))
        bytes.append(UInt8(command & 0xFF))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    /// A decoded inbound frame.
    struct Packet {
        let vendor: UInt16
        let command: UInt16
        let payload: [UInt8]
    }

    /// Split a (possibly concatenated / partial) byte stream into complete frames.
    /// Returns the parsed packets plus any trailing bytes that form an incomplete frame.
    static func split(_ buffer: [UInt8]) -> (packets: [Packet], remainder: [UInt8]) {
        var packets: [Packet] = []
        var i = 0
        while buffer.count - i >= 8 {
            guard buffer[i] == sof else {
                // resync: drop one byte and keep scanning
                i += 1
                continue
            }
            let len = (Int(buffer[i + 2]) << 8) | Int(buffer[i + 3])
            let total = 8 + len
            if buffer.count - i < total { break } // wait for more bytes
            let vendor = (UInt16(buffer[i + 4]) << 8) | UInt16(buffer[i + 5])
            let command = (UInt16(buffer[i + 6]) << 8) | UInt16(buffer[i + 7])
            let payload = Array(buffer[(i + 8)..<(i + total)])
            packets.append(Packet(vendor: vendor, command: command, payload: payload))
            i += total
        }
        return (packets, Array(buffer[i...]))
    }
}

// MARK: - Sennheiser command catalog (reverse-engineered from Smart Control APK / m4.json)

enum SennCmd {
    // Noise control -------------------------------------------------------
    // Combined ANC mode property. payload [mode, state].
    //   mode:  1 = anti-wind, 2 = transparency/comfort, 3 = adaptive ANC
    //   state: 0 = off, 1 = on, 2 = auto
    static let ancModeSet: UInt16 = 0x1A00
    static let ancModeGet: UInt16 = 0x1A01
    static let ancModeResp: UInt16 = 0x1B01      // 6 bytes: (mode,state) x3
    static let ancModeNotif: UInt16 = 0x1A81

    // ANC on/off (the real master switch on ACCENTUM)
    static let ancOnSet: UInt16 = 0x1A04         // [activation: 0/1]
    static let ancOnGet: UInt16 = 0x1A05
    static let ancOnResp: UInt16 = 0x1B05
    static let ancOnNotif: UInt16 = 0x1A85

    // Transparency on/off (TransparentHearing_Status)
    static let transparencyOnSet: UInt16 = 0x1804   // [0/1]
    static let transparencyOnGet: UInt16 = 0x1805
    static let transparencyOnResp: UInt16 = 0x1905
    static let transparencyOnNotif: UInt16 = 0x1885

    // Transparency level
    static let transparencySet: UInt16 = 0x1A02  // [level: uint8]
    static let transparencyGet: UInt16 = 0x1A03
    static let transparencyResp: UInt16 = 0x1B03
    static let transparencyNotif: UInt16 = 0x1A83

    // Battery -------------------------------------------------------------
    static let batteryGet: UInt16 = 0x0603       // -> resp 0x0703 / notif 0x0683
    static let batteryResp: UInt16 = 0x0703
    static let batteryNotif: UInt16 = 0x0683

    // System info ---------------------------------------------------------
    static let codecGet: UInt16 = 0x0800         // -> 0x0900
    static let codecResp: UInt16 = 0x0900
    static let modelIdGet: UInt16 = 0x1206       // -> 0x1306 (string)
    static let modelIdResp: UInt16 = 0x1306
    static let fwVersionGet: UInt16 = 0x1201     // -> 0x1301 (3x uint16)
    static let fwVersionResp: UInt16 = 0x1301

    // Toggles -------------------------------------------------------------
    static let sidetoneSet: UInt16 = 0x0805      // [level 0..5]
    static let sidetoneGet: UInt16 = 0x0806
    static let sidetoneResp: UInt16 = 0x0906

    static let smartPauseSet: UInt16 = 0x080C    // [0/1]
    static let smartPauseGet: UInt16 = 0x080D
    static let smartPauseResp: UInt16 = 0x090D

    static let onHeadSet: UInt16 = 0x0400        // [0/1]
    static let onHeadGet: UInt16 = 0x0401
    static let onHeadResp: UInt16 = 0x0501

    // Product info --------------------------------------------------------
    static let serialGet: UInt16 = 0x0003        // Qualcomm vendor, string
    static let serialResp: UInt16 = 0x0103
    static let hwRevisionGet: UInt16 = 0x1200    // -> 0x1300 (uint16)
    static let hwRevisionResp: UInt16 = 0x1300

    // Sidetone level 0..5 -------------------------------------------------
    // (declared above: sidetoneSet 0x0805 / sidetoneGet 0x0806 / sidetoneResp 0x0906)

    // Voice / tone prompts ------------------------------------------------
    static let promptModeSet: UInt16 = 0x0801    // [0 off, 1 tone, 2 tone+voice]
    static let promptModeGet: UInt16 = 0x0802
    static let promptModeResp: UInt16 = 0x0902
    static let promptLangGet: UInt16 = 0x0807    // -> 0x0907
    static let promptLangResp: UInt16 = 0x0907

    // Calls ---------------------------------------------------------------
    static let autoAnswerSet: UInt16 = 0x080A    // [0/1]
    static let autoAnswerGet: UInt16 = 0x080B
    static let autoAnswerResp: UInt16 = 0x090B
    static let comfortCallSet: UInt16 = 0x0814   // [0/1]
    static let comfortCallGet: UInt16 = 0x0815
    static let comfortCallResp: UInt16 = 0x0915

    // Audio mode (genericAudio) — podcast mode = audio mode 2 -------------
    static let audioModeSet: UInt16 = 0x0803     // [0x00, mode 0-5]
    static let audioModeGet: UInt16 = 0x0804
    static let audioModeResp: UInt16 = 0x0904
    static let audioModeNotif: UInt16 = 0x0884
    static let audioModePodcast: UInt8 = 2

    // Misc toggles --------------------------------------------------------
    static let lowLatencySet: UInt16 = 0x0817    // [0/1]
    static let lowLatencyGet: UInt16 = 0x0818
    static let lowLatencyResp: UInt16 = 0x0918
    static let btCompatSet: UInt16 = 0x0405      // [0 betterAudio, 1 betterCompat]
    static let btCompatGet: UInt16 = 0x0406
    static let btCompatResp: UInt16 = 0x0506

    // Auto power-off timer (Config timer; timerID 0 = POWER_OFF_TIMER) -----
    static let timerSet: UInt16 = 0x0600         // [timerID u8, value u16]
    static let timerGet: UInt16 = 0x0601         // [timerID u8] -> 0x0701 [id u8, value u16]
    static let timerResp: UInt16 = 0x0701
    static let timerPowerOff: UInt8 = 0

    // Anti-wind via combined ANC mode (mode 1) ----------------------------
    // setting: ancModeSet 0x1A00 [1, value]; value 0 off / 1 max / 2 auto.
    // reading: ancModeResp 0x1B01 / notif 0x1A81, first (mode,state) pair.

    // Paired devices ------------------------------------------------------
    static let pairedListSizeGet: UInt16 = 0x1400   // -> 0x1500 [own?, count]
    static let pairedListSizeResp: UInt16 = 0x1500
    static let pairedDeviceInfo: UInt16 = 0x1401    // [index] -> 0x1501 [idx,prio,status,...,name]
    static let pairedDeviceInfoResp: UInt16 = 0x1501
    static let pairedConnect: UInt16 = 0x1402       // [index]
    static let pairedDisconnect: UInt16 = 0x1403    // [index]
    static let pairedDelete: UInt16 = 0x1405        // [index]

    // Factory reset -------------------------------------------------------
    static let factoryReset: UInt16 = 0x0040        // invocation, no params

    // Equalizer (UserEq feature 8, base 0x1000) ---------------------------
    // Confirmed against the same Sennheiser GAIA stack (HDB 630 reverse engineering).
    static let eqConfigGet: UInt16 = 0x1000      // -> [bands, minGain_i7, maxGain_i7, ..]
    static let eqBandSet: UInt16 = 0x1001        // [band 0-4, gain int8 = dB×10]
    static let eqBandGet: UInt16 = 0x1002        // [band] -> [gain int8]
    static let eqBandResp: UInt16 = 0x1102       // get response
    static let eqBandSetResp: UInt16 = 0x1101    // set response (band echo)
    static let eqNotif: UInt16 = 0x1082          // pushes all 5 band gains
    static let bassBoostSet: UInt16 = 0x1008     // [0/1]
    static let bassBoostGet: UInt16 = 0x1009
    static let bassBoostResp: UInt16 = 0x1109
    static let bassBoostNotif: UInt16 = 0x1089

    // Notification registration (Sennheiser vendor) -----------------------
    // invocation 0x0007 [featureID]; featureID: battery = 3, ANC = 13, userEQ = 8
    static let registerNotification: UInt16 = 0x0007
    static let featureBattery: UInt8 = 3
    static let featureANC: UInt8 = 13
    static let featureUserEQ: UInt8 = 8
}

/// One entry in the headphone's paired-device list.
struct PairedDevice: Identifiable, Equatable {
    var id: UInt8 { index }
    let index: UInt8
    let connected: Bool
    let name: String
}

/// 5-band graphic-EQ presets (gains in dB) — taken verbatim from the ACCENTUM config.
/// Band centre labels: 50 / 250 / 800 / 3000 / 8000 Hz.
enum EqPreset {
    static let bands = ["50", "250", "800", "3k", "8k"]
    static let all: [(name: String, gains: [Float])] = [
        ("Flat",      [0, 0, 0, 0, 0]),
        ("Rock",      [0, 0, 3, 3, -1]),
        ("Pop",       [0, -5, 0, 5, 0]),
        ("Dance",     [2, -3, -3, 1, 1]),
        ("Hip-Hop",   [3, -1, -4, 2, 0]),
        ("Classical", [0, 0, 0, 1, 2]),
        ("Movie",     [0, 0, 2, 2, -1]),
        ("Jazz",      [-3, 0, 2, 2, 0]),
    ]
    static let bassBoost: [Float] = [5, -2, 0, 0, 0]
    static let gainLimit: Float = 6     // ACCENTUM gain range ±6 dB (graphic EQ)
}

/// Voice-prompt language map (Sennheiser).
enum PromptLanguage {
    static let names: [UInt8: String] = [
        0: "English", 1: "German", 2: "French", 3: "Spanish",
        4: "Chinese", 5: "Japanese", 6: "Russian", 7: "Korean"
    ]
    static func name(_ id: UInt8) -> String { names[id] ?? "—" }
}

/// High-level noise-control state of the headphones.
///
/// ACCENTUM exposes two independent boolean toggles — ANC on/off (0x1A05) and
/// Transparency on/off (0x1805) — plus a transparency level. The audible mode is
/// derived from them: transparency takes precedence, then ANC, otherwise off.
struct NoiseControlState: Equatable {
    enum Mode: String { case anc = "ANC", transparency = "Transparency", off = "Off", unknown = "—" }

    var ancOn: Bool? = nil
    var transparencyOn: Bool? = nil
    var transparencyLevel: UInt8 = 0
    var antiWind: UInt8? = nil          // 0 off, 1 max, 2 auto (mode 1 of 0x1B01)

    var active: Mode {
        if transparencyOn == true { return .transparency }
        if ancOn == true { return .anc }
        if ancOn == false { return .off }
        return .unknown
    }
}

/// Known codec ids (Sennheiser map).
enum Codec {
    static let names: [UInt8: String] = [
        0: "SBC", 1: "AAC", 2: "aptX", 3: "aptX-LL", 4: "MP3", 5: "aptX-HD",
        6: "Faststream", 7: "LHDC", 8: "aptX Adaptive", 9: "aptX Lossless",
        10: "LC3", 255: "—"
    ]
    static func name(_ id: UInt8) -> String { names[id] ?? "0x\(String(id, radix: 16))" }
}
