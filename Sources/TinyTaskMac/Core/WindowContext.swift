import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum WindowContextError: Error, LocalizedError {
    case noFrontmostApplication
    case noFocusedWindow

    var errorDescription: String? {
        switch self {
        case .noFrontmostApplication:
            return "No frontmost application was found."
        case .noFocusedWindow:
            return "No focused window was found."
        }
    }
}

struct WindowValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

public struct WindowTargetMatcher {
    public static func matches(recorded: WindowTarget, candidate: WindowTarget, mode: TargetLockMode, tolerance: CGFloat = 2.0) -> Bool {
        guard recorded.bundleIdentifier == candidate.bundleIdentifier else {
            return false
        }

        switch mode {
        case .appLevel:
            return true
        case .exactWindow:
            return matchesWindowIdentity(recorded: recorded, candidate: candidate, tolerance: tolerance)
        }
    }

    static func matchesWindowIdentity(recorded: WindowTarget, candidate: WindowTarget, tolerance: CGFloat = 2.0) -> Bool {
        recorded.windowTitleHash == candidate.windowTitleHash &&
            recorded.role == candidate.role &&
            recorded.subrole == candidate.subrole &&
            recorded.displayID == candidate.displayID &&
            abs(recorded.backingScale - candidate.backingScale) < 0.01 &&
            recorded.frame.isApproximatelyEqual(to: candidate.frame, tolerance: tolerance)
    }
}

struct ResolvedTargetWindow {
    let application: NSRunningApplication
    let appElement: AXUIElement
    let windowElement: AXUIElement
    let target: WindowTarget
}

enum WindowContextResolver {
    static func captureFrontmostTarget(excludingBundleIdentifiers: Set<String> = []) throws -> WindowTarget {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw WindowContextError.noFrontmostApplication
        }

        if let bundleID = application.bundleIdentifier, excludingBundleIdentifiers.contains(bundleID) {
            throw WindowContextError.noFrontmostApplication
        }

        guard let resolved = resolveFocusedWindow(for: application) else {
            throw WindowContextError.noFocusedWindow
        }

