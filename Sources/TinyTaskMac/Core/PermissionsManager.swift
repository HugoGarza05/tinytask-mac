import AppKit
@preconcurrency import ApplicationServices
import Foundation

@MainActor
final class PermissionsManager {
    func checklistState(promptForAccessibility: Bool) -> PermissionChecklistState {
        PermissionChecklistState(
            accessibilityGranted: Self.isAccessibilityGranted(prompt: promptForAccessibility),
            inputMonitoringGranted: Self.isInputMonitoringGranted()
        )
    }

    func currentState(promptForAccessibility: Bool) -> PermissionState {
        checklistState(promptForAccessibility: promptForAccessibility).status
    }

    static func isAccessibilityGranted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isInputMonitoringGranted() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }

    func openAccessibilitySettings() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        let granted = Self.isAccessibilityGranted(prompt: true)
        if !granted {
            openAccessibilitySettings()
        }
        return granted
    }

    func openInputMonitoringSettings() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func instructions(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "Permissions are granted."
        case .needsAccessibility:
            return "Enable TinyTaskMac in Privacy & Security > Accessibility, then relaunch or retry."
        case .needsInputMonitoring:
            return "Enable TinyTaskMac in Privacy & Security > Input Monitoring, then relaunch or retry."
        case .needsAccessibilityAndInputMonitoring:
            return "Enable TinyTaskMac in both Accessibility and Input Monitoring, then relaunch or retry."
        }
    }

    private func openPane(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
