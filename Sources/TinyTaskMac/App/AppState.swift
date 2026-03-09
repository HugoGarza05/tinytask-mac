import AppKit
import Foundation
import UniformTypeIdentifiers

private enum ActivePlaybackOwner {
    case none
    case singleMacro
    case routine
}

private enum PendingStartAction {
    case singleMacro
    case routine
}

private struct ResolvedRoutinePlan {
    var routine: RoutineDocument
    let targetApp: PreferredPlaybackApp
    let mainDocument: MacroDocument
    let interruptDocuments: [UUID: MacroDocument]
}

@MainActor
final class AppState: NSObject {
    private let permissionsManager = PermissionsManager()
    private let preferences = AppPreferences.shared
    private let recorderEngine = RecorderEngine()
    private lazy var playbackEngine = PlaybackEngine(syntheticMarker: recorderEngine.syntheticMarker)
    private let hotKeyCenter = HotKeyCenter()

    private let selfBundleIdentifier = Bundle.main.bundleIdentifier ?? "TinyTaskMac"

    private var currentDocument: MacroDocument?
    private var currentRoutine: RoutineDocument?
    private var resolvedRoutinePlan: ResolvedRoutinePlan?
    private var routineScheduler: RoutineScheduler?
    private var lastObservedExternalTarget: WindowTarget?
    private var hotKeys: [HotKeyAction: HotKeyDescriptor] = [:]
    private var focusTimer: Timer?
    private var routineTickTimer: Timer?
    private var activePlaybackToken: UUID?
    private var activePlaybackTarget: PlaybackTargetContext?
    private var activePlaybackDocument: MacroDocument?
    private var activePlaybackOwner: ActivePlaybackOwner = .none
    private var pendingStartAction: PendingStartAction?
    private var pendingStopStatus: String?

    private var isRecording = false
    private var isPlaying = false
    private var statusText = "Ready"
    private var warningText: String?

    private var playbackMode: PlaybackMode
    private var targetLockMode: TargetLockMode
    private var repeatMode: RepeatMode
    private var playbackSpeedMultiplier: Double
    private var alwaysOnTop: Bool
    private var lockPlaybackTargetToFront: Bool
    private var savedPreferredPlaybackApp: PreferredPlaybackApp?
    private var permissionChecklist: PermissionChecklistState
    private var setupOnboardingCompleted: Bool
    private var hasDismissedSetupWindow = false

    override init() {
        playbackMode = preferences.playbackMode()
        targetLockMode = preferences.targetLockMode()
        repeatMode = preferences.repeatMode()
        playbackSpeedMultiplier = preferences.playbackSpeed()
        alwaysOnTop = preferences.alwaysOnTop()
        lockPlaybackTargetToFront = preferences.lockPlaybackTargetToFront()
        savedPreferredPlaybackApp = preferences.preferredPlaybackApp()
        permissionChecklist = PermissionChecklistState(
            accessibilityGranted: PermissionsManager.isAccessibilityGranted(prompt: false),
            inputMonitoringGranted: PermissionsManager.isInputMonitoringGranted()
        )
        setupOnboardingCompleted = preferences.setupOnboardingCompleted()
        super.init()
    }

