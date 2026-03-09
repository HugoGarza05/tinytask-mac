import AppKit
import Carbon
import Foundation

@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private let defaults: UserDefaults
    private let hotKeyPrefix = "hotkey."
    private let playbackModeKey = "playbackMode"
    private let targetLockKey = "targetLockMode"
    private let repeatModeKey = "repeatMode"
    private let playbackSpeedKey = "playbackSpeed"
    private let alwaysOnTopKey = "alwaysOnTop"
    private let focusLockKey = "lockPlaybackTargetToFront"
    private let preferredPlaybackAppKey = "preferredPlaybackApp"
    private let setupOnboardingCompletedKey = "setupOnboardingCompleted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hotKeys() -> [HotKeyAction: HotKeyDescriptor] {
        var result = defaultHotKeys()

        for action in HotKeyAction.allCases {
            let key = hotKeyPrefix + action.rawValue
            guard let data = defaults.data(forKey: key) else {
                continue
            }

            if let descriptor = try? JSONDecoder().decode(HotKeyDescriptor.self, from: data) {
                result[action] = descriptor
            }
        }

        return result
    }

    func setHotKey(_ descriptor: HotKeyDescriptor, for action: HotKeyAction) {
        let key = hotKeyPrefix + action.rawValue
        if let data = try? JSONEncoder().encode(descriptor) {
            defaults.set(data, forKey: key)
        }
    }

    func resetHotKeys() {
        for action in HotKeyAction.allCases {
            defaults.removeObject(forKey: hotKeyPrefix + action.rawValue)
        }
    }

    func playbackMode() -> PlaybackMode {
        PlaybackMode(rawValue: UInt8(defaults.integer(forKey: playbackModeKey))) ?? .strict
    }

    func setPlaybackMode(_ value: PlaybackMode) {
        defaults.set(Int(value.rawValue), forKey: playbackModeKey)
    }

    func targetLockMode() -> TargetLockMode {
        TargetLockMode(rawValue: UInt8(defaults.integer(forKey: targetLockKey))) ?? .exactWindow
    }

    func setTargetLockMode(_ value: TargetLockMode) {
        defaults.set(Int(value.rawValue), forKey: targetLockKey)
    }

    func repeatMode() -> RepeatMode {
        RepeatMode(rawValue: UInt8(defaults.integer(forKey: repeatModeKey))) ?? .once
    }

    func setRepeatMode(_ value: RepeatMode) {
        defaults.set(Int(value.rawValue), forKey: repeatModeKey)
    }

    func playbackSpeed() -> Double {
        let speed = defaults.double(forKey: playbackSpeedKey)
        return speed == 0 ? 1.0 : speed
    }

    func setPlaybackSpeed(_ value: Double) {
        defaults.set(value, forKey: playbackSpeedKey)
    }

    func alwaysOnTop() -> Bool {
        if defaults.object(forKey: alwaysOnTopKey) == nil {
            return true
        }
        return defaults.bool(forKey: alwaysOnTopKey)
    }

    func setAlwaysOnTop(_ value: Bool) {
        defaults.set(value, forKey: alwaysOnTopKey)
    }

    func lockPlaybackTargetToFront() -> Bool {
        if defaults.object(forKey: focusLockKey) == nil {
            return true
        }
        return defaults.bool(forKey: focusLockKey)
    }

    func setLockPlaybackTargetToFront(_ value: Bool) {
        defaults.set(value, forKey: focusLockKey)
    }

    func preferredPlaybackApp() -> PreferredPlaybackApp? {
        guard let data = defaults.data(forKey: preferredPlaybackAppKey) else {
            return nil
        }

        return try? JSONDecoder().decode(PreferredPlaybackApp.self, from: data)
    }

    func setPreferredPlaybackApp(_ value: PreferredPlaybackApp?) {
        guard let value else {
            defaults.removeObject(forKey: preferredPlaybackAppKey)
            return
        }

        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: preferredPlaybackAppKey)
        }
    }

    func setupOnboardingCompleted() -> Bool {
        defaults.bool(forKey: setupOnboardingCompletedKey)
    }

    func setSetupOnboardingCompleted(_ value: Bool) {
        defaults.set(value, forKey: setupOnboardingCompletedKey)
    }

    private func defaultHotKeys() -> [HotKeyAction: HotKeyDescriptor] {
        [
            .toggleRecording: HotKeyDescriptor(keyCode: 15, carbonModifiers: UInt32(controlKey | optionKey | shiftKey), displayText: "⌃⌥⇧R"),
            .togglePlayback: HotKeyDescriptor(keyCode: 35, carbonModifiers: UInt32(controlKey | optionKey | shiftKey), displayText: "⌃⌥⇧P"),
            .emergencyStop: HotKeyDescriptor(keyCode: 47, carbonModifiers: UInt32(controlKey | optionKey | cmdKey), displayText: "⌃⌥⌘.")
        ]
    }
}
