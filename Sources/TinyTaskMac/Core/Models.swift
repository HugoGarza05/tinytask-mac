import AppKit
import Foundation

public enum PlaybackMode: UInt8, CaseIterable, Sendable {
    case strict = 0
    case scaled = 1

    var title: String {
        switch self {
        case .strict: return "Strict"
        case .scaled: return "Scaled"
        }
    }
}

public enum TargetLockMode: UInt8, CaseIterable, Sendable {
    case exactWindow = 0
    case appLevel = 1

    var title: String {
        switch self {
        case .exactWindow: return "Exact Window"
        case .appLevel: return "App Level"
        }
    }
}

public enum RepeatMode: UInt8, CaseIterable, Sendable {
    case once = 0
    case infinite = 1

    var title: String {
        switch self {
        case .once: return "Once"
        case .infinite: return "Infinite"
        }
    }
}

public enum MacroEventKind: UInt8, Sendable {
    case mouseMove = 0
    case leftMouseDown = 1
    case leftMouseUp = 2
    case rightMouseDown = 3
    case rightMouseUp = 4
    case otherMouseDown = 5
    case otherMouseUp = 6
    case leftMouseDragged = 7
    case rightMouseDragged = 8
    case otherMouseDragged = 9
    case scroll = 10
    case keyDown = 11
    case keyUp = 12
    case flagsChanged = 13

    init?(eventType: CGEventType) {
        switch eventType {
        case .mouseMoved: self = .mouseMove
        case .leftMouseDown: self = .leftMouseDown
        case .leftMouseUp: self = .leftMouseUp
        case .rightMouseDown: self = .rightMouseDown
        case .rightMouseUp: self = .rightMouseUp
        case .otherMouseDown: self = .otherMouseDown
        case .otherMouseUp: self = .otherMouseUp
        case .leftMouseDragged: self = .leftMouseDragged
        case .rightMouseDragged: self = .rightMouseDragged
        case .otherMouseDragged: self = .otherMouseDragged
        case .scrollWheel: self = .scroll
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        default: return nil
        }
    }

    var cgEventType: CGEventType {
        switch self {
        case .mouseMove: return .mouseMoved
        case .leftMouseDown: return .leftMouseDown
        case .leftMouseUp: return .leftMouseUp
        case .rightMouseDown: return .rightMouseDown
        case .rightMouseUp: return .rightMouseUp
        case .otherMouseDown: return .otherMouseDown
        case .otherMouseUp: return .otherMouseUp
        case .leftMouseDragged: return .leftMouseDragged
        case .rightMouseDragged: return .rightMouseDragged
        case .otherMouseDragged: return .otherMouseDragged
        case .scroll: return .scrollWheel
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        case .flagsChanged: return .flagsChanged
        }
    }

    var isMouseEvent: Bool {
        switch self {
        case .scroll, .keyDown, .keyUp, .flagsChanged:
            return false
        default:
            return true
        }
    }
}

public struct DisplayDescriptor: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: Double

    public init(id: UInt32, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

public struct WindowTarget: Equatable, Sendable {
    public let bundleIdentifier: String
    public let applicationName: String
    public let windowTitle: String
    public let windowTitleHash: UInt64
    public let role: String
    public let subrole: String
    public let frame: CGRect
    public let displayID: UInt32
    public let backingScale: Double

    public init(bundleIdentifier: String, applicationName: String, windowTitle: String, windowTitleHash: UInt64, role: String, subrole: String, frame: CGRect, displayID: UInt32, backingScale: Double) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.windowTitleHash = windowTitleHash
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.displayID = displayID
        self.backingScale = backingScale
    }
}

struct PreferredPlaybackApp: Equatable, Codable, Sendable {
    var bundleIdentifier: String
    var applicationName: String
}

enum PlaybackTargetSource: Equatable, Sendable {
    case recorded
    case preferredApp(PreferredPlaybackApp)
}

struct PlaybackTargetContext: Equatable, Sendable {
    let source: PlaybackTargetSource
    let target: WindowTarget
    let lockMode: TargetLockMode

    var applicationName: String {
        switch source {
        case .recorded:
            return target.applicationName
        case let .preferredApp(app):
            return app.applicationName
        }
    }
}

public struct MacroSettings: Equatable, Sendable {
    public var playbackMode: PlaybackMode
    public var targetLockMode: TargetLockMode
    public var repeatMode: RepeatMode
    public var playbackSpeedMultiplier: Double

