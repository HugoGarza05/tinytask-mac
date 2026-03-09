import AppKit
import Foundation

final class SetupWindowController: NSWindowController {
    private let appState: AppState

    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let inputMonitoringStatusLabel = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(wrappingLabelWithString: "")
    private let continueButton = NSButton(title: "Continue", target: nil, action: nil)

    init(appState: AppState) {
        self.appState = appState

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up TinyTaskMac"

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let titleLabel = NSTextField(labelWithString: "Finish setup before recording or playback.")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        statusLabel.maximumNumberOfLines = 3
        statusLabel.textColor = .secondaryLabelColor

        accessibilityStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        inputMonitoringStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)

        helperLabel.maximumNumberOfLines = 4
        helperLabel.textColor = .secondaryLabelColor

        let accessibilityRow = permissionRow(
            title: "Accessibility",
            detail: "Required to send mouse and keyboard events to the target app.",
            statusLabel: accessibilityStatusLabel
        )
        let inputMonitoringRow = permissionRow(
            title: "Input Monitoring",
            detail: "Required to record your own inputs into new macros.",
            statusLabel: inputMonitoringStatusLabel
        )

        let accessibilityButton = NSButton(title: "Grant Accessibility", target: self, action: #selector(requestAccessibilityAccess))
        let inputMonitoringButton = NSButton(title: "Open Input Monitoring", target: self, action: #selector(openInputMonitoring))
        let recheckButton = NSButton(title: "Re-check Permissions", target: self, action: #selector(recheckPermissions))
        continueButton.target = self
        continueButton.action = #selector(continueIntoApp)
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))

        let primaryButtons = NSStackView(views: [accessibilityButton, inputMonitoringButton, recheckButton])
        primaryButtons.orientation = .horizontal
        primaryButtons.spacing = 10
        primaryButtons.distribution = .fillEqually

        let exitButtons = NSStackView(views: [continueButton, quitButton])
        exitButtons.orientation = .horizontal
        exitButtons.spacing = 10
        exitButtons.distribution = .fillEqually

        let stack = NSStackView(views: [
            titleLabel,
            statusLabel,
            accessibilityRow,
            inputMonitoringRow,
            helperLabel,
            primaryButtons,
            exitButtons
        ])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    private func permissionRow(title: String, detail: String, statusLabel: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.maximumNumberOfLines = 3
        detailLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, detailLabel, statusLabel])
        textStack.orientation = .vertical
        textStack.spacing = 4

        let wrapper = NSStackView(views: [textStack])
        wrapper.orientation = .vertical
        wrapper.spacing = 0
        wrapper.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 10
        wrapper.layer?.borderWidth = 1
        wrapper.layer?.borderColor = NSColor.separatorColor.cgColor
        return wrapper
    }

    private func refresh() {
        let snapshot = appState.snapshot()
        let checklist = snapshot.permissionChecklist

        statusLabel.stringValue = snapshot.shouldBlockAutomation
            ? "TinyTaskMac keeps recording, playback, and routine start disabled until both macOS permissions are granted."
            : "Permissions are in place. You can continue into the app or reopen this window later from the menu."

        accessibilityStatusLabel.stringValue = checklist.accessibilityGranted ? "Status: Granted" : "Status: Action required"
        accessibilityStatusLabel.textColor = checklist.accessibilityGranted ? .systemGreen : .systemOrange

        inputMonitoringStatusLabel.stringValue = checklist.inputMonitoringGranted ? "Status: Granted" : "Status: Action required"
        inputMonitoringStatusLabel.textColor = checklist.inputMonitoringGranted ? .systemGreen : .systemOrange

        helperLabel.stringValue = checklist.inputMonitoringGranted
            ? "If permissions change later, TinyTaskMac will send you back here instead of showing a blocking alert."
            : "macOS may require you to quit and reopen TinyTaskMac after enabling Input Monitoring."

        continueButton.title = checklist.isGranted ? "Continue" : "Continue Without Permissions"
    }

    @objc
    private func requestAccessibilityAccess() {
        appState.requestAccessibilityAccess()
    }

    @objc
    private func openInputMonitoring() {
        appState.openInputMonitoringSettings()
    }

    @objc
    private func recheckPermissions() {
        appState.recheckPermissions()
    }

    @objc
    private func continueIntoApp() {
        appState.dismissSetupWindow()
        window?.close()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc
    private func handleAppStateDidChange() {
        refresh()
    }
}
