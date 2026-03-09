import AppKit
import Foundation

final class PreferencesWindowController: NSWindowController {
    private let appState: AppState
    private var fields: [HotKeyAction: HotKeyRecorderField] = [:]
    private let lockPlaybackTargetCheckbox = NSButton(checkboxWithTitle: "Lock target app to front during playback", target: nil, action: nil)
    private let preferredPlaybackAppPopup = NSPopUpButton()
    private let clearPreferredPlaybackAppButton = NSButton(title: "Clear", target: nil, action: nil)
    private let preferredPlaybackAppStatusLabel = NSTextField(wrappingLabelWithString: "")

    init(appState: AppState) {
        self.appState = appState

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"

        super.init(window: window)
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

        let playbackTitleLabel = NSTextField(labelWithString: "Playback")
        playbackTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        lockPlaybackTargetCheckbox.target = self
        lockPlaybackTargetCheckbox.action = #selector(lockPlaybackTargetChanged)

        preferredPlaybackAppPopup.target = self
        preferredPlaybackAppPopup.action = #selector(preferredPlaybackAppChanged)

        clearPreferredPlaybackAppButton.target = self
        clearPreferredPlaybackAppButton.action = #selector(clearPreferredPlaybackApp)

        preferredPlaybackAppStatusLabel.maximumNumberOfLines = 3
        preferredPlaybackAppStatusLabel.textColor = .secondaryLabelColor

        let preferredPlaybackAppRow = NSStackView(views: [preferredPlaybackAppPopup, clearPreferredPlaybackAppButton])
        preferredPlaybackAppRow.orientation = .horizontal
        preferredPlaybackAppRow.spacing = 8

        let playbackGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Preferred Playback App"), preferredPlaybackAppRow]
        ])
        playbackGrid.rowSpacing = 10
        playbackGrid.columnSpacing = 12

        let hotKeyTitleLabel = NSTextField(labelWithString: "Hotkeys")
        hotKeyTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Click a shortcut field, then press the replacement shortcut. Hotkeys are global and never recorded into macros.")
        descriptionLabel.maximumNumberOfLines = 3

        let rows = HotKeyAction.allCases.map { action -> [NSView] in
            let label = NSTextField(labelWithString: action.title)
            let field = HotKeyRecorderField()
            field.onCapture = { [weak self] descriptor in
                self?.appState.updateHotKey(descriptor, for: action)
            }
            fields[action] = field
            return [label, field]
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        let accessibilityButton = NSButton(title: "Accessibility", target: self, action: #selector(openAccessibility))
        let inputMonitoringButton = NSButton(title: "Input Monitoring", target: self, action: #selector(openInputMonitoring))
        let defaultsButton = NSButton(title: "Use Defaults", target: self, action: #selector(resetHotKeys))

        let buttons = NSStackView(views: [accessibilityButton, inputMonitoringButton, defaultsButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [
            playbackTitleLabel,
            lockPlaybackTargetCheckbox,
            playbackGrid,
            preferredPlaybackAppStatusLabel,
            separator,
            hotKeyTitleLabel,
            descriptionLabel,
            grid,
            buttons
        ])
        stack.orientation = NSUserInterfaceLayoutOrientation.vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    private func refresh() {
        let snapshot = appState.snapshot()
        lockPlaybackTargetCheckbox.state = snapshot.lockPlaybackTargetToFront ? .on : .off
        rebuildPreferredPlaybackAppPopup(
            availableApps: appState.availablePlaybackApps(),
            selectedBundleIdentifier: snapshot.preferredPlaybackAppBundleIdentifier,
            selectedAppName: snapshot.preferredPlaybackAppName,
            isRunning: snapshot.isPreferredPlaybackAppRunning
        )
        clearPreferredPlaybackAppButton.isEnabled = snapshot.preferredPlaybackAppBundleIdentifier != nil
        preferredPlaybackAppStatusLabel.stringValue = preferredPlaybackStatusText(snapshot: snapshot)

        for action in HotKeyAction.allCases {
            fields[action]?.stringValue = appState.hotKey(for: action).displayText
        }
    }

    @objc
    private func openAccessibility() {
        appState.openAccessibilitySettings()
    }

    @objc
    private func openInputMonitoring() {
        appState.openInputMonitoringSettings()
    }

    @objc
    private func resetHotKeys() {
        appState.resetHotKeysToDefaults()
    }

    @objc
    private func lockPlaybackTargetChanged() {
        appState.updateLockPlaybackTargetToFront(lockPlaybackTargetCheckbox.state == .on)
    }

    @objc
    private func preferredPlaybackAppChanged() {
        let app = preferredPlaybackAppPopup.selectedItem?.representedObject as? PreferredPlaybackApp
        appState.updatePreferredPlaybackApp(app)
    }

    @objc
    private func clearPreferredPlaybackApp() {
        appState.clearPreferredPlaybackApp()
    }

    @objc
    private func handleAppStateDidChange() {
        refresh()
    }

    private func rebuildPreferredPlaybackAppPopup(
        availableApps: [PreferredPlaybackApp],
        selectedBundleIdentifier: String?,
        selectedAppName: String?,
        isRunning: Bool
    ) {
        preferredPlaybackAppPopup.removeAllItems()

        preferredPlaybackAppPopup.addItem(withTitle: "Recorded Macro Target")
        preferredPlaybackAppPopup.lastItem?.representedObject = nil

        for app in availableApps {
            preferredPlaybackAppPopup.addItem(withTitle: app.applicationName)
            preferredPlaybackAppPopup.lastItem?.representedObject = app
        }

        if let selectedBundleIdentifier,
           !availableApps.contains(where: { $0.bundleIdentifier == selectedBundleIdentifier }) {
            let offlineApp = PreferredPlaybackApp(
                bundleIdentifier: selectedBundleIdentifier,
                applicationName: selectedAppName ?? selectedBundleIdentifier
            )
            preferredPlaybackAppPopup.addItem(withTitle: "\(offlineApp.applicationName) (Not Running)")
            preferredPlaybackAppPopup.lastItem?.representedObject = offlineApp
        }

        if let selectedBundleIdentifier,
           let item = preferredPlaybackAppPopup.itemArray.first(where: {
               ($0.representedObject as? PreferredPlaybackApp)?.bundleIdentifier == selectedBundleIdentifier
           }) {
            preferredPlaybackAppPopup.select(item)
        } else {
            preferredPlaybackAppPopup.selectItem(at: 0)
        }

        preferredPlaybackAppPopup.isEnabled = isRunning || selectedBundleIdentifier == nil || preferredPlaybackAppPopup.numberOfItems > 1
    }

    private func preferredPlaybackStatusText(snapshot: AppSnapshot) -> String {
        guard let appName = snapshot.preferredPlaybackAppName else {
            return "Using each macro's recorded target unless you choose a preferred playback app."
        }

        if snapshot.isPreferredPlaybackAppRunning {
            return "\(appName) is saved as the preferred playback app and will override each macro's recorded target."
        }

        return "\(appName) is saved as the preferred playback app, but it is not running. Launch it before playback."
    }
}

private final class HotKeyRecorderField: NSTextField {
    var onCapture: ((HotKeyDescriptor) -> Void)?
    private var isCapturing = false

    init() {
        super.init(frame: .zero)
        isEditable = false
        isBezeled = true
        drawsBackground = true
        focusRingType = .default
        alignment = .center
        placeholderString = "Click and press keys"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        isCapturing = true
        stringValue = "Type shortcut"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        guard let descriptor = HotKeyCenter.descriptor(from: event) else {
            NSSound.beep()
            return
        }

        stringValue = descriptor.displayText
        isCapturing = false
        onCapture?(descriptor)
    }
}