    func start() {
        hotKeys = preferences.hotKeys()
        hotKeyCenter.register(hotKeys)

        hotKeyCenter.onHotKey = { [weak self] action in
            DispatchQueue.main.async {
                guard let self else { return }
                self.recorderEngine.noteControlHotKeyTriggered()
                self.handleHotKey(action)
            }
        }

        recorderEngine.onHumanInputDuringPlayback = { [weak self] in
            Task { @MainActor in
                self?.markHumanInterference()
            }
        }

        recorderEngine.onTapFailure = { [weak self] message in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.statusText = "Setup required"
                self.warningText = message
                self.refreshPermissionState(promptForAccessibility: false)
                self.presentSetupWindow()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceRunningAppsDidChange(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceRunningAppsDidChange(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        _ = recorderEngine.ensureMonitoringStarted()
        refreshPermissionState(promptForAccessibility: false)
        observeCurrentExternalTarget()
        broadcastState()
    }

    func snapshot() -> AppSnapshot {
        let routineRuntime = routineScheduler?.runtimeState

        return AppSnapshot(
            currentFileName: currentDocument?.fileURL?.lastPathComponent ?? "Unsaved Macro",
            routineFileName: currentRoutine.map { $0.fileURL?.lastPathComponent ?? "Unsaved Routine" } ?? "No Routine",
            statusText: effectiveStatusText(),
            warningText: effectiveWarningText(),
            isRecording: isRecording,
            isPlaying: activePlaybackOwner == .singleMacro,
            hasMacroLoaded: currentDocument != nil,
            hasRoutineLoaded: currentRoutine != nil,
            isRoutineRunning: routineRuntime?.isRunning == true,
            routineName: currentRoutine?.name,
            routineCurrentEntryName: routineRuntime?.currentEntryName,
            routineStatusText: routineRuntime?.statusText ?? currentRoutineStatusPreview(),
            routineNextDueText: routineRuntime?.nextDueText,
            alwaysOnTop: alwaysOnTop,
            lockPlaybackTargetToFront: lockPlaybackTargetToFront,
            preferredPlaybackAppName: savedPreferredPlaybackApp?.applicationName,
            preferredPlaybackAppBundleIdentifier: savedPreferredPlaybackApp?.bundleIdentifier,
            isPreferredPlaybackAppRunning: isPreferredPlaybackAppRunning(),
            permissionChecklist: permissionChecklist,
            shouldBlockAutomation: !permissionChecklist.isGranted,
            hasDismissedSetupWindow: hasDismissedSetupWindow,
            playbackMode: playbackMode,
            targetLockMode: targetLockMode,
            repeatMode: repeatMode,
            playbackSpeedMultiplier: playbackSpeedMultiplier
        )
    }

    func shouldPresentSetupWindowOnLaunch() -> Bool {
        !setupOnboardingCompleted || !permissionChecklist.isGranted
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func togglePlayback() {
        if activePlaybackOwner == .routine || routineScheduler?.runtimeState.isRunning == true {
            stopRoutine(status: "Routine stopped")
            return
        }

        if activePlaybackOwner == .singleMacro {
            requestStopActivePlayback(status: "Playback stopped", pendingStart: nil)
        } else {
            startSinglePlaybackRequest()
        }
    }

    func emergencyStop() {
        if activePlaybackOwner == .routine || routineScheduler?.runtimeState.isRunning == true {
            stopRoutine(status: "Emergency stop triggered")
        } else if activePlaybackOwner == .singleMacro {
            requestStopActivePlayback(status: "Emergency stop triggered", pendingStart: nil)
        }

        if isRecording {
            stopRecording(status: "Recording aborted")
        }
    }

    func openMacro() {
        let panel = NSOpenPanel()
        if let type = UTType(filenameExtension: MacroDocument.fileExtension) {
            panel.allowedContentTypes = [type]
        } else {
            panel.allowedContentTypes = [.data]
        }
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openDocument(at: url)
    }

    func saveMacro() {
        guard var document = currentDocument else {
            presentAlert(title: "Nothing To Save", message: "Record or open a macro first.")
            return
        }

        applyCurrentSettings(to: &document)

        let url: URL
        if let fileURL = document.fileURL {
            url = fileURL
        } else {
            let panel = NSSavePanel()
            if let type = UTType(filenameExtension: MacroDocument.fileExtension) {
                panel.allowedContentTypes = [type]
            } else {
                panel.allowedContentTypes = [.data]
            }
            panel.nameFieldStringValue = "Macro.\(MacroDocument.fileExtension)"

            guard panel.runModal() == .OK, let selectedURL = panel.url else {
                return
            }
            url = selectedURL
        }

        do {
            try MacroFileCodec.save(document, to: url)
            document.fileURL = url
            currentDocument = document
            statusText = "Saved \(url.lastPathComponent)"
            broadcastState()
        } catch {
            presentAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }

    func openRoutine() {
        guard ensureRoutineIsEditable() else {
            return
        }

        let panel = NSOpenPanel()
        if let type = UTType(filenameExtension: RoutineDocument.fileExtension) {
            panel.allowedContentTypes = [type]
        } else {
            panel.allowedContentTypes = [.data]
        }
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openDocument(at: url)
    }

    func openDocument(at url: URL) {
        switch url.pathExtension.lowercased() {
        case MacroDocument.fileExtension:
            loadMacro(from: url)
        case RoutineDocument.fileExtension:
            loadRoutine(from: url)
        default:
            presentAlert(title: "Unsupported File", message: "TinyTaskMac can open .\(MacroDocument.fileExtension) and .\(RoutineDocument.fileExtension) files.")
        }
    }

    func saveRoutine() {
        guard ensureRoutineIsEditable() else {
            return
        }

        guard var routine = currentRoutine else {
            presentAlert(title: "Nothing To Save", message: "Create or open a routine first.")
            return
        }

        do {
            let resolvedPlan = try resolveRoutinePlan(for: routine)
            routine = resolvedPlan.routine

            let url: URL
            if let fileURL = routine.fileURL {
                url = fileURL
            } else {
                let panel = NSSavePanel()
                if let type = UTType(filenameExtension: RoutineDocument.fileExtension) {
                    panel.allowedContentTypes = [type]
                } else {
                    panel.allowedContentTypes = [.data]
                }
                panel.nameFieldStringValue = "\(routine.name.isEmpty ? "Routine" : routine.name).\(RoutineDocument.fileExtension)"

                guard panel.runModal() == .OK, let selectedURL = panel.url else {
                    return
                }
                url = selectedURL
            }

            try RoutineFileCodec.save(routine, to: url)
            currentRoutine = try RoutineFileCodec.load(from: url)
            statusText = "Saved \(url.lastPathComponent)"
            broadcastState()
        } catch {
            presentAlert(title: "Save Routine Failed", message: error.localizedDescription)
        }
    }

    func runRoutine() {
        if activePlaybackOwner == .singleMacro {
            requestStopActivePlayback(status: "Playback stopped", pendingStart: .routine)
            return
        }

        if activePlaybackOwner == .routine || routineScheduler?.runtimeState.isRunning == true {
            return
        }

        startRoutineNow()
    }

    func stopRoutine(status: String = "Routine stopped") {
        guard currentRoutine != nil || routineScheduler != nil else {
            return
        }

        stopRoutineTimer()
        routineScheduler?.stop(at: Date())
        resolvedRoutinePlan = nil

        if activePlaybackOwner == .routine {
            requestStopActivePlayback(status: status, pendingStart: nil)
        } else {
            routineScheduler = nil
            activePlaybackOwner = .none
            isPlaying = false
            activePlaybackDocument = nil
            activePlaybackTarget = nil
            activePlaybackToken = nil
            statusText = status
            broadcastState()
        }
    }

    func routineDocument() -> RoutineDocument {
        if let currentRoutine {
            return currentRoutine
        }

        let fallbackName = savedPreferredPlaybackApp.map { "\($0.applicationName) Routine" } ?? "Untitled Routine"
        let routine = RoutineDocument(
            fileURL: nil,
            createdAt: Date(),
            name: fallbackName,
            interruptEntries: []
        )
        currentRoutine = routine
        return routine
    }

    func updateRoutineName(_ value: String) {
        guard ensureRoutineIsEditable() else {
            return
        }

        var routine = routineDocument()
        routine.name = value.isEmpty ? "Untitled Routine" : value
        currentRoutine = routine
        broadcastState()
    }

    func clearRoutineMainMacro() {
        guard ensureRoutineIsEditable() else {
            return
        }

        guard var routine = currentRoutine else {
            return
        }

        routine.mainEntry = nil
        currentRoutine = routine
        broadcastState()
    }

    func chooseRoutineMainMacro() {
        guard ensureRoutineIsEditable() else {
            return
        }

        do {
            let (macroURL, document) = try chooseMacroFile(title: "Choose Main Macro")
            var routine = routineDocument()
            try validateRoutineTargetCompatibility(of: document, with: routine)
            routine.mainEntry = RoutineMainEntry(
                macroReference: RoutinePathResolver.reference(for: macroURL, relativeTo: routine.fileURL)
            )
            routine = applyRoutineTargetIfNeeded(from: document, to: routine)
            if routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routine.name == "Untitled Routine" {
                routine.name = "\(document.target.applicationName) Routine"
            }
            currentRoutine = routine
            statusText = "Selected \(macroURL.lastPathComponent) as main macro"
            broadcastState()
        } catch {
            presentAlert(title: "Main Macro Failed", message: error.localizedDescription)
        }
    }

    func addRoutineInterrupt() {
        guard ensureRoutineIsEditable() else {
            return
        }

        var routine = routineDocument()
        routine.interruptEntries.append(
            RoutineInterruptEntry(
                name: "Interrupt Macro",
                intervalMinutes: 120,
                priority: 5,
                isEnabled: true
            )
        )
        currentRoutine = routine
        broadcastState()
    }

    func removeRoutineInterrupt(id: UUID) {
        guard ensureRoutineIsEditable() else {
            return
        }

        guard var routine = currentRoutine else {
            return
        }
        routine.interruptEntries.removeAll { $0.id == id }
        currentRoutine = routine
        broadcastState()
    }

    func updateRoutineInterruptName(_ value: String, for id: UUID) {
        mutateRoutineInterrupt(id: id) { $0.name = value }
    }

    func updateRoutineInterruptIntervalMinutes(_ value: Int, for id: UUID) {
        mutateRoutineInterrupt(id: id) { $0.intervalMinutes = max(1, value) }
    }

    func updateRoutineInterruptPriority(_ value: Int, for id: UUID) {
        mutateRoutineInterrupt(id: id) { $0.priority = min(9, max(1, value)) }
    }

    func updateRoutineInterruptEnabled(_ value: Bool, for id: UUID) {
        mutateRoutineInterrupt(id: id) { $0.isEnabled = value }
    }

    func chooseRoutineInterruptMacro(for id: UUID) {
        guard ensureRoutineIsEditable() else {
            return
        }

        do {
            let (macroURL, document) = try chooseMacroFile(title: "Choose Interrupt Macro")
            guard var routine = currentRoutine else {
                return
            }
            try validateRoutineTargetCompatibility(of: document, with: routine)
            routine = applyRoutineTargetIfNeeded(from: document, to: routine)

            guard let index = routine.interruptEntries.firstIndex(where: { $0.id == id }) else {
                return
            }

            routine.interruptEntries[index].macroReference = RoutinePathResolver.reference(for: macroURL, relativeTo: routine.fileURL)
            if routine.interruptEntries[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routine.interruptEntries[index].name == "Interrupt Macro" {
                routine.interruptEntries[index].name = macroURL.deletingPathExtension().lastPathComponent
            }

            currentRoutine = routine
            statusText = "Selected \(macroURL.lastPathComponent) for \(routine.interruptEntries[index].name)"
            broadcastState()
        } catch {
            presentAlert(title: "Interrupt Macro Failed", message: error.localizedDescription)
        }
    }

    func openAccessibilitySettings() {
        permissionsManager.openAccessibilitySettings()
    }

    func requestAccessibilityAccess() {
        _ = permissionsManager.requestAccessibilityAccess()
        hasDismissedSetupWindow = false
        refreshPermissionState(promptForAccessibility: false)
        broadcastState()
    }

    func openInputMonitoringSettings() {
        permissionsManager.openInputMonitoringSettings()
    }

    func recheckPermissions() {
        refreshPermissionState(promptForAccessibility: false)
        broadcastState()
    }

    func dismissSetupWindow() {
        hasDismissedSetupWindow = true
        if permissionChecklist.isGranted {
            completeSetupOnboardingIfNeeded()
        }
        broadcastState()
    }

    func openLatestReleasePage() {
        NSWorkspace.shared.open(ReleaseConfiguration.latestReleaseURL)
    }

    func hotKey(for action: HotKeyAction) -> HotKeyDescriptor {
        hotKeys[action] ?? preferences.hotKeys()[action]!
    }

    func updateHotKey(_ descriptor: HotKeyDescriptor, for action: HotKeyAction) {
        hotKeys[action] = descriptor
        preferences.setHotKey(descriptor, for: action)
        hotKeyCenter.register(hotKeys)
        broadcastState()
    }

    func resetHotKeysToDefaults() {
        preferences.resetHotKeys()
        hotKeys = preferences.hotKeys()
        hotKeyCenter.register(hotKeys)
        broadcastState()
    }

    func updatePlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        preferences.setPlaybackMode(mode)
        mutateDocumentSettings { $0.playbackMode = mode }
        broadcastState()
    }

    func updateTargetLockMode(_ mode: TargetLockMode) {
        targetLockMode = mode
        preferences.setTargetLockMode(mode)
        mutateDocumentSettings { $0.targetLockMode = mode }
        broadcastState()
    }

    func updateRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        preferences.setRepeatMode(mode)
        mutateDocumentSettings { $0.repeatMode = mode }
        broadcastState()
    }

    func updatePlaybackSpeed(_ multiplier: Double) {
        playbackSpeedMultiplier = multiplier
        preferences.setPlaybackSpeed(multiplier)
        mutateDocumentSettings { $0.playbackSpeedMultiplier = multiplier }
        broadcastState()
    }

    func updateAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
        preferences.setAlwaysOnTop(value)
        broadcastState()
    }

    func updateLockPlaybackTargetToFront(_ value: Bool) {
        lockPlaybackTargetToFront = value
        preferences.setLockPlaybackTargetToFront(value)

        if isPlaying {
            if value {
                startFocusGuard()

                if let document = activePlaybackDocument, let playbackTarget = activePlaybackTarget {
                    reassertPlaybackTarget(for: document, source: playbackTarget.source)
                }
            } else {
                stopFocusGuard()
            }
        }

        broadcastState()
    }

    func updatePreferredPlaybackApp(_ app: PreferredPlaybackApp?) {
        savedPreferredPlaybackApp = app
        preferences.setPreferredPlaybackApp(app)
        broadcastState()
    }

    func clearPreferredPlaybackApp() {
        updatePreferredPlaybackApp(nil)
    }

    func availablePlaybackApps() -> [PreferredPlaybackApp] {
        var appsByBundleIdentifier: [String: PreferredPlaybackApp] = [:]

        for application in NSWorkspace.shared.runningApplications {
            guard
                !application.isTerminated,
                application.activationPolicy == .regular,
                let bundleIdentifier = application.bundleIdentifier,
                bundleIdentifier != selfBundleIdentifier
            else {
                continue
            }

            let name = application.localizedName ?? bundleIdentifier
            appsByBundleIdentifier[bundleIdentifier] = PreferredPlaybackApp(
                bundleIdentifier: bundleIdentifier,
                applicationName: name
            )
        }

        return appsByBundleIdentifier.values.sorted {
            $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
        }
    }

    private func startRecording() {
        if activePlaybackOwner == .routine || routineScheduler?.runtimeState.isRunning == true {
            stopRoutine(status: "Routine stopped")
        } else if activePlaybackOwner == .singleMacro {
            requestStopActivePlayback(status: "Playback stopped", pendingStart: nil)
        }

        guard ensureAutomationReady() else {
            return
        }

        guard let target = recordingTarget() else {
            presentAlert(
                title: "Target Window Not Found",
                message: "Focus the app you want to record, then use the record hotkey or bring that app to the front before recording."
            )
            return
        }

        do {
            try recorderEngine.startRecording(filteredHotKeys: Array(hotKeys.values))
            _ = WindowContextResolver.refocus(target: target, lockMode: .exactWindow)
            isRecording = true
            warningText = nil
            statusText = "Recording \(target.applicationName)"
            broadcastState()
        } catch {
            presentAlert(title: "Recording Failed", message: error.localizedDescription)
        }
    }

    private func stopRecording(status: String = "Recording captured") {
        do {
            let events = try recorderEngine.stopRecording()
            isRecording = false

            guard let target = recordingTarget() ?? lastObservedExternalTarget else {
                statusText = status
                broadcastState()
                return
            }

            let displays = DisplayLayout.snapshot()
            currentDocument = MacroDocument(
                fileURL: currentDocument?.fileURL,
                createdAt: Date(),
                displays: displays,
                displayLayoutHash: DisplayLayout.hash(displays),
                target: target,
                settings: MacroSettings(
                    playbackMode: playbackMode,
                    targetLockMode: targetLockMode,
                    repeatMode: repeatMode,
                    playbackSpeedMultiplier: playbackSpeedMultiplier
                ),
                events: events
            )

            statusText = events.isEmpty ? "Recording captured no events" : "\(status): \(events.count) events"
            warningText = events.isEmpty ? "No input events were captured." : nil
            broadcastState()
        } catch {
            isRecording = false
            presentAlert(title: "Stop Recording Failed", message: error.localizedDescription)
        }
    }

    private func startSinglePlaybackRequest() {
        if activePlaybackOwner == .routine || routineScheduler?.runtimeState.isRunning == true {
            stopRoutineTimer()
            routineScheduler?.stop(at: Date())
            requestStopActivePlayback(status: "Routine stopped", pendingStart: .singleMacro)
            return
        }

        startSinglePlaybackNow()
    }

    private func startSinglePlaybackNow() {
        guard ensureAutomationReady() else {
            return
        }

        guard var document = currentDocument else {
            presentAlert(title: "No Macro Loaded", message: "Record or open a macro first.")
            return
        }

        applyCurrentSettings(to: &document)
        currentDocument = document

        startDocumentPlayback(
            document: document,
            targetSource: playbackTargetSource(),
            owner: .singleMacro,
            status: document.settings.playbackMode == .strict ? "Strict playback running" : "Scaled playback running"
        ) { [weak self] token, result in
            self?.handleSinglePlaybackCompletion(token: token, result: result)
        }
    }

    private func startRoutineNow() {
        guard ensureAutomationReady() else {
            return
        }

        guard let currentRoutine else {
            presentAlert(title: "No Routine Loaded", message: "Create or open a routine first.")
            return
        }

        do {
            let resolvedPlan = try resolveRoutinePlan(for: currentRoutine)
            guard let bundleIdentifier = resolvedPlan.routine.targetAppBundleIdentifier,
                  availablePlaybackApps().contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                let appName = resolvedPlan.routine.targetAppName ?? "the target app"
                presentAlert(title: "Routine Blocked", message: "Launch \(appName) before starting the routine.")
                return
            }

            self.currentRoutine = resolvedPlan.routine
            self.resolvedRoutinePlan = resolvedPlan
            let scheduler = RoutineScheduler(routine: resolvedPlan.routine)
            routineScheduler = scheduler
            warningText = nil
            statusText = "Routine starting"
            startRoutineTimer()
            executeRoutineCommand(scheduler.start(at: Date()))
        } catch {
            presentAlert(title: "Routine Failed", message: error.localizedDescription)
        }
    }

    private func executeRoutineCommand(_ command: RoutineSchedulerCommand) {
        guard let resolvedRoutinePlan, let routineScheduler else {
            return
        }

        switch command {
        case .startMain:
            var document = resolvedRoutinePlan.mainDocument
            document.settings.repeatMode = .infinite
            startDocumentPlayback(
                document: document,
                targetSource: .preferredApp(resolvedRoutinePlan.targetApp),
                owner: .routine,
                status: "Running Main Macro"
            ) { [weak self] token, result in
                self?.handleRoutinePlaybackCompletion(token: token, result: result)
            }

        case let .startInterrupt(id):
            guard var document = resolvedRoutinePlan.interruptDocuments[id] else {
                routineScheduler.playbackFailed(message: "Routine failed: missing interrupt macro.", at: Date())
                stopRoutineTimer()
                statusText = "Routine failed"
                presentAlert(title: "Routine Failed", message: "An interrupt macro could not be resolved.")
                broadcastState()
                return
            }

            document.settings.repeatMode = .once
            let entryName = routineScheduler.entryName(for: .interrupt(id))
            startDocumentPlayback(
                document: document,
                targetSource: .preferredApp(resolvedRoutinePlan.targetApp),
                owner: .routine,
                status: "Running \(entryName)"
            ) { [weak self] token, result in
                self?.handleRoutinePlaybackCompletion(token: token, result: result)
            }

        case .stopCurrentForInterrupts:
            statusText = "Interrupt pending"
            playbackEngine.stop()
            broadcastState()
        }
    }

    private func startDocumentPlayback(
        document: MacroDocument,
        targetSource: PlaybackTargetSource,
        owner: ActivePlaybackOwner,
        status: String,
        completion: @escaping @MainActor (UUID, Result<Void, Error>) -> Void
    ) {
        let playbackTarget: PlaybackTargetContext
        switch resolvePlaybackTarget(for: document, source: targetSource) {
        case let .success(target):
            playbackTarget = target
        case let .failure(error):
            handlePlaybackStartFailure(message: error.message, owner: owner)
            return
        }

        if lockPlaybackTargetToFront,
           !WindowContextResolver.isFrontmost(target: playbackTarget.target),
           !WindowContextResolver.refocus(target: playbackTarget.target, lockMode: playbackTarget.lockMode) {
            handlePlaybackStartFailure(message: "TinyTaskMac could not reactivate the target window.", owner: owner)
            return
        }

        let token = UUID()
        activePlaybackToken = token
        activePlaybackOwner = owner
        activePlaybackTarget = playbackTarget
        activePlaybackDocument = document
        isPlaying = true
        warningText = nil
        statusText = status
        recorderEngine.beginPlaybackMonitoring()
        if lockPlaybackTargetToFront {
            startFocusGuard()
        } else {
            stopFocusGuard()
        }
        broadcastState()

        do {
            try playbackEngine.start(document: document) { result in
                Task { @MainActor in
                    completion(token, result)
                }
            }
        } catch {
            clearActivePlaybackState()
            handlePlaybackStartFailure(message: error.localizedDescription, owner: owner)
        }
    }

    private func requestStopActivePlayback(status: String, pendingStart: PendingStartAction?) {
        guard activePlaybackOwner != .none else {
            pendingStopStatus = nil
            pendingStartAction = nil

            switch pendingStart {
            case .singleMacro:
                startSinglePlaybackNow()
            case .routine:
                startRoutineNow()
            case nil:
                statusText = status
                broadcastState()
            }
            return
        }

        pendingStopStatus = status
        pendingStartAction = pendingStart

        if activePlaybackOwner == .routine {
            stopRoutineTimer()
            routineScheduler?.stop(at: Date())
        }

        playbackEngine.stop()
    }

    private func handleSinglePlaybackCompletion(token: UUID, result: Result<Void, Error>) {
        guard activePlaybackToken == token else {
            return
        }

        let followUp = pendingStartAction
        let stopStatus = pendingStopStatus

        clearActivePlaybackState()
        pendingStartAction = nil
        pendingStopStatus = nil

        switch result {
        case .success:
            if let stopStatus {
                statusText = stopStatus
            } else {
                statusText = "Playback finished"
            }

            switch followUp {
            case .singleMacro:
                startSinglePlaybackNow()
            case .routine:
                startRoutineNow()
            case nil:
                broadcastState()
            }

        case let .failure(error):
            statusText = "Playback failed"
            broadcastState()
            presentAlert(title: "Playback Failed", message: error.localizedDescription)
        }
    }

    private func handleRoutinePlaybackCompletion(token: UUID, result: Result<Void, Error>) {
        guard activePlaybackToken == token else {
            return
        }

        let followUp = pendingStartAction
        let stopStatus = pendingStopStatus

        clearActivePlaybackState()
        pendingStartAction = nil
        pendingStopStatus = nil

        switch result {
        case .success:
            if let followUp {
                resolvedRoutinePlan = nil
                routineScheduler = nil
                if let stopStatus {
                    statusText = stopStatus
                }

                switch followUp {
                case .singleMacro:
                    startSinglePlaybackNow()
                case .routine:
                    startRoutineNow()
                }
                return
            }

            guard let routineScheduler else {
                statusText = stopStatus ?? "Routine stopped"
                broadcastState()
                return
            }

            guard routineScheduler.runtimeState.isRunning else {
                resolvedRoutinePlan = nil
                self.routineScheduler = nil
                statusText = stopStatus ?? "Routine stopped"
                broadcastState()
                return
            }

            if let command = routineScheduler.playbackFinished(at: Date()) {
                broadcastState()
                executeRoutineCommand(command)
            } else {
                statusText = routineScheduler.runtimeState.statusText
                broadcastState()
            }

        case let .failure(error):
            routineScheduler?.playbackFailed(message: "Routine failed", at: Date())
            stopRoutineTimer()
            resolvedRoutinePlan = nil
            routineScheduler = nil
            statusText = "Routine failed"
            broadcastState()
            presentAlert(title: "Routine Failed", message: error.localizedDescription)
        }
    }

    private func clearActivePlaybackState() {
        activePlaybackToken = nil
        activePlaybackOwner = .none
        activePlaybackTarget = nil
        activePlaybackDocument = nil
        isPlaying = false
        recorderEngine.endPlaybackMonitoring()
        stopFocusGuard()
    }

    private func startRoutineTimer() {
        stopRoutineTimer()
        routineTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleRoutineTick()
            }
        }
    }

