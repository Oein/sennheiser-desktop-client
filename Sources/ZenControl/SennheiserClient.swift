import Foundation
import IOBluetooth
import Combine

/// Observable state of the connected headphones, plus the RFCOMM/GAIA transport.
///
/// Sennheiser ACCENTUM / MOMENTUM headphones speak Qualcomm GAIA V3 over a
/// Bluetooth Classic RFCOMM (Serial Port Profile, UUID 0x1101) channel. We locate
/// that channel on the already-paired device via SDP and exchange GAIA frames.
final class SennheiserClient: NSObject, ObservableObject {

    // State; `onChange` is called on the main thread after any update, and
    // `objectWillChange` fires so SwiftUI views re-render.
    private(set) var deviceName: String = ""
    private(set) var isConnected = false
    private(set) var modelId: String = ""
    private(set) var firmware: String = ""
    private(set) var battery: Int? = nil          // headphone battery %
    private(set) var codec: String = "—"
    private(set) var noise = NoiseControlState()
    private(set) var smartPause: Bool? = nil
    private(set) var onHead: Bool? = nil
    private(set) var lastError: String = ""

    /// Which features to show, based on the connected model (id + BT name).
    var profile: DeviceProfile { DeviceProfile.resolve(modelId: modelId, name: deviceName) }

    // Product info
    private(set) var serial: String = ""
    private(set) var hwRevision: String = ""

    // Sound / calls / misc settings
    private(set) var sidetone: UInt8? = nil       // 0..5
    private(set) var promptMode: UInt8? = nil      // 0 off, 1 tone, 2 tone+voice
    private(set) var promptLanguage: UInt8? = nil
    private(set) var autoAnswer: Bool? = nil
    private(set) var comfortCall: Bool? = nil
    private(set) var lowLatency: Bool? = nil
    private(set) var btCompatibility: UInt8? = nil // 0 betterAudio, 1 betterCompat
    private(set) var autoPowerOff: UInt16? = nil   // minutes (0 = never)
    private(set) var audioMode: UInt8? = nil       // 0-5; 2 = podcast

    // Paired devices
    private(set) var pairedDevices: [PairedDevice] = []
    private var pairedExpected = 0

    // Equalizer (5-band graphic EQ, gains in dB)
    private(set) var eqBands: [Float] = [0, 0, 0, 0, 0]
    private(set) var eqPreset: String = "Flat"
    private(set) var bassBoost = false

    var onChange: (() -> Void)?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var rxBuffer: [UInt8] = []

    // Names we treat as supported Sennheiser GAIA devices.
    private static let nameHints = ["ACCENTUM", "MOMENTUM", "SENNHEISER", "CX", "HD "]

    // MARK: - Discovery & connection

    /// Returns paired devices that look like supported Sennheiser headphones.
    static func candidateDevices() -> [IOBluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.filter { dev in
            let n = (dev.name ?? "").uppercased()
            return nameHints.contains { n.contains($0) }
        }
    }

    func connect(to dev: IOBluetoothDevice) {
        disconnect()
        device = dev
        deviceName = dev.name ?? dev.addressString ?? "Sennheiser"
        notify()

        // SDP may be cached for a paired device; refresh it, then open the SPP channel.
        dev.performSDPQuery(self)
    }

    func disconnect() {
        channel?.close()
        channel = nil
        device = nil
        isConnected = false
        rxBuffer.removeAll()
    }

