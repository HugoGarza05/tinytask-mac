import AppKit
import Foundation

final class RoutineWindowController: NSWindowController, NSTextFieldDelegate {
    private let appState: AppState

    private let nameField = NSTextField(string: "")
    private let targetLabel = NSTextField(labelWithString: "Target app: Not set")
    private let mainMacroLabel = NSTextField(labelWithString: "No main macro selected")
    private let chooseMainButton = NSButton(title: "Choose Main Macro", target: nil, action: nil)
    private let clearMainButton = NSButton(title: "Clear Main", target: nil, action: nil)
    private let addInterruptButton = NSButton(title: "Add Interrupt", target: nil, action: nil)
    private let interruptStack = NSStackView()
    private let scrollView = NSScrollView()

    init(appState: AppState) {
        self.appState = appState

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Routine Editor"

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

        let titleLabel = NSTextField(labelWithString: "Routine")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        nameField.placeholderString = "Routine Name"
        nameField.delegate = self

        targetLabel.maximumNumberOfLines = 2
        targetLabel.textColor = .secondaryLabelColor

        mainMacroLabel.maximumNumberOfLines = 2

        chooseMainButton.target = self
        chooseMainButton.action = #selector(chooseMainMacro)

        clearMainButton.target = self
        clearMainButton.action = #selector(clearMainMacro)

        addInterruptButton.target = self
        addInterruptButton.action = #selector(addInterrupt)

        let nameGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Name"), nameField]
        ])
        nameGrid.rowSpacing = 8
        nameGrid.columnSpacing = 12

        let mainButtons = NSStackView(views: [chooseMainButton, clearMainButton])
        mainButtons.orientation = .horizontal
        mainButtons.spacing = 8
        mainButtons.distribution = .fillEqually

        let mainSection = NSStackView(views: [
            NSTextField(labelWithString: "Main Macro"),
            mainMacroLabel,
            mainButtons
        ])
        mainSection.orientation = .vertical
        mainSection.spacing = 8

        let interruptsHeader = NSStackView(views: [NSTextField(labelWithString: "Timed Interrupts"), addInterruptButton])
        interruptsHeader.orientation = .horizontal
        interruptsHeader.spacing = 8
        interruptsHeader.distribution = .fill

        interruptStack.orientation = .vertical
        interruptStack.spacing = 10
        interruptStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        interruptStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(interruptStack)
        NSLayoutConstraint.activate([
            interruptStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            interruptStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            interruptStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            interruptStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            interruptStack.widthAnchor.constraint(equalTo: documentView.widthAnchor)
        ])

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [
            titleLabel,
            nameGrid,
            targetLabel,
            mainSection,
            separator,
            interruptsHeader,
            scrollView
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
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func refresh() {
        let routine = appState.routineDocument()
        nameField.stringValue = routine.name
        targetLabel.stringValue = "Target app: \(routine.targetAppName ?? "Not set")"
        mainMacroLabel.stringValue = routine.mainEntry?.macroReference.displayName ?? "No main macro selected"
        clearMainButton.isEnabled = routine.mainEntry != nil

        rebuildInterruptRows(entries: routine.interruptEntries)
    }

    private func rebuildInterruptRows(entries: [RoutineInterruptEntry]) {
        for view in interruptStack.arrangedSubviews {
            interruptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !entries.isEmpty else {
            let emptyLabel = NSTextField(wrappingLabelWithString: "No timed interrupts yet. Add one for relogging or other periodic recovery flows.")
            emptyLabel.textColor = .secondaryLabelColor
            interruptStack.addArrangedSubview(emptyLabel)
            return
        }

        for entry in entries.sorted(by: { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }) {
            let row = RoutineInterruptRowView(entry: entry)
            row.onToggleEnabled = { [weak self] value in
                self?.appState.updateRoutineInterruptEnabled(value, for: entry.id)
            }
            row.onNameChange = { [weak self] value in
                self?.appState.updateRoutineInterruptName(value, for: entry.id)
            }
            row.onChooseMacro = { [weak self] in
                self?.appState.chooseRoutineInterruptMacro(for: entry.id)
            }
            row.onIntervalChange = { [weak self] value in
                self?.appState.updateRoutineInterruptIntervalMinutes(value, for: entry.id)
            }
            row.onPriorityChange = { [weak self] value in
                self?.appState.updateRoutineInterruptPriority(value, for: entry.id)
            }
            row.onRemove = { [weak self] in
                self?.appState.removeRoutineInterrupt(id: entry.id)
            }
            interruptStack.addArrangedSubview(row)
        }
    }

    @objc
    private func chooseMainMacro() {
        appState.chooseRoutineMainMacro()
    }

    @objc
    private func clearMainMacro() {
        appState.clearRoutineMainMacro()
    }

    @objc
    private func addInterrupt() {
        appState.addRoutineInterrupt()
    }

    @objc
    private func handleAppStateDidChange() {
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == nameField else {
            return
        }

        appState.updateRoutineName(field.stringValue)
    }
}

private final class RoutineInterruptRowView: NSView, NSTextFieldDelegate {
    var onToggleEnabled: ((Bool) -> Void)?
    var onNameChange: ((String) -> Void)?
    var onChooseMacro: (() -> Void)?
    var onIntervalChange: ((Int) -> Void)?
    var onPriorityChange: ((Int) -> Void)?
    var onRemove: (() -> Void)?

    private let enabledCheckbox: NSButton
    private let nameField = NSTextField(string: "")
    private let macroLabel = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "Choose Macro", target: nil, action: nil)
    private let intervalField = NSTextField(string: "")
    private let priorityPopup = NSPopUpButton()
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    init(entry: RoutineInterruptEntry) {
        enabledCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.separatorColor.cgColor

        nameField.stringValue = entry.name
        nameField.delegate = self

        macroLabel.stringValue = entry.macroReference.displayName
        macroLabel.maximumNumberOfLines = 2
        macroLabel.textColor = .secondaryLabelColor

        enabledCheckbox.state = entry.isEnabled ? .on : .off
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(toggleEnabled)

        chooseButton.target = self
        chooseButton.action = #selector(chooseMacro)

        intervalField.stringValue = String(entry.intervalMinutes)
        intervalField.alignment = .center
        intervalField.delegate = self
        intervalField.placeholderString = "Minutes"

        priorityPopup.addItems(withTitles: (1...9).map { "P\($0)" })
        priorityPopup.selectItem(withTitle: "P\(entry.priority)")
        priorityPopup.target = self
        priorityPopup.action = #selector(priorityChanged)

        removeButton.target = self
        removeButton.action = #selector(removeRow)

        let headerRow = NSStackView(views: [
            enabledCheckbox,
            NSTextField(labelWithString: "Name"),
            nameField,
            NSTextField(labelWithString: "Every"),
            intervalField,
            NSTextField(labelWithString: "min"),
            NSTextField(labelWithString: "Priority"),
            priorityPopup,
            chooseButton,
            removeButton
        ])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        headerRow.alignment = .centerY

        let contentStack = NSStackView(views: [headerRow, macroLabel])
        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            intervalField.widthAnchor.constraint(equalToConstant: 60),
            priorityPopup.widthAnchor.constraint(equalToConstant: 70)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func toggleEnabled() {
        onToggleEnabled?(enabledCheckbox.state == .on)
    }

    @objc
    private func chooseMacro() {
        onChooseMacro?()
    }

    @objc
    private func priorityChanged() {
        onPriorityChange?(priorityPopup.indexOfSelectedItem + 1)
    }

    @objc
    private func removeRow() {
        onRemove?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }

        if field == nameField {
            onNameChange?(field.stringValue)
        } else if field == intervalField {
            onIntervalChange?(Int(field.stringValue) ?? 1)
        }
    }
}
