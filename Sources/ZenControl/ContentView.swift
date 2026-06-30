import SwiftUI
import IOBluetooth

struct ContentView: View {
    @ObservedObject var client: SennheiserClient
    @State private var devices: [IOBluetoothDevice] = []
    @State private var transparency: Double = 0
    @State private var transparencyEditing = false
    @State private var sidetone: Double = 0
    @State private var sidetoneEditing = false
    @State private var showResetConfirm = false
    @State private var selectedTab = 0

    private let powerOffOptions: [(String, UInt16)] =
        [("Never", 0), ("15 min", 15), ("30 min", 30), ("1 hour", 60), ("2 hours", 120)]

    private var p: DeviceProfile { client.profile }

    var body: some View {
        VStack(spacing: 0) {
            header
            if client.isConnected {
                tabs
            } else {
                disconnectedBody
            }
        }
        .frame(width: Theme.windowWidth)
        .frame(minHeight: 460, idealHeight: 600, maxHeight: 820)
        .background(WindowBackground())
        .tint(Theme.accent)
        .onAppear { reloadDevices(); autoConnect() }
        .onReceive(client.objectWillChange) { _ in
            if !transparencyEditing { transparency = Double(client.noise.transparencyLevel) }
            if !sidetoneEditing { sidetone = Double(client.sidetone ?? 0) }
        }
        .animation(.easeInOut(duration: 0.2), value: client.isConnected)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(client.isConnected ? 0.18 : 0.08))
                    .frame(width: 46, height: 46)
                Image(systemName: "headphones")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(client.isConnected ? Theme.accent : .secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle).font(.headline)
                HStack(spacing: 5) {
                    StatusDot(connected: client.isConnected)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if client.isConnected, let b = client.battery { BatteryBadge(percent: b) }
        }
        .padding(.horizontal, 18).padding(.top, 28).padding(.bottom, 12)
    }

    private var headerTitle: String {
        if !client.modelId.isEmpty { return client.modelId }
        if !client.deviceName.isEmpty { return client.deviceName }
        return "ZenControl"
    }

    private var statusLine: String {
        if client.isConnected {
            var p: [String] = []
            if client.codec != "—" { p.append(client.codec) }
            if !client.firmware.isEmpty { p.append("fw \(client.firmware)") }
            return p.isEmpty ? "Connected" : p.joined(separator: " · ")
        }
        return client.lastError.isEmpty ? "Not connected" : client.lastError
    }

    // MARK: - Tabs

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            scroll { noiseSection }
                .tabItem { Label("Noise", systemImage: "waveform") }.tag(0)
            if p.has(.equalizer) {
                scroll { equalizerSection }
                    .tabItem { Label("EQ", systemImage: "slider.vertical.3") }.tag(1)
            }
            scroll { settingsTab }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
            scroll { deviceSection }
                .tabItem { Label("Device", systemImage: "info.circle") }.tag(3)
        }
        .padding(.top, 4)
    }

    private func scroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView { VStack(spacing: 14) { content() }.padding(16) }
    }

    // MARK: - Noise

    private var noiseSection: some View {
        SectionCard(title: "Noise Control", systemImage: "waveform") {
            HStack(spacing: 8) {
                ModeButton(title: "Adaptive ANC", systemImage: "waveform.path.ecg",
                           selected: client.noise.active == .anc) { client.setNoiseMode(.anc) }
                ModeButton(title: "Transparency", systemImage: "ear",
                           selected: client.noise.active == .transparency) { client.setNoiseMode(.transparency) }
                ModeButton(title: "Off", systemImage: "speaker.slash",
                           selected: client.noise.active == .off) { client.setNoiseMode(.off) }
            }
            if client.noise.active == .transparency && p.showsTransparencyLevel {
                Divider()
                gainSlider("Transparency level", value: $transparency, editing: $transparencyEditing,
                           range: 0...100, deviceValue: Int(client.noise.transparencyLevel), unit: "") {
                    client.setTransparencyLevel(UInt8($0))
                }
            }
            if p.hasAntiWind, let aw = client.noise.antiWind {
                Divider()
                SettingRow(icon: "wind", title: "Anti-Wind") {
                    Picker("", selection: Binding(get: { Int(aw) }, set: { client.setAntiWind(UInt8($0)) })) {
                        Text("Off").tag(0); Text("Max").tag(1); Text("Auto").tag(2)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }

    // MARK: - Equalizer

    private var equalizerSection: some View {
        SectionCard(title: "Equalizer", systemImage: "slider.vertical.3",
                    accessory: AnyView(
                        Text(client.eqPreset.isEmpty ? "" : client.eqPreset)
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                    )) {
            EQCurve(gains: client.eqBands, limit: EqPreset.gainLimit)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EqPreset.all, id: \.name) { preset in
                        let selected = client.eqPreset == preset.name
                        Button(preset.name) { client.applyEqPreset(name: preset.name, gains: preset.gains) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(selected ? Theme.accent : Color.secondary.opacity(0.22))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                }.padding(.vertical, 2)
            }
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text("\(EqPreset.bands[i])Hz")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        Slider(value: Binding(get: { Double(client.eqBands[i]) },
                                              set: { client.setEqBand(i, Float($0)) }),
                               in: Double(-EqPreset.gainLimit)...Double(EqPreset.gainLimit), step: 1)
                        Text(String(format: "%+d", Int(client.eqBands[i])))
                            .font(.callout.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Divider()
            SettingRow(icon: "dial.high", title: "Bass Boost") {
                Toggle("", isOn: Binding(get: { client.bassBoost }, set: { client.setBassBoost($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: - Settings tab (model-gated)

    @ViewBuilder private var settingsTab: some View {
        let showSound = p.has(.sidetone) || p.has(.lowLatency) || p.has(.btCompatibility)
        let showCalls = p.has(.autoAnswer) || p.has(.comfortCall)
        if showSound { soundSection }
        if showCalls { callsSection }
        generalSection
        if !showSound && !showCalls && !hasGeneralRows {
            Text("No adjustable settings for this model.")
                .font(.callout).foregroundStyle(.secondary).padding()
        }
    }

    private var hasGeneralRows: Bool {
        p.has(.smartPause) || p.has(.onHeadDetection) || p.has(.podcastMode)
            || p.has(.voicePrompts) || p.has(.autoPowerOff)
    }

    private var soundSection: some View {
        SectionCard(title: "Sound", systemImage: "speaker.wave.2") {
            if p.has(.sidetone) {
                gainSlider("Sidetone", value: $sidetone, editing: $sidetoneEditing,
                           range: 0...5, deviceValue: Int(client.sidetone ?? 0), unit: "",
                           enabled: client.sidetone != nil) { client.setSidetone(UInt8($0)) }
            }
            if p.has(.lowLatency) {
                if p.has(.sidetone) { Divider() }
                SettingRow(icon: "timer", title: "Low Latency Mode", enabled: client.lowLatency != nil) {
                    switchToggle(client.lowLatency) { client.setLowLatency($0) }
                }
            }
            if p.has(.btCompatibility) {
                Divider()
                SettingRow(icon: "antenna.radiowaves.left.and.right", title: "Connection",
                           subtitle: "Audio quality vs. range", enabled: client.btCompatibility != nil) {
                    Picker("", selection: Binding(get: { Int(client.btCompatibility ?? 0) },
                                                  set: { client.setBtCompatibility($0 == 1) })) {
                        Text("Audio").tag(0); Text("Compatibility").tag(1)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }

    private var callsSection: some View {
        SectionCard(title: "Calls", systemImage: "phone") {
            if p.has(.autoAnswer) {
                SettingRow(icon: "phone.arrow.down.left", title: "Auto-Answer Calls",
                           enabled: client.autoAnswer != nil) {
                    switchToggle(client.autoAnswer) { client.setAutoAnswer($0) }
                }
            }
            if p.has(.comfortCall) {
                if p.has(.autoAnswer) { Divider() }
                SettingRow(icon: "waveform.and.person.filled", title: "Comfort Call",
                           subtitle: "Hear yourself during calls", enabled: client.comfortCall != nil) {
                    switchToggle(client.comfortCall) { client.setComfortCall($0) }
                }
            }
        }
    }

    @ViewBuilder private var generalSection: some View {
        if hasGeneralRows {
            SectionCard(title: "General", systemImage: "gearshape") {
                if p.has(.smartPause) {
                    SettingRow(icon: "playpause", title: "Smart Pause",
                               subtitle: "Pause when removed", enabled: client.smartPause != nil) {
                        switchToggle(client.smartPause) { client.setSmartPause($0) }
                    }
                }
                if p.has(.onHeadDetection) {
                    if p.has(.smartPause) { Divider() }
                    SettingRow(icon: "sensor.tag.radiowaves.forward", title: "On-Head Detection",
                               enabled: client.onHead != nil) {
                        switchToggle(client.onHead) { client.setOnHeadDetection($0) }
                    }
                }
                if p.has(.podcastMode) {
                    Divider()
                    SettingRow(icon: "mic", title: "Podcast Mode", enabled: client.audioMode != nil) {
                        switchToggle(client.audioMode.map { $0 == 2 }) { client.setPodcastMode($0) }
                    }
                }
                if p.has(.voicePrompts) {
                    Divider()
                    SettingRow(icon: "speaker.wave.2.bubble", title: "Voice Prompts",
                               subtitle: client.promptLanguage.map { PromptLanguage.name($0) },
                               enabled: client.promptMode != nil) {
                        Picker("", selection: Binding(get: { Int(client.promptMode ?? 0) },
                                                      set: { client.setPromptMode(UInt8($0)) })) {
                            Text("Off").tag(0); Text("Tone").tag(1); Text("Voice").tag(2)
                        }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                if p.has(.autoPowerOff) {
                    Divider()
                    SettingRow(icon: "power", title: "Auto Power-Off", enabled: client.autoPowerOff != nil) {
                        Picker("", selection: Binding(get: { client.autoPowerOff ?? 0 },
                                                      set: { client.setAutoPowerOff($0) })) {
                            ForEach(powerOffOptions, id: \.1) { Text($0.0).tag($0.1) }
                        }.labelsHidden().fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Device

    private var deviceSection: some View {
        Group {
            if p.has(.connectionManagement) && !client.pairedDevices.isEmpty {
                SectionCard(title: "Connected Devices", systemImage: "link") {
                    ForEach(Array(client.pairedDevices.enumerated()), id: \.element.id) { idx, dev in
                        if idx > 0 { Divider() }
                        HStack(spacing: 10) {
                            Image(systemName: dev.connected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(dev.connected ? .green : .secondary)
                            Text(dev.name).font(.callout)
                            Spacer()
                            if dev.connected {
                                Button("Disconnect") { client.disconnectPairedDevice(dev.index) }.controlSize(.small)
                            } else {
                                Button("Connect") { client.connectPairedDevice(dev.index) }.controlSize(.small)
                            }
                            Button { client.deletePairedDevice(dev.index) }
                                label: { Image(systemName: "trash").foregroundStyle(.red) }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                    }
                }
            }
            SectionCard(title: "Device Info", systemImage: "info.circle") {
                infoRow("Model", client.modelId)
                infoRow("Firmware", client.firmware)
                infoRow("Hardware", client.hwRevision)
                infoRow("Serial", client.serial)
                if let b = client.battery { infoRow("Battery", "\(b)%") }
                infoRow("Codec", client.codec == "—" ? "" : client.codec)
            }
            HStack {
                Button { client.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Spacer()
                if p.has(.factoryReset) {
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Label("Factory Reset", systemImage: "exclamationmark.arrow.circlepath")
                    }
                }
            }
            .confirmationDialog("Reset the headphones to factory settings?",
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Factory Reset", role: .destructive) { client.factoryReset() }
                Button("Cancel", role: .cancel) {}
            }
            HStack {
                Spacer()
                Button("Disconnect") { client.disconnect() }.controlSize(.small)
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedBody: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "headphones.circle")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(client.deviceName.isEmpty ? "No device connected" : "Connecting to \(client.deviceName)…")
                    .font(.headline)
                if devices.isEmpty {
                    Text("Pair your Sennheiser headphones in\nSystem Settings → Bluetooth, then reload.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            if !devices.isEmpty {
                VStack(spacing: 8) {
                    ForEach(devices, id: \.addressString) { dev in
                        Button { client.connect(to: dev) } label: {
                            HStack {
                                Image(systemName: "headphones")
                                Text(dev.name ?? dev.addressString ?? "Unknown")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(.vertical, 2)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                }
                .frame(maxWidth: 280)
            }
            Button { reloadDevices() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Reusable helpers

    private func switchToggle(_ value: Bool?, action: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value ?? false }, set: { action($0) }))
            .labelsHidden().toggleStyle(.switch).disabled(value == nil)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        Group {
            if !value.isEmpty {
                HStack {
                    Text(label).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.callout.monospacedDigit()).textSelection(.enabled)
                }
            }
        }
    }

    private func gainSlider(_ label: String, value: Binding<Double>, editing: Binding<Bool>,
                            range: ClosedRange<Double>, deviceValue: Int, unit: String,
                            enabled: Bool = true, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))\(unit)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1, onEditingChanged: { editing.wrappedValue = $0 })
                .onChange(of: value.wrappedValue) { v in
                    if Int(v.rounded()) != deviceValue { onChange(v.rounded()) }
                }
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private func reloadDevices() { devices = SennheiserClient.candidateDevices() }
    private func autoConnect() { if !client.isConnected, let d = devices.first { client.connect(to: d) } }
}

/// Subtle vertical gradient window background.
private struct WindowBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor)],
                       startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
}
