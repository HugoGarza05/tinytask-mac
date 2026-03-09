import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var toolbarWindowController: ToolbarWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var routineWindowController: RoutineWindowController?
    private var setupWindowController: SetupWindowController?
    private var statusItem: NSStatusItem?
    private var menuItems: [String: NSMenuItem] = [:]

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        appState.start()

        let toolbar = ToolbarWindowController(appState: appState)
        toolbar.showWindow(nil)
        toolbar.window?.center()
        toolbar.window?.makeKeyAndOrderFront(nil)
        toolbarWindowController = toolbar

        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateDidChange),
            name: .appStateDidChange,
            object: appState
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPreferences),
            name: .openPreferencesWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenRoutineEditor),
            name: .openRoutineEditorWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSetupWindow),
            name: .openSetupWindow,
            object: nil
        )

        NSApp.activate(ignoringOtherApps: true)
        if appState.shouldPresentSetupWindowOnLaunch() {
            openSetupWindow()
        }
        refreshStatusMenu()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            appState.openDocument(at: URL(fileURLWithPath: filename))
        }
        sender.reply(toOpenOrPrint: .success)
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
    private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(appState: appState)
        }

        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func openSetupWindow() {
        if setupWindowController == nil {
            setupWindowController = SetupWindowController(appState: appState)
        }

        setupWindowController?.showWindow(nil)
        setupWindowController?.window?.center()
        setupWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func openRoutineEditor() {
        if routineWindowController == nil {
            routineWindowController = RoutineWindowController(appState: appState)
        }

        routineWindowController?.showWindow(nil)
        routineWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func checkForUpdates() {
        appState.openLatestReleasePage()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc
    private func handleAppStateDidChange() {
        refreshStatusMenu()
    }

    @objc
    private func handleOpenPreferences() {
        openPreferences()
    }

    @objc
    private func handleOpenRoutineEditor() {
        openRoutineEditor()
    }

    @objc
    private func handleOpenSetupWindow() {
        openSetupWindow()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "TM"
        let menu = NSMenu()

        let record = NSMenuItem(title: "Record", action: #selector(toggleRecording), keyEquivalent: "")
        let play = NSMenuItem(title: "Play", action: #selector(togglePlayback), keyEquivalent: "")
        let open = NSMenuItem(title: "Open…", action: #selector(openMacro), keyEquivalent: "")
        let save = NSMenuItem(title: "Save…", action: #selector(saveMacro), keyEquivalent: "")
        let openRoutine = NSMenuItem(title: "Open Routine…", action: #selector(openRoutine), keyEquivalent: "")
        let saveRoutine = NSMenuItem(title: "Save Routine…", action: #selector(saveRoutine), keyEquivalent: "")
        let editRoutine = NSMenuItem(title: "Edit Routine…", action: #selector(openRoutineEditor), keyEquivalent: "")
        let runRoutine = NSMenuItem(title: "Run Routine", action: #selector(runRoutine), keyEquivalent: "")
        let stopRoutine = NSMenuItem(title: "Stop Routine", action: #selector(stopRoutine), keyEquivalent: "")
        let setup = NSMenuItem(title: "Set Up Permissions…", action: #selector(openSetupWindow), keyEquivalent: "")
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")

        [record, play, open, save].forEach {
            $0.target = self
            menu.addItem($0)
        }

        menu.addItem(.separator())

        [openRoutine, saveRoutine, editRoutine, runRoutine, stopRoutine].forEach {
            $0.target = self
            menu.addItem($0)
        }

        menu.addItem(.separator())

        [setup, updates].forEach {
            $0.target = self
            menu.addItem($0)
        }

        menu.addItem(.separator())

        [prefs, quit].forEach {
            $0.target = self
            menu.addItem($0)
        }

        statusItem.menu = menu
        self.statusItem = statusItem
        menuItems = [
            "record": record,
            "play": play,
            "open": open,
            "save": save,
            "openRoutine": openRoutine,
            "saveRoutine": saveRoutine,
            "editRoutine": editRoutine,
            "runRoutine": runRoutine,
            "stopRoutine": stopRoutine
        ]
    }

    private func refreshStatusMenu() {
        let snapshot = appState.snapshot()
        menuItems["record"]?.title = snapshot.isRecording ? "Stop Recording" : "Record"
        menuItems["record"]?.isEnabled = !snapshot.shouldBlockAutomation || snapshot.isRecording
        menuItems["play"]?.title = snapshot.isPlaying ? "Stop Playback" : "Play"
        menuItems["play"]?.isEnabled = (snapshot.hasMacroLoaded || snapshot.isPlaying) && !snapshot.isRoutineRunning && !snapshot.shouldBlockAutomation
        menuItems["save"]?.isEnabled = snapshot.hasMacroLoaded
        menuItems["openRoutine"]?.isEnabled = !snapshot.isRoutineRunning
        menuItems["saveRoutine"]?.isEnabled = snapshot.hasRoutineLoaded
        menuItems["editRoutine"]?.isEnabled = !snapshot.isRoutineRunning
        menuItems["runRoutine"]?.isEnabled = snapshot.hasRoutineLoaded && !snapshot.isRoutineRunning && !snapshot.shouldBlockAutomation
        menuItems["stopRoutine"]?.isEnabled = snapshot.isRoutineRunning

        if snapshot.isRecording {
            statusItem?.button?.title = "TM REC"
        } else if snapshot.isRoutineRunning {
            statusItem?.button?.title = "TM RT"
        } else if snapshot.isPlaying {
            statusItem?.button?.title = "TM ▶"
        } else {
            statusItem?.button?.title = "TM"
        }
    }
}
