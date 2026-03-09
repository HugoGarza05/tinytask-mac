import AppKit
import Carbon
import Foundation

final class HotKeyCenter {
    static let signature: FourCharCode = 0x544D_4143

    private var eventHandler: EventHandlerRef?
    private var registered: [HotKeyAction: EventHotKeyRef] = [:]
    private var hotKeys: [HotKeyAction: HotKeyDescriptor] = [:]

    var onHotKey: ((HotKeyAction) -> Void)?

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
    }

    func register(_ hotKeys: [HotKeyAction: HotKeyDescriptor]) {
        unregisterAll()
        self.hotKeys = hotKeys

        for action in HotKeyAction.allCases {
            guard let descriptor = hotKeys[action] else {
                continue
            }

            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotKeyID(for: action))
            RegisterEventHotKey(descriptor.keyCode, descriptor.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)

            if let reference {
                registered[action] = reference
            }
        }
    }

    func unregisterAll() {
        for (_, reference) in registered {
            UnregisterEventHotKey(reference)
        }
        registered.removeAll()
    }

    func currentHotKeys() -> [HotKeyAction: HotKeyDescriptor] {
        hotKeys
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else {
                return noErr
            }

            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            if let action = center.action(for: hotKeyID.id) {
                center.onHotKey?(action)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    private func hotKeyID(for action: HotKeyAction) -> UInt32 {
        switch action {
        case .toggleRecording:
            return 1
        case .togglePlayback:
            return 2
        case .emergencyStop:
            return 3
        }
    }

    private func action(for hotKeyID: UInt32) -> HotKeyAction? {
        switch hotKeyID {
        case 1:
            return .toggleRecording
        case 2:
            return .togglePlayback
        case 3:
            return .emergencyStop
        default:
            return nil
        }
    }

    static func descriptor(from event: NSEvent) -> HotKeyDescriptor? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        let characters = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !characters.isEmpty else {
            return nil
        }

        let display = displayText(for: modifiers, key: characters)
        return HotKeyDescriptor(keyCode: keyCode, carbonModifiers: modifiers, displayText: display)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return modifiers
    }

    static func displayText(for modifiers: UInt32, key: String) -> String {
        var parts = ""

        if modifiers & UInt32(controlKey) != 0 {
            parts += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts += "⌘"
        }

        return parts + key
    }
}
