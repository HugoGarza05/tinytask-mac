import CoreGraphics
import Foundation
import TinyTaskMacKit

@main
struct TinyTaskMacSelfTest {
    static func main() throws {
        let displays = [
            DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2.0)
        ]

        let original = makeMacro(
            displays: displays,
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            windowTitle: "Untitled"
        )

        try verifyMacroRoundTrip(original)
        try verifyWindowTargetMatching(original)
        try verifyRoutineRoundTrip(displays: displays)
        try verifyRoutineSchedulerPriority()
        try verifyRoutineSchedulerOverdueCollapse()

        print("TinyTaskMac self-test passed.")
    }

    private static func verifyMacroRoundTrip(_ original: MacroDocument) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(MacroDocument.fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }

        try MacroFileCodec.save(original, to: url)
        let loaded = try MacroFileCodec.load(from: url)

        guard loaded.displayLayoutHash == original.displayLayoutHash else {
            throw SelfTestError("Display hash roundtrip failed.")
        }
        guard loaded.target == original.target else {
            throw SelfTestError("Target roundtrip failed.")
        }
        guard loaded.settings == original.settings else {
            throw SelfTestError("Settings roundtrip failed.")
        }
        guard loaded.events == original.events else {
            throw SelfTestError("Event roundtrip failed.")
        }
    }

    private static func verifyWindowTargetMatching(_ original: MacroDocument) throws {
        let moved = WindowTarget(
            bundleIdentifier: original.target.bundleIdentifier,
            applicationName: original.target.applicationName,
            windowTitle: original.target.windowTitle,
            windowTitleHash: original.target.windowTitleHash,
            role: original.target.role,
            subrole: original.target.subrole,
            frame: CGRect(
                x: original.target.frame.origin.x + 30,
                y: original.target.frame.origin.y + 30,
                width: original.target.frame.width,
                height: original.target.frame.height
            ),
            displayID: original.target.displayID,
            backingScale: original.target.backingScale
        )

        guard WindowTargetMatcher.matches(recorded: original.target, candidate: original.target, mode: .exactWindow) else {
            throw SelfTestError("Exact-window match should succeed for identical targets.")
        }
        guard !WindowTargetMatcher.matches(recorded: original.target, candidate: moved, mode: .exactWindow) else {
            throw SelfTestError("Exact-window match should fail when geometry drifts.")
        }
        guard WindowTargetMatcher.matches(recorded: original.target, candidate: moved, mode: .appLevel) else {
            throw SelfTestError("App-level matching should accept geometry drift.")
        }
    }

    private static func verifyRoutineRoundTrip(displays: [DisplayDescriptor]) throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let mainMacroURL = tempDirectory.appendingPathComponent("MainLoop").appendingPathExtension(MacroDocument.fileExtension)
        let relogMacroURL = tempDirectory.appendingPathComponent("Relog").appendingPathExtension(MacroDocument.fileExtension)
        let routineURL = tempDirectory.appendingPathComponent("RobloxRoutine").appendingPathExtension(RoutineDocument.fileExtension)

        try MacroFileCodec.save(
            makeMacro(
                displays: displays,
                bundleIdentifier: "com.roblox.Roblox",
                applicationName: "Roblox",
                windowTitle: "Main"
            ),
            to: mainMacroURL
        )
        try MacroFileCodec.save(
            makeMacro(
                displays: displays,
                bundleIdentifier: "com.roblox.Roblox",
                applicationName: "Roblox",
                windowTitle: "Relog"
            ),
            to: relogMacroURL
        )

        let routine = RoutineDocument(
            fileURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Roblox Routine",
            targetAppBundleIdentifier: "com.roblox.Roblox",
            targetAppName: "Roblox",
            mainEntry: RoutineMainEntry(
                macroReference: RoutineEntryReference(absolutePath: mainMacroURL.path)
            ),
            interruptEntries: [
                RoutineInterruptEntry(
                    name: "Relog",
                    macroReference: RoutineEntryReference(absolutePath: relogMacroURL.path),
                    intervalMinutes: 120,
                    priority: 1,
                    isEnabled: true
                )
            ]
        )

        try RoutineFileCodec.save(routine, to: routineURL)
        let loaded = try RoutineFileCodec.load(from: routineURL)

        guard loaded.name == routine.name else {
            throw SelfTestError("Routine name roundtrip failed.")
        }
        guard loaded.targetAppBundleIdentifier == routine.targetAppBundleIdentifier else {
            throw SelfTestError("Routine target bundle roundtrip failed.")
        }
        guard loaded.mainEntry?.macroReference.relativePath != nil else {
            throw SelfTestError("Routine save should store a relative path for nearby macro files.")
        }
        guard loaded.mainEntry?.macroReference.resolvedURL(relativeTo: routineURL) == mainMacroURL else {
            throw SelfTestError("Routine main macro should resolve relative to the routine file.")
        }
        guard loaded.interruptEntries.first?.macroReference.resolvedURL(relativeTo: routineURL) == relogMacroURL else {
            throw SelfTestError("Routine interrupt macro should resolve relative to the routine file.")
        }
    }

    private static func verifyRoutineSchedulerPriority() throws {
        let highPriorityID = UUID()
        let lowPriorityID = UUID()
        let routine = RoutineDocument(
            fileURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Priority",
            targetAppBundleIdentifier: "com.roblox.Roblox",
            targetAppName: "Roblox",
            mainEntry: RoutineMainEntry(),
            interruptEntries: [
                RoutineInterruptEntry(id: lowPriorityID, name: "Cleanup", intervalMinutes: 5, priority: 5, isEnabled: true),
                RoutineInterruptEntry(id: highPriorityID, name: "Relog", intervalMinutes: 10, priority: 1, isEnabled: true)
            ]
        )

        let scheduler = RoutineScheduler(routine: routine)
        let startDate = Date(timeIntervalSince1970: 0)

        guard scheduler.start(at: startDate) == .startMain else {
            throw SelfTestError("Routine scheduler should start with the main macro.")
        }
        guard scheduler.tick(now: startDate.addingTimeInterval(4 * 60)) == nil else {
            throw SelfTestError("Routine scheduler should not preempt before an interrupt is due.")
        }
        guard scheduler.tick(now: startDate.addingTimeInterval(10 * 60)) == .stopCurrentForInterrupts else {
            throw SelfTestError("Routine scheduler should stop the main macro when interrupts become due.")
        }

        guard scheduler.playbackFinished(at: startDate.addingTimeInterval(10 * 60)) == .startInterrupt(highPriorityID) else {
            throw SelfTestError("Highest-priority interrupt should run first.")
        }
        guard scheduler.playbackFinished(at: startDate.addingTimeInterval(10 * 60 + 10)) == .startInterrupt(lowPriorityID) else {
            throw SelfTestError("Remaining overdue interrupts should run next in priority order.")
        }
        guard scheduler.playbackFinished(at: startDate.addingTimeInterval(10 * 60 + 20)) == .startMain else {
            throw SelfTestError("Routine scheduler should return to the main macro after interrupts complete.")
        }
    }

    private static func verifyRoutineSchedulerOverdueCollapse() throws {
        let interruptID = UUID()
        let routine = RoutineDocument(
            fileURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Overdue",
            targetAppBundleIdentifier: "com.roblox.Roblox",
            targetAppName: "Roblox",
            mainEntry: RoutineMainEntry(),
            interruptEntries: [
                RoutineInterruptEntry(id: interruptID, name: "Relog", intervalMinutes: 5, priority: 1, isEnabled: true)
            ]
        )

        let scheduler = RoutineScheduler(routine: routine)
        let startDate = Date(timeIntervalSince1970: 0)

        _ = scheduler.start(at: startDate)
        guard scheduler.tick(now: startDate.addingTimeInterval(25 * 60)) == .stopCurrentForInterrupts else {
            throw SelfTestError("Overdue interrupt should still request only one preemption.")
        }
        guard scheduler.playbackFinished(at: startDate.addingTimeInterval(25 * 60)) == .startInterrupt(interruptID) else {
            throw SelfTestError("Overdue interrupt should run once after preemption.")
        }
        guard scheduler.playbackFinished(at: startDate.addingTimeInterval(26 * 60)) == .startMain else {
            throw SelfTestError("Routine scheduler should not backfill multiple missed interrupt runs.")
        }
    }

    private static func makeMacro(
        displays: [DisplayDescriptor],
        bundleIdentifier: String,
        applicationName: String,
        windowTitle: String
    ) -> MacroDocument {
        MacroDocument(
            fileURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            displays: displays,
            displayLayoutHash: DisplayLayout.hash(displays),
            target: WindowTarget(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                windowTitle: windowTitle,
                windowTitleHash: 42,
                role: "AXWindow",
                subrole: "AXStandardWindow",
                frame: CGRect(x: 120, y: 180, width: 900, height: 600),
                displayID: 1,
                backingScale: 2.0
            ),
            settings: MacroSettings(
                playbackMode: .strict,
                targetLockMode: .exactWindow,
                repeatMode: .once,
                playbackSpeedMultiplier: 1.0
            ),
            events: [
                MacroEventRecord(
                    kind: .mouseMove,
                    flagsRaw: 0,
                    deltaNanos: 0,
                    x: 220,
                    y: 420,
                    keyCode: 0,
                    buttonNumber: 0,
                    clickCount: 0,
                    scrollX: 0,
                    scrollY: 0,
                    scrollUnit: 0,
                    displayID: 1,
                    modifierFlagsRaw: 0
                ),
                MacroEventRecord(
                    kind: .keyDown,
                    flagsRaw: 0,
                    deltaNanos: 8_000_000,
                    x: 0,
                    y: 0,
                    keyCode: 0x0F,
                    buttonNumber: 0,
                    clickCount: 0,
                    scrollX: 0,
                    scrollY: 0,
                    scrollUnit: 0,
                    displayID: 1,
                    modifierFlagsRaw: 0
                )
            ]
        )
    }
}

private struct SelfTestError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
