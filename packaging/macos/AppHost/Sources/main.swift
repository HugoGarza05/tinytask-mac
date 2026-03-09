import AppKit
import TinyTaskMacKit

@MainActor
private func runTinyTaskMac() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}

runTinyTaskMac()