    private func openSerialPortChannel(on dev: IOBluetoothDevice) {
        // Sennheiser exposes the GAIA control channel as an SDP record literally
        // named "GAIA" (an RFCOMM/SPP service, distinct from the Hands-Free unit).
        var channelID: BluetoothRFCOMMChannelID = 0
        var found = false

        if let records = dev.services as? [IOBluetoothSDPServiceRecord] {
            // 1) prefer the record named "GAIA"
            for rec in records where (rec.getServiceName() ?? "").uppercased() == "GAIA" {
                if rec.getRFCOMMChannelID(&channelID) == kIOReturnSuccess { found = true; break }
            }
            // 2) otherwise the first RFCOMM record that is NOT Hands-Free / Headset
            if !found {
                for rec in records {
                    let name = (rec.getServiceName() ?? "").lowercased()
                    if name.contains("hands-free") || name.contains("headset") { continue }
                    if rec.getRFCOMMChannelID(&channelID) == kIOReturnSuccess { found = true; break }
                }
            }
        }
        // 3) last resort: the generic Serial Port (0x1101) record
        if !found, let record = dev.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1101)),
           record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
            found = true
        }
        guard found else {
            fail("No GAIA / Serial Port service found on \(deviceName).")
            return
        }
        var ch: IOBluetoothRFCOMMChannel?
        let res = dev.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        if res != kIOReturnSuccess {
            fail("Failed to open RFCOMM channel (error \(res)).")
            return
        }
        channel = ch
    }

    // MARK: - Sending

    var debug = false

    func send(vendor: UInt16 = GAIA.vendorSennheiser, _ command: UInt16, _ payload: [UInt8] = []) {
        guard let ch = channel, isConnected else { return }
        let data = GAIA.frame(vendor: vendor, command: command, payload: payload)
        if debug { print(">> " + data.map { String(format: "%02x", $0) }.joined()) }
        var frame = [UInt8](data)
        frame.withUnsafeMutableBytes { raw in
            _ = ch.writeSync(raw.baseAddress, length: UInt16(raw.count))
        }
    }

    /// Query everything we display once the link is up.
    private func refreshAll() {
        // subscribe to async notifications first
        send(SennCmd.registerNotification, [SennCmd.featureBattery])
        send(SennCmd.registerNotification, [SennCmd.featureANC])
        send(SennCmd.registerNotification, [SennCmd.featureUserEQ])
        send(SennCmd.modelIdGet)
        send(SennCmd.fwVersionGet)
        send(SennCmd.batteryGet)
        send(SennCmd.codecGet)
        send(SennCmd.ancOnGet)
        send(SennCmd.transparencyOnGet)
        send(SennCmd.transparencyGet)
        send(SennCmd.ancModeGet)                       // anti-wind state (mode 1)
        send(SennCmd.smartPauseGet)
        send(SennCmd.onHeadGet)
        // product info
        send(vendor: GAIA.vendorQualcomm, SennCmd.serialGet)
        send(SennCmd.hwRevisionGet)
        // sound / calls / misc
        send(SennCmd.sidetoneGet)
        send(SennCmd.promptModeGet)
        send(SennCmd.promptLangGet)
        send(SennCmd.autoAnswerGet)
        send(SennCmd.comfortCallGet)
        send(SennCmd.lowLatencyGet)
        send(SennCmd.btCompatGet)
        send(SennCmd.audioModeGet)
        send(SennCmd.timerGet, [SennCmd.timerPowerOff])
        // paired devices
        send(SennCmd.pairedListSizeGet)
        // equalizer
        send(SennCmd.eqConfigGet)
        for b in UInt8(0)..<5 { send(SennCmd.eqBandGet, [b]) }
        send(SennCmd.bassBoostGet)
    }

    // MARK: - Public control surface

    func setNoiseMode(_ mode: NoiseControlState.Mode) {
        // ANC and Transparency are independent toggles; drive them to a clean,
        // mutually-exclusive 3-state. (Verified against a real ACCENTUM.)
        switch mode {
        case .anc:
            send(SennCmd.transparencyOnSet, [0])
            send(SennCmd.ancOnSet, [1])
        case .transparency:
            send(SennCmd.ancOnSet, [0])
            send(SennCmd.transparencyOnSet, [1])
        case .off:
            send(SennCmd.transparencyOnSet, [0])
            send(SennCmd.ancOnSet, [0])
        case .unknown:
            break
        }
        send(SennCmd.ancOnGet)                         // read back
        send(SennCmd.transparencyOnGet)
    }

    private var transpWork: DispatchWorkItem?
    /// Debounced so a slider drag doesn't flood the RFCOMM link; the value where the
    /// user settles is the one that gets sent.
    func setTransparencyLevel(_ level: UInt8) {
        transpWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.send(SennCmd.transparencySet, [level])
        }
        transpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func setSmartPause(_ on: Bool) {
        send(SennCmd.smartPauseSet, [on ? 1 : 0])
        send(SennCmd.smartPauseGet)
    }

    func setOnHeadDetection(_ on: Bool) {
        send(SennCmd.onHeadSet, [on ? 1 : 0])
        send(SennCmd.onHeadGet)
    }

    func setAntiWind(_ value: UInt8) {                 // 0 off, 1 max, 2 auto
        send(SennCmd.ancModeSet, [1, value])
        send(SennCmd.ancModeGet)
    }

    func setSidetone(_ level: UInt8) {                 // 0..5
        send(SennCmd.sidetoneSet, [min(level, 5)])
        send(SennCmd.sidetoneGet)
    }

    func setPromptMode(_ mode: UInt8) {                // 0 off, 1 tone, 2 tone+voice
        send(SennCmd.promptModeSet, [mode])
        send(SennCmd.promptModeGet)
    }

    func setAutoAnswer(_ on: Bool) {
        send(SennCmd.autoAnswerSet, [on ? 1 : 0]); send(SennCmd.autoAnswerGet)
    }

    func setComfortCall(_ on: Bool) {
        send(SennCmd.comfortCallSet, [on ? 1 : 0]); send(SennCmd.comfortCallGet)
    }

    func setLowLatency(_ on: Bool) {
        send(SennCmd.lowLatencySet, [on ? 1 : 0]); send(SennCmd.lowLatencyGet)
    }

    func setBtCompatibility(_ betterCompat: Bool) {
        send(SennCmd.btCompatSet, [betterCompat ? 1 : 0]); send(SennCmd.btCompatGet)
    }

    func setPodcastMode(_ on: Bool) {
        send(SennCmd.audioModeSet, [0x00, on ? SennCmd.audioModePodcast : 0])
        send(SennCmd.audioModeGet)
    }

    func setAutoPowerOff(_ minutes: UInt16) {
        send(SennCmd.timerSet, [SennCmd.timerPowerOff,
                                UInt8((minutes >> 8) & 0xFF), UInt8(minutes & 0xFF)])
        send(SennCmd.timerGet, [SennCmd.timerPowerOff])
    }

    func connectPairedDevice(_ index: UInt8)    { send(SennCmd.pairedConnect, [index]); refreshPaired() }
    func disconnectPairedDevice(_ index: UInt8) { send(SennCmd.pairedDisconnect, [index]); refreshPaired() }
    func deletePairedDevice(_ index: UInt8)     { send(SennCmd.pairedDelete, [index]); refreshPaired() }
    private func refreshPaired() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.send(SennCmd.pairedListSizeGet)
        }
    }

    func factoryReset() { send(SennCmd.factoryReset) }

    /// Apply a graphic-EQ preset (5 band gains, dB). Sends each band to the device.
    func applyEqPreset(name: String, gains: [Float]) {
        eqPreset = name
        eqBands = gains
        for (i, g) in gains.enumerated() { sendEqBand(i, g) }
        notify()
    }

    func setEqBand(_ index: Int, _ gain: Float) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = gain
        eqPreset = "Custom"
        sendEqBand(index, gain)    // debounced per band
        notify()
    }

    func setBassBoost(_ on: Bool) {
        bassBoost = on
        send(SennCmd.bassBoostSet, [on ? 1 : 0])
        send(SennCmd.bassBoostGet)
        notify()
    }

    private var eqWork: [Int: DispatchWorkItem] = [:]
    /// EQ band gain is encoded as a signed byte of dB×10 (e.g. +3.0 dB → 30).
    private func sendEqBand(_ index: Int, _ gainDB: Float) {
        eqWork[index]?.cancel()
        let raw = Int8(clamping: Int((gainDB * 10).rounded()))
        let work = DispatchWorkItem { [weak self] in
            self?.send(SennCmd.eqBandSet, [UInt8(index), UInt8(bitPattern: raw)])
        }
        eqWork[index] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func refresh() { refreshAll() }

    // MARK: - Inbound frame handling

    private func handle(_ pkt: GAIA.Packet) {
        let p = pkt.payload
        switch pkt.command {
        case SennCmd.ancOnResp, SennCmd.ancOnNotif:
            if let v = p.first { noise.ancOn = v != 0 }
        case SennCmd.transparencyOnResp, SennCmd.transparencyOnNotif:
            if let v = p.first { noise.transparencyOn = v != 0 }
        case SennCmd.transparencyResp, SennCmd.transparencyNotif:
            if let v = p.first { noise.transparencyLevel = v }
        case SennCmd.ancModeResp, SennCmd.ancModeNotif:
            // 6 bytes (mode,state)×3; mode 1 = anti-wind.
            if p.count >= 2, p[0] == 1 { noise.antiWind = p[1] }
            if p.count >= 6 {
                for j in stride(from: 0, to: 6, by: 2) where p[j] == 1 { noise.antiWind = p[j + 1] }
            }
        case SennCmd.serialResp:
            serial = String(bytes: p.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        case SennCmd.hwRevisionResp:
            if p.count >= 2 { hwRevision = "\((Int(p[0]) << 8) | Int(p[1]))" }
        case SennCmd.sidetoneResp:
            if let v = p.first { sidetone = v }
        case SennCmd.promptModeResp:
            if let v = p.first { promptMode = v }
        case SennCmd.promptLangResp:
            if let v = p.first { promptLanguage = v }
        case SennCmd.autoAnswerResp:
            if let v = p.first { autoAnswer = v != 0 }
        case SennCmd.comfortCallResp:
            if let v = p.first { comfortCall = v != 0 }
        case SennCmd.lowLatencyResp:
            if let v = p.first { lowLatency = v != 0 }
        case SennCmd.btCompatResp:
            if let v = p.first { btCompatibility = v }
        case SennCmd.audioModeResp, SennCmd.audioModeNotif:
            if let v = p.last { audioMode = v }
        case SennCmd.timerResp:
            // [timerID u8, value u16]; we only track POWER_OFF_TIMER (id 0)
            if p.count >= 3, p[0] == SennCmd.timerPowerOff {
                autoPowerOff = (UInt16(p[1]) << 8) | UInt16(p[2])
            }
        case SennCmd.pairedListSizeResp:
            // [ownIndex, count] (observed). Fetch each device's info.
            let count = Int(p.last ?? 0)
            pairedExpected = count
            pairedDevices.removeAll()
            for i in 0..<count { send(SennCmd.pairedDeviceInfo, [UInt8(i)]) }
        case SennCmd.eqBandResp, SennCmd.eqBandSetResp:
            // [band, gain_i8] (gain = dB×10)
            if p.count >= 2, p[0] < 5 {
                eqBands[Int(p[0])] = Float(Int8(bitPattern: p[1])) / 10
                matchEqPreset()
            }
        case SennCmd.eqNotif:
            // pushes all 5 band gains as signed bytes (dB×10)
            if p.count >= 5 {
                for i in 0..<5 { eqBands[i] = Float(Int8(bitPattern: p[i])) / 10 }
                matchEqPreset()
            }
        case SennCmd.bassBoostResp, SennCmd.bassBoostNotif:
            if let v = p.first { bassBoost = v != 0 }
        case SennCmd.pairedDeviceInfoResp:
            // [index, connectionPriority, connectionStatus, ...name(string)]
            if p.count >= 3 {
                let idx = p[0]
                let connected = p[2] != 0
                let nameBytes = Array(p[3...]).prefix { $0 != 0 }
                let name = String(bytes: nameBytes, encoding: .utf8) ?? "Device \(idx)"
                pairedDevices.removeAll { $0.index == idx }
                pairedDevices.append(PairedDevice(index: idx, connected: connected, name: name))
                pairedDevices.sort { $0.index < $1.index }
            }
        case SennCmd.batteryResp, SennCmd.batteryNotif:
            // first byte is count, remainder are per-source percentages; take the max.
            if p.count >= 2 { battery = Int(p[1...].max() ?? p[1]) }
            else if let v = p.first { battery = Int(v) }
        case SennCmd.codecResp:
            if let v = p.first { codec = Codec.name(v) }
        case SennCmd.modelIdResp:
            modelId = String(bytes: p.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        case SennCmd.fwVersionResp:
            if p.count >= 6 {
                let a = (Int(p[0]) << 8) | Int(p[1])
                let b = (Int(p[2]) << 8) | Int(p[3])
                let c = (Int(p[4]) << 8) | Int(p[5])
                firmware = "\(a).\(b).\(c)"
            }
        case SennCmd.smartPauseResp:
            if let v = p.first { smartPause = v != 0 }
        case SennCmd.onHeadResp:
            if let v = p.first { onHead = v != 0 }
        default:
            break
        }
        notify()
    }

    // MARK: - Helpers

    /// Label the current band gains if they match a known preset, else "Custom".
    private func matchEqPreset() {
        for preset in EqPreset.all where preset.gains == eqBands {
            eqPreset = preset.name; return
        }
        if eqBands == EqPreset.bassBoost { eqPreset = "Bass Boost"; return }
        eqPreset = "Custom"
    }

    private func fail(_ msg: String) {
        lastError = msg
        notify()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.onChange?()
        }
    }
}

// MARK: - SDP completion

extension SennheiserClient {
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let device else { return }
        if status == kIOReturnSuccess {
            openSerialPortChannel(on: device)
        } else {
            fail("SDP query failed (error \(status)).")
        }
    }
}

// MARK: - RFCOMM channel delegate

extension SennheiserClient: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            isConnected = true
            lastError = ""
            notify()
            refreshAll()
        } else {
            fail("RFCOMM open failed (error \(error)).")
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        let chunk = Data(bytes: dataPointer, count: dataLength)
        rxBuffer.append(contentsOf: chunk)
        let (packets, remainder) = GAIA.split(rxBuffer)
        rxBuffer = remainder
        for pkt in packets {
            if debug {
                let pl = pkt.payload.map { String(format: "%02x", $0) }.joined()
                print(String(format: "<< vendor=%04x cmd=%04x payload=%@", pkt.vendor, pkt.command, pl))
            }
            handle(pkt)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        isConnected = false
        channel = nil
        notify()
    }
}
