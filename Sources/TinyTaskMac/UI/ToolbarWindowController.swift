import AppKit
import Foundation

final class ToolbarWindowController: NSWindowController {
    private let appState: AppState

    private let macroFileLabel = NSTextField(labelWithString: "Unsaved Macro")
    private let routineFileLabel = NSTextField(labelWithString: "No Routine")
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let routineStatusLabel = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(labelWithString: "")

    private let recordButton = NSButton(title: "Record", target: nil, action: nil)
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let setupButton = NSButton(title: "Setup", target: nil, action: nil)
    private let prefsButton = NSButton(title: "Prefs", target: nil, action: nil)

    private let editRoutineButton = NSButton(title: "Edit Routine", target: nil, action: nil)
    private let openRoutineButton = NSButton(title: "Open Routine", target: nil, action: nil)
    private let saveRoutineButton = NSButton(title: "Save Routine", target: nil, action: nil)
    private let runRoutineButton = NSButton(title: "Run Routine", target: nil, action: nil)
    private let stopRoutineButton = NSButton(title: "Stop Routine", target: nil, action: nil)

    private let modePopup = NSPopUpButton()
    private let targetPopup = NSPopUpButton()
    private let repeatPopup = NSPopUpButton()
    private let speedPopup = NSPopUpButton()
    private let alwaysOnTopCheckbox = NSButton(checkboxWithTitle: "Always On Top", target: nil, action: nil)

    init(appState: AppState) {
        self.appState = appState

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 340),
            styleMask: [.titled, .closable, .utilityWindow, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "TinyTaskMac"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        setupUI()
        refresh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateDidChange),
            name: .appStateDidChange,
            object: appState
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        macroFileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        routineFileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        routineFileLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        routineStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        routineStatusLabel.textColor = .secondaryLabelColor
        routineStatusLabel.maximumNumberOfLines = 2
        warningLabel.font = .systemFont(ofSize: 12, weight: .medium)
        warningLabel.textColor = .systemRed
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.maximumNumberOfLines = 2

        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        openButton.target = self
        openButton.action = #selector(openMacro)
        saveButton.target = self
        saveButton.action = #selector(saveMacro)
        setupButton.target = self
        setupButton.action = #selector(openSetup)
        prefsButton.target = self
        prefsButton.action = #selector(openPrefs)

        editRoutineButton.target = self
        editRoutineButton.action = #selector(editRoutine)
        openRoutineButton.target = self
        openRoutineButton.action = #selector(openRoutine)
        saveRoutineButton.target = self
        saveRoutineButton.action = #selector(saveRoutine)
        runRoutineButton.target = self
        runRoutineButton.action = #selector(runRoutine)
        stopRoutineButton.target = self
        stopRoutineButton.action = #selector(stopRoutine)

        modePopup.addItems(withTitles: PlaybackMode.allCases.map(\.title))
        modePopup.target = self
        modePopup.action = #selector(modeChanged)

        targetPopup.addItems(withTitles: TargetLockMode.allCases.map(\.title))
        targetPopup.target = self
        targetPopup.action = #selector(targetChanged)

        repeatPopup.addItems(withTitles: RepeatMode.allCases.map(\.title))
        repeatPopup.target = self
        repeatPopup.action = #selector(repeatChanged)

        speedPopup.addItems(withTitles: ["0.25x", "0.5x", "1.0x", "2.0x", "4.0x"])
        speedPopup.target = self
        speedPopup.action = #selector(speedChanged)

        alwaysOnTopCheckbox.target = self
        alwaysOnTopCheckbox.action = #selector(alwaysOnTopChanged)

        let macroButtonRow = NSStackView(views: [recordButton, playButton, openButton, saveButton, setupButton, prefsButton])
        macroButtonRow.orientation = .horizontal
        macroButtonRow.spacing = 8
        macroButtonRow.distribution = .fillEqually

        let routineButtonRow = NSStackView(views: [editRoutineButton, openRoutineButton, saveRoutineButton, runRoutineButton, stopRoutineButton])
        routineButtonRow.orientation = .horizontal
        routineButtonRow.spacing = 8
        routineButtonRow.distribution = .fillEqually

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Mode"), modePopup],
            [NSTextField(labelWithString: "Target"), targetPopup],
            [NSTextField(labelWithString: "Repeat"), repeatPopup],
            [NSTextField(labelWithString: "Speed"), speedPopup]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12