    public init(playbackMode: PlaybackMode, targetLockMode: TargetLockMode, repeatMode: RepeatMode, playbackSpeedMultiplier: Double) {
        self.playbackMode = playbackMode
        self.targetLockMode = targetLockMode
        self.repeatMode = repeatMode
        self.playbackSpeedMultiplier = playbackSpeedMultiplier
    }
}

public struct MacroEventRecord: Equatable, Sendable {
    public static let recordVersion: UInt16 = 1

    public let kind: MacroEventKind
    public let flagsRaw: UInt64
    public let deltaNanos: UInt64
    public let x: Double
    public let y: Double
    public let keyCode: UInt16
    public let buttonNumber: UInt8
    public let clickCount: UInt8
    public let scrollX: Int32
    public let scrollY: Int32
    public let scrollUnit: UInt8
    public let displayID: UInt32
    public let modifierFlagsRaw: UInt64

    public init(kind: MacroEventKind, flagsRaw: UInt64, deltaNanos: UInt64, x: Double, y: Double, keyCode: UInt16, buttonNumber: UInt8, clickCount: UInt8, scrollX: Int32, scrollY: Int32, scrollUnit: UInt8, displayID: UInt32, modifierFlagsRaw: UInt64) {
        self.kind = kind
        self.flagsRaw = flagsRaw
        self.deltaNanos = deltaNanos
        self.x = x
        self.y = y
        self.keyCode = keyCode
        self.buttonNumber = buttonNumber
        self.clickCount = clickCount
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.scrollUnit = scrollUnit
        self.displayID = displayID
        self.modifierFlagsRaw = modifierFlagsRaw
    }
}

public struct MacroDocument: Equatable, Sendable {
    public static let fileExtension = "tmacro"
    public static let appVersion = "0.1.0"

    public var fileURL: URL?
    public let createdAt: Date
    public var displays: [DisplayDescriptor]
    public var displayLayoutHash: UInt64
    public var target: WindowTarget
    public var settings: MacroSettings
    public var events: [MacroEventRecord]
    public var isStrictRunCompromised = false

    public init(fileURL: URL?, createdAt: Date, displays: [DisplayDescriptor], displayLayoutHash: UInt64, target: WindowTarget, settings: MacroSettings, events: [MacroEventRecord], isStrictRunCompromised: Bool = false) {
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.displays = displays
        self.displayLayoutHash = displayLayoutHash
        self.target = target
        self.settings = settings
        self.events = events
        self.isStrictRunCompromised = isStrictRunCompromised
    }
}

public struct RoutineEntryReference: Equatable, Codable, Sendable {
    public var relativePath: String?
    public var absolutePath: String?

    public init(relativePath: String? = nil, absolutePath: String? = nil) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
    }

    public var displayName: String {
        let candidate = relativePath ?? absolutePath ?? "Unassigned Macro"
        return URL(fileURLWithPath: candidate).lastPathComponent
    }

    public func resolvedURL(relativeTo routineFileURL: URL?) -> URL? {
        if let relativePath, let routineFileURL {
            let baseDirectoryURL = routineFileURL.deletingLastPathComponent()
            let candidate = baseDirectoryURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let absolutePath {
            let candidate = URL(fileURLWithPath: absolutePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let relativePath, let routineFileURL {
            return routineFileURL.deletingLastPathComponent().appendingPathComponent(relativePath)
        }

        if let absolutePath {
            return URL(fileURLWithPath: absolutePath)
        }

        return nil
    }
}

public struct RoutineMainEntry: Equatable, Codable, Sendable {
    public var macroReference: RoutineEntryReference

    public init(macroReference: RoutineEntryReference = RoutineEntryReference()) {
        self.macroReference = macroReference
    }
}

public struct RoutineInterruptEntry: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var macroReference: RoutineEntryReference
    public var intervalMinutes: Int
    public var priority: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        macroReference: RoutineEntryReference = RoutineEntryReference(),
        intervalMinutes: Int,
        priority: Int,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.macroReference = macroReference
        self.intervalMinutes = intervalMinutes
        self.priority = priority
        self.isEnabled = isEnabled
    }
}

public struct RoutineDocument: Equatable, Sendable {
    public static let fileExtension = "troutine"
    public static let appVersion = "0.1.0"