    private func stopRoutineTimer() {
        routineTickTimer?.invalidate()
        routineTickTimer = nil
    }

    private func handleRoutineTick() {
        guard let routineScheduler else {
            return
        }

        if let command = routineScheduler.tick(now: Date()) {
            executeRoutineCommand(command)
        } else {
            broadcastState()
        }
    }

    private func handlePlaybackStartFailure(message: String, owner: ActivePlaybackOwner) {
        clearActivePlaybackState()

        if owner == .routine {
            stopRoutineTimer()
            routineScheduler?.playbackFailed(message: "Routine blocked", at: Date())
            resolvedRoutinePlan = nil
            routineScheduler = nil
            statusText = "Routine blocked"
        } else {
            statusText = "Playback blocked"
        }

        broadcastState()
        presentAlert(title: owner == .routine ? "Routine Blocked" : "Playback Blocked", message: message)
    }

    private func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .toggleRecording:
            toggleRecording()
        case .togglePlayback:
            togglePlayback()
        case .emergencyStop:
            emergencyStop()
        }
    }

    @objc
    private func workspaceDidActivate(_ notification: Notification) {
        handleActivation()
    }

    @objc
    private func workspaceRunningAppsDidChange(_ notification: Notification) {
        refreshPermissionState(promptForAccessibility: false)
        broadcastState()
    }

    private func handleActivation() {
        refreshPermissionState(promptForAccessibility: false)
        observeCurrentExternalTarget()

        guard
            lockPlaybackTargetToFront,
            isPlaying,
            let document = activePlaybackDocument,
            let playbackTarget = activePlaybackTarget
        else {
            broadcastState()
            return
        }

        if !WindowContextResolver.isFrontmost(target: playbackTarget.target) {
            reassertPlaybackTarget(for: document, source: playbackTarget.source)
        }

        broadcastState()
    }

    private func observeCurrentExternalTarget() {
        guard PermissionsManager.isAccessibilityGranted(prompt: false) else {
            return
        }

        do {
            let target = try WindowContextResolver.captureFrontmostTarget(excludingBundleIdentifiers: [selfBundleIdentifier])
            lastObservedExternalTarget = target
        } catch {
            // Ignore; the current app may be frontmost or the target may not expose AX state.
        }
    }

    private func markHumanInterference() {
        guard isPlaying else {
            return
        }
        warningText = "Human input detected during playback. The run is now fidelity-compromised."
        if activePlaybackOwner == .singleMacro {
            currentDocument?.isStrictRunCompromised = true
        }
        broadcastState()
    }

    private func startFocusGuard() {
        stopFocusGuard()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard
                    self.lockPlaybackTargetToFront,
                    let document = self.activePlaybackDocument,
                    let playbackTarget = self.activePlaybackTarget,
                    self.isPlaying
                else {
                    return
                }

                self.reassertPlaybackTarget(for: document, source: playbackTarget.source)
            }
        }
    }

    private func stopFocusGuard() {
        focusTimer?.invalidate()
        focusTimer = nil
    }

    private func reassertPlaybackTarget(for document: MacroDocument, source: PlaybackTargetSource) {
        switch resolvePlaybackTarget(for: document, source: source) {
        case let .success(playbackTarget):
            activePlaybackTarget = playbackTarget

            if WindowContextResolver.isFrontmost(target: playbackTarget.target) {
                return
            }

            guard WindowContextResolver.refocus(target: playbackTarget.target, lockMode: playbackTarget.lockMode) else {
                handleUnrecoverablePlaybackBlock(message: "TinyTaskMac could not reactivate the target window.")
                return
            }

            switch resolvePlaybackTarget(for: document, source: source) {
            case let .success(refocusedTarget):
                activePlaybackTarget = refocusedTarget
                statusText = "Playback target refocused"
                broadcastState()
            case let .failure(error):
                handleUnrecoverablePlaybackBlock(message: error.message)
            }

        case let .failure(error):
            handleUnrecoverablePlaybackBlock(message: error.message)
        }
    }

    private func handleUnrecoverablePlaybackBlock(message: String) {
        if activePlaybackOwner == .routine {
            stopRoutine(status: "Routine blocked")
            presentAlert(title: "Routine Blocked", message: message)
        } else {
            requestStopActivePlayback(status: "Playback blocked", pendingStart: nil)
            presentAlert(title: "Playback Blocked", message: message)
        }
    }

    private func recordingTarget() -> WindowTarget? {
        if let current = try? WindowContextResolver.captureFrontmostTarget(excludingBundleIdentifiers: [selfBundleIdentifier]) {
            return current
        }

        return lastObservedExternalTarget
    }

    private func ensureAutomationReady() -> Bool {
        refreshPermissionState(promptForAccessibility: false)

        guard permissionChecklist.isGranted else {
            statusText = "Setup required"
            hasDismissedSetupWindow = false
            presentSetupWindow()
            return false
        }

        completeSetupOnboardingIfNeeded()
        return true
    }

    private func resolvePlaybackTarget(for document: MacroDocument, source: PlaybackTargetSource) -> Result<PlaybackTargetContext, WindowValidationError> {
        if let error = WindowContextResolver.validateDisplayLayout(for: document) {
            return .failure(error)
        }

        return WindowContextResolver.resolvePlaybackTarget(for: document, source: source)
    }

    private func playbackTargetSource() -> PlaybackTargetSource {
        if let savedPreferredPlaybackApp {
            return .preferredApp(savedPreferredPlaybackApp)
        }

        return .recorded
    }

    private func isPreferredPlaybackAppRunning() -> Bool {
        guard let savedPreferredPlaybackApp else {
            return false
        }

        return availablePlaybackApps().contains { $0.bundleIdentifier == savedPreferredPlaybackApp.bundleIdentifier }
    }

    private func mutateDocumentSettings(_ mutate: (inout MacroSettings) -> Void) {
        guard var document = currentDocument else {
            return
        }
        mutate(&document.settings)
        currentDocument = document
    }

    private func mutateRoutineInterrupt(id: UUID, mutate: (inout RoutineInterruptEntry) -> Void) {
        guard ensureRoutineIsEditable() else {
            return
        }

        guard var routine = currentRoutine,
              let index = routine.interruptEntries.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&routine.interruptEntries[index])
        routine.interruptEntries[index].intervalMinutes = max(1, routine.interruptEntries[index].intervalMinutes)
        routine.interruptEntries[index].priority = min(9, max(1, routine.interruptEntries[index].priority))
        currentRoutine = routine
        broadcastState()
    }

    private func applyCurrentSettings(to document: inout MacroDocument) {
        document.settings.playbackMode = playbackMode
        document.settings.targetLockMode = targetLockMode
        document.settings.repeatMode = repeatMode
        document.settings.playbackSpeedMultiplier = playbackSpeedMultiplier
    }

    private func loadMacro(from url: URL) {
        do {
            var document = try MacroFileCodec.load(from: url)
            playbackMode = document.settings.playbackMode
            targetLockMode = document.settings.targetLockMode
            repeatMode = document.settings.repeatMode
            playbackSpeedMultiplier = document.settings.playbackSpeedMultiplier
            statusText = "Loaded \(url.lastPathComponent)"
            warningText = nil
            document.isStrictRunCompromised = false
            currentDocument = document
            broadcastState()
        } catch {
            presentAlert(title: "Open Failed", message: error.localizedDescription)
        }
    }

    private func loadRoutine(from url: URL) {
        guard ensureRoutineIsEditable() else {
            return
        }

        do {
            let routine = try RoutineFileCodec.load(from: url)
            let resolvedPlan = try resolveRoutinePlan(for: routine)
            currentRoutine = resolvedPlan.routine
            resolvedRoutinePlan = nil
            routineScheduler = nil
            statusText = "Loaded \(url.lastPathComponent)"
            warningText = nil
            broadcastState()
        } catch {
            presentAlert(title: "Open Routine Failed", message: error.localizedDescription)
        }
    }

    private func resolveRoutinePlan(for routine: RoutineDocument) throws -> ResolvedRoutinePlan {
        guard let mainEntry = routine.mainEntry else {
            throw WindowValidationError(message: "Choose a main macro before saving or running the routine.")
        }

        let mainURL = try resolvedRoutineMacroURL(for: mainEntry.macroReference, routine: routine)
        let mainDocument = try MacroFileCodec.load(from: mainURL)

        var targetBundleIdentifier = routine.targetAppBundleIdentifier ?? mainDocument.target.bundleIdentifier
        var targetAppName = routine.targetAppName ?? mainDocument.target.applicationName

        guard mainDocument.target.bundleIdentifier == targetBundleIdentifier else {
            throw WindowValidationError(message: "The main macro targets a different app than this routine.")
        }

        var interruptDocuments: [UUID: MacroDocument] = [:]
        for entry in routine.interruptEntries {
            let macroURL = try resolvedRoutineMacroURL(for: entry.macroReference, routine: routine)
            let document = try MacroFileCodec.load(from: macroURL)

            guard document.target.bundleIdentifier == targetBundleIdentifier else {
                throw WindowValidationError(message: "\(displayName(for: entry)) targets \(document.target.applicationName), but routines only support one app.")
            }

            interruptDocuments[entry.id] = document
        }

        let normalizedRoutine = RoutineDocument(
            fileURL: routine.fileURL,
            createdAt: routine.createdAt,
            name: routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Routine" : routine.name,
            targetAppBundleIdentifier: targetBundleIdentifier,
            targetAppName: targetAppName,
            mainEntry: RoutineMainEntry(
                macroReference: RoutinePathResolver.reference(for: mainURL, relativeTo: routine.fileURL)
            ),
            interruptEntries: routine.interruptEntries.map { entry in
                let absoluteURL = try? resolvedRoutineMacroURL(for: entry.macroReference, routine: routine)
                return RoutineInterruptEntry(
                    id: entry.id,
                    name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayName(for: entry) : entry.name,
                    macroReference: absoluteURL.map { RoutinePathResolver.reference(for: $0, relativeTo: routine.fileURL) } ?? entry.macroReference,
                    intervalMinutes: max(1, entry.intervalMinutes),
                    priority: min(9, max(1, entry.priority)),
                    isEnabled: entry.isEnabled
                )
            }
        )

        targetBundleIdentifier = normalizedRoutine.targetAppBundleIdentifier ?? mainDocument.target.bundleIdentifier
        targetAppName = normalizedRoutine.targetAppName ?? mainDocument.target.applicationName

        return ResolvedRoutinePlan(
            routine: normalizedRoutine,
            targetApp: PreferredPlaybackApp(bundleIdentifier: targetBundleIdentifier, applicationName: targetAppName),
            mainDocument: mainDocument,
            interruptDocuments: interruptDocuments
        )
    }

    private func resolvedRoutineMacroURL(for reference: RoutineEntryReference, routine: RoutineDocument) throws -> URL {
        guard let url = reference.resolvedURL(relativeTo: routine.fileURL) else {
            throw WindowValidationError(message: "A routine macro reference is missing.")
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WindowValidationError(message: "Could not find \(reference.displayName).")
        }

        return url
    }

    private func validateRoutineTargetCompatibility(of document: MacroDocument, with routine: RoutineDocument) throws {
        if let targetBundleIdentifier = routine.targetAppBundleIdentifier,
           document.target.bundleIdentifier != targetBundleIdentifier {
            let targetName = routine.targetAppName ?? "the routine target"
            throw WindowValidationError(message: "\(document.target.applicationName) does not match \(targetName). One routine can target only one app.")
        }
    }

    private func applyRoutineTargetIfNeeded(from document: MacroDocument, to routine: RoutineDocument) -> RoutineDocument {
        RoutineDocument(
            fileURL: routine.fileURL,
            createdAt: routine.createdAt,
            name: routine.name,
            targetAppBundleIdentifier: routine.targetAppBundleIdentifier ?? document.target.bundleIdentifier,
            targetAppName: routine.targetAppName ?? document.target.applicationName,
            mainEntry: routine.mainEntry,
            interruptEntries: routine.interruptEntries
        )
    }

    private func chooseMacroFile(title: String) throws -> (URL, MacroDocument) {
        let panel = NSOpenPanel()
        panel.title = title
        if let type = UTType(filenameExtension: MacroDocument.fileExtension) {
            panel.allowedContentTypes = [type]
        } else {
            panel.allowedContentTypes = [.data]
        }
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }

        return (url, try MacroFileCodec.load(from: url))
    }

    private func displayName(for entry: RoutineInterruptEntry) -> String {
        let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? entry.macroReference.displayName : trimmed
    }

    private func currentRoutineStatusPreview() -> String? {
        guard let currentRoutine else {
            return nil
        }

        if let targetAppName = currentRoutine.targetAppName {
            return "Target app: \(targetAppName)"
        }

        return "Routine ready"
    }

    private func ensureRoutineIsEditable() -> Bool {
        guard activePlaybackOwner != .routine, routineScheduler?.runtimeState.isRunning != true else {
            presentAlert(title: "Routine Running", message: "Stop the routine before changing, opening, or saving it.")
            return false
        }

        return true
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        let alertWindow = alert.window
        alertWindow.level = .screenSaver
        alertWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        alertWindow.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        alertWindow.center()
        alertWindow.orderFrontRegardless()
        alert.runModal()
    }

    private func broadcastState() {
        NotificationCenter.default.post(name: .appStateDidChange, object: self)
    }

    private func refreshPermissionState(promptForAccessibility: Bool) {
        permissionChecklist = permissionsManager.checklistState(promptForAccessibility: promptForAccessibility)
        if permissionChecklist.isGranted, warningText == permissionsManager.instructions(for: .needsInputMonitoring) ||
            warningText == permissionsManager.instructions(for: .needsAccessibility) ||
            warningText == permissionsManager.instructions(for: .needsAccessibilityAndInputMonitoring) {
            warningText = nil
        }
    }

    private func presentSetupWindow() {
        NotificationCenter.default.post(name: .openSetupWindow, object: nil)
        broadcastState()
    }

    private func completeSetupOnboardingIfNeeded() {
        guard !setupOnboardingCompleted else {
            return
        }

        setupOnboardingCompleted = true
        preferences.setSetupOnboardingCompleted(true)
    }

    private func effectiveStatusText() -> String {
        if !permissionChecklist.isGranted, activePlaybackOwner == .none, !isRecording {
            return "Setup required"
        }

        return statusText
    }

    private func effectiveWarningText() -> String? {
        if !permissionChecklist.isGranted {
            return permissionsManager.instructions(for: permissionChecklist.status)
        }

        return warningText
    }
}