        let stack = NSStackView(views: [
            macroFileLabel,
            routineFileLabel,
            macroButtonRow,
            routineButtonRow,
            grid,
            alwaysOnTopCheckbox,
            statusLabel,
            routineStatusLabel,
            warningLabel
        ])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func refresh() {
        let snapshot = appState.snapshot()
        macroFileLabel.stringValue = "Macro: \(snapshot.currentFileName)"
        routineFileLabel.stringValue = "Routine: \(snapshot.routineFileName)"
        statusLabel.stringValue = snapshot.statusText

        let routineStatusPieces = [snapshot.routineStatusText, snapshot.routineNextDueText].compactMap { $0 }.filter { !$0.isEmpty }
        routineStatusLabel.stringValue = routineStatusPieces.joined(separator: " • ")
        warningLabel.stringValue = snapshot.warningText ?? ""
        alwaysOnTopCheckbox.state = snapshot.alwaysOnTop ? .on : .off

        recordButton.title = snapshot.isRecording ? "Stop" : "Record"
        playButton.title = snapshot.isPlaying ? "Stop" : "Play"
        playButton.isEnabled = (snapshot.hasMacroLoaded || snapshot.isPlaying) && !snapshot.isRoutineRunning && !snapshot.shouldBlockAutomation
        recordButton.isEnabled = !snapshot.isRoutineRunning && !snapshot.shouldBlockAutomation
        saveButton.isEnabled = snapshot.hasMacroLoaded
        setupButton.isEnabled = true

        editRoutineButton.isEnabled = !snapshot.isRoutineRunning
        openRoutineButton.isEnabled = !snapshot.isRoutineRunning
        saveRoutineButton.isEnabled = snapshot.hasRoutineLoaded
        runRoutineButton.isEnabled = snapshot.hasRoutineLoaded && !snapshot.isRoutineRunning && !snapshot.shouldBlockAutomation
        stopRoutineButton.isEnabled = snapshot.isRoutineRunning

        modePopup.selectItem(at: Int(snapshot.playbackMode.rawValue))
        targetPopup.selectItem(at: Int(snapshot.targetLockMode.rawValue))
        repeatPopup.selectItem(at: Int(snapshot.repeatMode.rawValue))
        speedPopup.selectItem(withTitle: String(format: "%.2gx", snapshot.playbackSpeedMultiplier))
        if speedPopup.indexOfSelectedItem == -1 {
            speedPopup.selectItem(withTitle: "1.0x")
        }
        speedPopup.isEnabled = snapshot.playbackMode == .scaled
        applyWindowBehavior(alwaysOnTop: snapshot.alwaysOnTop)
    }

    @objc
    private func toggleRecording() {
        appState.toggleRecording()
    }

    @objc
    private func togglePlayback() {
        appState.togglePlayback()
    }

    @objc
    private func openMacro() {
        appState.openMacro()
    }

    @objc
    private func saveMacro() {
        appState.saveMacro()
    }

    @objc
    private func openSetup() {
        NotificationCenter.default.post(name: .openSetupWindow, object: nil)
    }

    @objc
    private func openPrefs() {
        NotificationCenter.default.post(name: .openPreferencesWindow, object: nil)
    }

    @objc
    private func editRoutine() {
        NotificationCenter.default.post(name: .openRoutineEditorWindow, object: nil)
    }

    @objc
    private func openRoutine() {
        appState.openRoutine()
    }

    @objc
    private func saveRoutine() {
        appState.saveRoutine()
    }

    @objc
    private func runRoutine() {
        appState.runRoutine()
    }

    @objc
    private func stopRoutine() {
        appState.stopRoutine()
    }

    @objc
    private func handleAppStateDidChange() {
        refresh()
    }

    @objc
    private func modeChanged() {
        appState.updatePlaybackMode(PlaybackMode(rawValue: UInt8(modePopup.indexOfSelectedItem)) ?? .strict)
    }

    @objc
    private func targetChanged() {
        appState.updateTargetLockMode(TargetLockMode(rawValue: UInt8(targetPopup.indexOfSelectedItem)) ?? .exactWindow)
    }

    @objc
    private func repeatChanged() {
        appState.updateRepeatMode(RepeatMode(rawValue: UInt8(repeatPopup.indexOfSelectedItem)) ?? .once)
    }

    @objc
    private func speedChanged() {
        let title = speedPopup.titleOfSelectedItem ?? "1.0x"
        let trimmed = title.replacingOccurrences(of: "x", with: "")
        let value = Double(trimmed) ?? 1.0
        appState.updatePlaybackSpeed(value)
    }

    @objc
    private func alwaysOnTopChanged() {
        appState.updateAlwaysOnTop(alwaysOnTopCheckbox.state == .on)
    }

    private func applyWindowBehavior(alwaysOnTop: Bool) {
        guard let panel = window as? NSPanel else {
            return
        }

        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = alwaysOnTop
        panel.level = alwaysOnTop ? .statusBar : .normal

        if alwaysOnTop {
            panel.orderFrontRegardless()
        }
    }
}
