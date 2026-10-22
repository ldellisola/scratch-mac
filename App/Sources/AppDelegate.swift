import AppKit
import ScratchCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var environment: AppEnvironment?
    private var windowController: MainWindowController?
    /// The editor, which the window asks for the undo manager of the note it shows (`windowWillReturnUndoManager`).
    private var editor: EditorViewController?
    /// The target of the menu items that belong to the app. A menu item holds its target weakly, so it stays here.
    private let commands = AppCommands()
    /// The coordinator owns the autosaver, which does not keep itself alive: it stays here for the app's lifetime.
    private var coordinator: SessionCoordinator?
    /// The window's toolbar keeps its delegate weakly.
    private var toolbarController: ToolbarController?
    /// What the attachments are: the editor draws the token lines of a note from it (plan 5, task 4). The editor holds it
    /// too, and the coordinator is told of the copies of new attachments through it (plan 5, task 5).
    private var attachmentCatalog: AttachmentCatalog?
    /// Only with `-ScratchFrameMonitor` (the performance tests).
    private var frameMonitor: FrameMonitor?

    // MARK: Launch

    /// The launch sequence: open the storage, restore the session, show the window with the active note and put the
    /// cursor in it. It does as little as possible before the first frame (spec §7).
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainMenu.install(in: NSApp, commands: commands)
        do {
            try launch()
        } catch {
            quit(after: error)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    /// Closing the window quits the app, like Notepad (spec §6.6).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Quitting writes everything that is unsaved before the process ends (spec §6.6).
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.persistNow()
    }

    /// So does switching to another app: whatever happens to Scratch next, the notes are on disk.
    func applicationDidResignActive(_ notification: Notification) {
        coordinator?.persistNow()
    }

    /// Coming back reads the note list again, so that "Today" and the time labels are those of today when the app was
    /// left open over midnight (spec §6.2), and purges Recently Deleted when that was not done in the last hour.
    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator?.refreshNoteList()
        coordinator?.purgeExpiredNotes(now: Date())
    }

    private func launch() throws {
        let environment = try AppEnvironment.bootstrap(arguments: CommandLine.arguments)
        self.environment = environment
        LaunchTimer.mark("storage")

        if let appearance = environment.options.appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        }

        let editor = EditorViewController()
        self.editor = editor
        // The editor draws an attachment line from the catalog, so it has it before the first note is shown.
        let attachmentCatalog = AttachmentCatalog(store: environment.storage.attachments)
        self.attachmentCatalog = attachmentCatalog
        editor.attachmentCatalog = attachmentCatalog
        let sidebar = SidebarViewController()
        let tabStrip = TabStripViewController()
        let editorArea = EditorAreaViewController(tabStrip: tabStrip, editor: editor)
        let content = MainSplitViewController(
            sidebar: sidebar, editorArea: editorArea, remembersLayout: !environment.options.isIsolated)
        let windowController = MainWindowController(environment: environment, content: content)
        self.windowController = windowController
        // The Edit menu's Undo asks the window for its undo manager, and the window asks this delegate.
        windowController.window?.delegate = self

        let coordinator = SessionCoordinator(
            storage: environment.storage, editor: editor, sidebar: sidebar, tabStrip: tabStrip)
        self.coordinator = coordinator
        let toolbarController = ToolbarController()
        toolbarController.onNewNote = { [weak coordinator] in coordinator?.newNoteInNewTab() }
        toolbarController.onTogglePin = { [weak coordinator] in coordinator?.togglePinOfActiveNote() }
        toolbarController.onAttach = { [weak editor] in editor?.attachFiles() }
        self.toolbarController = toolbarController
        windowController.window?.toolbar = toolbarController.makeToolbar()

        // File > New Note, New Tab and Close Tab, and Window > Show Next and Previous Tab and Select Tab (spec §6.3).
        commands.onNewNote = { [weak coordinator] in coordinator?.newNoteInNewTab() }
        commands.onCloseTab = { [weak coordinator] in coordinator?.closeActiveTab() }
        commands.onNextTab = { [weak coordinator] in coordinator?.selectNextTab() }
        commands.onPreviousTab = { [weak coordinator] in coordinator?.selectPreviousTab() }
        commands.onSelectTabNumber = { [weak coordinator] number in coordinator?.selectTab(number: number) }
        // File > Pin Note and Edit > Search Notes (spec §6.2), and the toolbar's pin button, which shows the pin of the
        // note in the active tab.
        commands.onTogglePin = { [weak coordinator] in coordinator?.togglePinOfActiveNote() }
        commands.onFocusSearch = { [weak sidebar] in sidebar?.focusSearch() }
        // File > Attach File… (⇧⌘A) and the paperclip (spec §6.4): the editor asks for the files and puts them in at the caret.
        commands.onAttachFile = { [weak editor] in editor?.attachFiles() }
        let appCommands = commands
        coordinator.onActiveNotePinChange = { [weak toolbarController, weak appCommands] pinned, enabled in
            toolbarController?.setPinned(pinned, enabled: enabled)
            // A note in Recently Deleted can be neither pinned nor attached to.
            toolbarController?.setAttachEnabled(enabled)
            appCommands?.setActiveNotePin(pinned: pinned, enabled: enabled)
        }
        // Help > Launch Times… shows how long the launches of this Mac took (plan 6 task 1).
        commands.onShowLaunchTimes = { [weak self] in self?.showLaunchTimes() }
        // Scratch > About Scratch shows the licences of tree-sitter and its grammars as its credits (plan 5 task 7).
        commands.onShowAbout = { NSApp.orderFrontStandardAboutPanel(options: AboutCredits.panelOptions()) }
        // View > Bigger, Smaller and Actual Size (spec §6.4).
        commands.onBigger = { [weak coordinator] in coordinator?.changeFontSize(FontSize.larger) }
        commands.onSmaller = { [weak coordinator] in coordinator?.changeFontSize(FontSize.smaller) }
        commands.onActualSize = { [weak coordinator] in coordinator?.changeFontSize { _ in FontSize.standard } }
        // UI tests read the editor's state from an element that a normal launch does not have.
        if environment.options.isIsolated { editor.installDebugStateElement() }

        coordinator.restore()
        LaunchTimer.mark("restore")
        windowController.showWindow(nil)
        editor.focus()
        LaunchTimer.mark("window")
        // The launch log: when the main run loop is next idle the window is on screen and takes keystrokes, which is where the
        // launch ends (spec §7). Everything the log does comes after that mark, on its own queue (`LaunchTimer.finish`).
        let dataDirectory = environment.storage.directory
        RunLoopIdle.onNext {
            LaunchTimer.mark("firstFrame")
            LaunchTimer.finish(dataDirectory: dataDirectory, version: LaunchTimesPanel.appVersion)
        }
        // Notes that were deleted more than 30 days ago are removed once the window is up (spec §6.2): one turn of the
        // main queue after the restore, so that it is not part of what the first frame waits for.
        // The sweep of the attachments that no note names comes after the purge, on the same queue, because the purge may
        // leave some (plan 5, "Never lose an attachment").
        DispatchQueue.main.async { [weak coordinator] in
            MainActor.assumeIsolated {
                coordinator?.purgeExpiredNotes(now: Date())
                coordinator?.sweepUnreferencedAttachments(now: Date())
            }
        }

        // The queries of the languages in the open tabs are compiled on the highlight queue once the first frame is out, so that
        // the first block in one of them is not coloured late (plan 5 task 7). After the signpost intervals of the frame, like
        // the chunks that style a long note.
        RunLoopIdle.onNext(order: RunLoopIdle.afterMeasurementsOrder) { [weak coordinator] in
            coordinator?.warmUpHighlighting()
        }

        if let file = environment.options.frameMonitorFile {
            let monitor = FrameMonitor(file: file, clipView: editor.clipView)
            monitor.start()
            frameMonitor = monitor
        }
    }

    /// Help > Launch Times…: the launch log in an alert, with Copy. The log is the one the launch loaded and appended to, or,
    /// in the moments before the queue has delivered it, the file's.
    private func showLaunchTimes() {
        guard let environment else { return }
        let log = LaunchTimer.log ?? LaunchLog.load(from: environment.storage.directory)
        LaunchTimesPanel.present(
            report: LaunchTimesPanel.report(of: log), over: windowController?.window)
    }

    // MARK: NSWindowDelegate

    /// Undo history is per note (spec §6.6): the window's undo manager is the one of the note in the editor. The text
    /// view uses it too, so the Edit menu and typing agree whichever of them AppKit asks.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editor?.activeUndoManager
    }

    /// The app cannot work without its storage. Say why, then quit.
    private func quit(after error: any Error) {
        FileHandle.standardError.write(Data("Scratch cannot start: \(error)\n".utf8))
        NSAlert(error: error).runModal()
        exit(EXIT_FAILURE)
    }
}