        return resolved.target
    }

    static func validateDisplayLayout(for document: MacroDocument) -> WindowValidationError? {
        let currentDisplays = DisplayLayout.snapshot()
        guard DisplayLayout.matchesRecorded(document.displays, current: currentDisplays) else {
            return WindowValidationError(message: "Display layout changed. Restore the recorded monitor arrangement before playback.")
        }

        return nil
    }

    static func resolvePlaybackTarget(for document: MacroDocument, source: PlaybackTargetSource) -> Result<PlaybackTargetContext, WindowValidationError> {
        switch source {
        case .recorded:
            return resolveRecordedPlaybackTarget(target: document.target, lockMode: document.settings.targetLockMode)
        case let .preferredApp(app):
            return resolvePreferredPlaybackTarget(recordedTarget: document.target, preferredApp: app)
        }
    }

    static func isFrontmost(target: WindowTarget) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleIdentifier
    }

    static func refocus(target: WindowTarget, lockMode: TargetLockMode) -> Bool {
        guard let resolved = findMatchingWindow(target: target, lockMode: lockMode) else {
            return false
        }

        let activated = resolved.application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        _ = AXUIElementSetAttributeValue(resolved.appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(resolved.windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(resolved.windowElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return activated
    }

    static func findMatchingWindow(target: WindowTarget, lockMode: TargetLockMode) -> ResolvedTargetWindow? {
        let matchingApps = runningApplications(matching: target.bundleIdentifier)

        switch lockMode {
        case .exactWindow:
            return findExactWindow(target: target, among: matchingApps)
        case .appLevel:
            return resolveAppLevelWindow(among: matchingApps)
        }
    }

    private static func resolveRecordedPlaybackTarget(target: WindowTarget, lockMode: TargetLockMode) -> Result<PlaybackTargetContext, WindowValidationError> {
        let matchingApps = runningApplications(matching: target.bundleIdentifier)
        guard !matchingApps.isEmpty else {
            return .failure(WindowValidationError(message: "The recorded target window is not available."))
        }

        switch lockMode {
        case .exactWindow:
            if let resolved = findExactWindow(target: target, among: matchingApps) {
                return .success(PlaybackTargetContext(source: .recorded, target: resolved.target, lockMode: .exactWindow))
            }

            if resolveAppLevelWindow(among: matchingApps) != nil {
                return .failure(WindowValidationError(message: "The target window geometry or identity changed. Restore the original layout before playback."))
            }

            return .failure(WindowValidationError(message: "The recorded target window is not available."))
        case .appLevel:
            guard let resolved = resolveAppLevelWindow(among: matchingApps) else {
                return .failure(WindowValidationError(message: "The recorded target window is not available."))
            }

            return .success(PlaybackTargetContext(source: .recorded, target: resolved.target, lockMode: .appLevel))
        }
    }

    private static func resolvePreferredPlaybackTarget(recordedTarget: WindowTarget, preferredApp: PreferredPlaybackApp) -> Result<PlaybackTargetContext, WindowValidationError> {
        let matchingApps = runningApplications(matching: preferredApp.bundleIdentifier)
        guard !matchingApps.isEmpty else {
            return .failure(WindowValidationError(message: "Launch \(preferredApp.applicationName) before playback."))
        }

        if let resolved = findWindowMatchingIdentity(target: recordedTarget, among: matchingApps) {
            return .success(PlaybackTargetContext(source: .preferredApp(preferredApp), target: resolved.target, lockMode: .exactWindow))
        }

        guard let resolved = resolveAppLevelWindow(among: matchingApps) else {
            return .failure(WindowValidationError(message: "The saved playback app is running but no usable window is available."))
        }

        return .success(PlaybackTargetContext(source: .preferredApp(preferredApp), target: resolved.target, lockMode: .appLevel))
    }

    private static func runningApplications(matching bundleIdentifier: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }
                return (lhs.localizedName ?? lhs.bundleIdentifier ?? "") < (rhs.localizedName ?? rhs.bundleIdentifier ?? "")
            }
    }

    private static func findExactWindow(target: WindowTarget, among applications: [NSRunningApplication]) -> ResolvedTargetWindow? {
        for application in applications {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = copyWindows(for: appElement) else {
                continue
            }

            for window in windows {
                guard let candidate = makeWindowTarget(from: window, application: application) else {
                    continue
                }

                if WindowTargetMatcher.matches(recorded: target, candidate: candidate, mode: .exactWindow) {
                    return ResolvedTargetWindow(
                        application: application,
                        appElement: appElement,
                        windowElement: window,
                        target: candidate
                    )
                }
            }
        }

        return nil
    }

    private static func findWindowMatchingIdentity(target: WindowTarget, among applications: [NSRunningApplication]) -> ResolvedTargetWindow? {
        for application in applications {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = copyWindows(for: appElement) else {
                continue
            }

            for window in windows {
                guard let candidate = makeWindowTarget(from: window, application: application) else {
                    continue
                }

                if WindowTargetMatcher.matchesWindowIdentity(recorded: target, candidate: candidate) {
                    return ResolvedTargetWindow(
                        application: application,
                        appElement: appElement,
                        windowElement: window,
                        target: candidate
                    )
                }
            }
        }

        return nil
    }

    private static func resolveAppLevelWindow(among applications: [NSRunningApplication]) -> ResolvedTargetWindow? {
        for application in applications {
            if let focused = resolveFocusedWindow(for: application) {
                return focused
            }

            if let primary = resolvePrimaryWindow(for: application) {
                return primary
            }
        }

        return nil
    }

    private static func resolveFocusedWindow(for application: NSRunningApplication) -> ResolvedTargetWindow? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        guard let focusedWindowValue = copyAttribute(kAXFocusedWindowAttribute, from: appElement) else {
            return nil
        }

        let window = unsafeDowncast(focusedWindowValue, to: AXUIElement.self)
        guard let target = makeWindowTarget(from: window, application: application) else {
            return nil
        }

        return ResolvedTargetWindow(
            application: application,
            appElement: appElement,
            windowElement: window,
            target: target
        )
    }

    private static func resolvePrimaryWindow(for application: NSRunningApplication) -> ResolvedTargetWindow? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        guard
            let windows = copyWindows(for: appElement),
            let window = windows.first,
            let target = makeWindowTarget(from: window, application: application)
        else {
            return nil
        }

        return ResolvedTargetWindow(
            application: application,
            appElement: appElement,
            windowElement: window,
            target: target
        )
    }

    private static func copyWindows(for application: AXUIElement) -> [AXUIElement]? {
        guard let value = copyAttribute(kAXWindowsAttribute, from: application) else {
            return nil
        }

        let array = unsafeDowncast(value, to: NSArray.self)
        return array.map { unsafeDowncast($0 as AnyObject, to: AXUIElement.self) }
    }

    private static func makeWindowTarget(from window: AXUIElement, application: NSRunningApplication) -> WindowTarget? {
        let title = (copyAttribute(kAXTitleAttribute, from: window) as? String) ?? ""
        let role = (copyAttribute(kAXRoleAttribute, from: window) as? String) ?? ""
        let subrole = (copyAttribute(kAXSubroleAttribute, from: window) as? String) ?? ""

        guard
            let positionValue = copyAttribute(kAXPositionAttribute, from: window),
            let sizeValue = copyAttribute(kAXSizeAttribute, from: window)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard
            AXValueGetType(positionValue as! AXValue) == .cgPoint,
            AXValueGetType(sizeValue as! AXValue) == .cgSize,
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }

        let frame = CGRect(origin: position, size: size)
        let display = DisplayLayout.descriptor(containing: CGPoint(x: frame.midX, y: frame.midY))
        let bundleIdentifier = application.bundleIdentifier ?? application.localizedName ?? "unknown.bundle"
        let appName = application.localizedName ?? bundleIdentifier

        return WindowTarget(
            bundleIdentifier: bundleIdentifier,
            applicationName: appName,
            windowTitle: title,
            windowTitleHash: fnv1a64(title),
            role: role,
            subrole: subrole,
            frame: frame,
            displayID: display?.id ?? 0,
            backingScale: display?.scale ?? 1.0
        )
    }

    private static func copyAttribute(_ name: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
        return value
    }
}