    public var fileURL: URL?
    public var createdAt: Date
    public var name: String
    public var targetAppBundleIdentifier: String?
    public var targetAppName: String?
    public var mainEntry: RoutineMainEntry?
    public var interruptEntries: [RoutineInterruptEntry]

    public init(
        fileURL: URL?,
        createdAt: Date,
        name: String,
        targetAppBundleIdentifier: String? = nil,
        targetAppName: String? = nil,
        mainEntry: RoutineMainEntry? = nil,
        interruptEntries: [RoutineInterruptEntry]
    ) {
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.name = name
        self.targetAppBundleIdentifier = targetAppBundleIdentifier
        self.targetAppName = targetAppName
        self.mainEntry = mainEntry
        self.interruptEntries = interruptEntries
    }
}

public enum RoutineExecutionKind: Equatable, Sendable {
    case main
    case interrupt(UUID)
}

public struct RoutineExecutionRequest: Equatable, Sendable {
    public var kind: RoutineExecutionKind
    public var entryName: String

    public init(kind: RoutineExecutionKind, entryName: String) {
        self.kind = kind
        self.entryName = entryName
    }
}

public enum RoutineSchedulerCommand: Equatable, Sendable {
    case startMain
    case startInterrupt(UUID)
    case stopCurrentForInterrupts
}

public struct RoutineRuntimeState: Equatable, Sendable {
    public var routineName: String
    public var isRunning: Bool
    public var currentEntryName: String?
    public var statusText: String
    public var nextDueText: String?

    public init(
        routineName: String,
        isRunning: Bool,
        currentEntryName: String?,
        statusText: String,
        nextDueText: String?
    ) {
        self.routineName = routineName
        self.isRunning = isRunning
        self.currentEntryName = currentEntryName
        self.statusText = statusText
        self.nextDueText = nextDueText
    }
}

public struct PermissionChecklistState: Equatable, Sendable {
    public var accessibilityGranted: Bool
    public var inputMonitoringGranted: Bool

    public init(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
    }

    var status: PermissionState {
        switch (accessibilityGranted, inputMonitoringGranted) {
        case (true, true):
            return .granted
        case (false, true):
            return .needsAccessibility
        case (true, false):
            return .needsInputMonitoring
        case (false, false):
            return .needsAccessibilityAndInputMonitoring
        }
    }

    public var isGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }
}

public struct AppSnapshot: Sendable {
    public var currentFileName: String
    public var routineFileName: String
    public var statusText: String
    public var warningText: String?
    public var isRecording: Bool
    public var isPlaying: Bool
    public var hasMacroLoaded: Bool
    public var hasRoutineLoaded: Bool
    public var isRoutineRunning: Bool
    public var routineName: String?
    public var routineCurrentEntryName: String?
    public var routineStatusText: String?
    public var routineNextDueText: String?
    public var alwaysOnTop: Bool
    public var lockPlaybackTargetToFront: Bool
    public var preferredPlaybackAppName: String?
    public var preferredPlaybackAppBundleIdentifier: String?
    public var isPreferredPlaybackAppRunning: Bool
    public var permissionChecklist: PermissionChecklistState
    public var shouldBlockAutomation: Bool
    public var hasDismissedSetupWindow: Bool
    public var playbackMode: PlaybackMode
    public var targetLockMode: TargetLockMode
    public var repeatMode: RepeatMode
    public var playbackSpeedMultiplier: Double
}

enum PermissionState: Equatable {
    case granted
    case needsAccessibility
    case needsInputMonitoring
    case needsAccessibilityAndInputMonitoring
}

public struct HotKeyDescriptor: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var displayText: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, displayText: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayText = displayText
    }
}

public enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case toggleRecording
    case togglePlayback
    case emergencyStop

    var title: String {
        switch self {
        case .toggleRecording: return "Toggle Recording"
        case .togglePlayback: return "Toggle Playback"
        case .emergencyStop: return "Emergency Stop"
        }
    }
}

extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
        abs(origin.y - other.origin.y) <= tolerance &&
        abs(size.width - other.size.width) <= tolerance &&
        abs(size.height - other.size.height) <= tolerance
    }
}

extension Notification.Name {
    static let appStateDidChange = Notification.Name("AppStateDidChange")
    static let openPreferencesWindow = Notification.Name("OpenPreferencesWindow")
    static let openRoutineEditorWindow = Notification.Name("OpenRoutineEditorWindow")
    static let openSetupWindow = Notification.Name("OpenSetupWindow")
}
