import AppKit
import SwiftUI

if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    runProbe()   // connect to the real paired device, dump state, exit
    exit(0)
}

if CommandLine.arguments.contains("--services") {
    dumpServices()   // list SDP service records + RFCOMM channels of paired devices
    exit(0)
}

if CommandLine.arguments.contains("--sniff") {
    runSniff()       // connect with raw-frame logging; toggle ANC on the headset to capture frames
    exit(0)
}

if CommandLine.arguments.contains("--anctest") {
    runAncTest()     // drive ANC on/off + transparency commands and observe responses
    exit(0)
}

if CommandLine.arguments.contains("--transtest") {
    runTransTest()   // probe how the transparency LEVEL command behaves
    exit(0)
}

if CommandLine.arguments.contains("--eqprobe") {
    runEqProbe()     // discover the Equalizer command ids from device push frames
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let client = SennheiserClient()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: ContentView(client: client))
        window = NSWindow(contentViewController: hosting)
        window.title = "ZenControl"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 460, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // normal windowed app with Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
