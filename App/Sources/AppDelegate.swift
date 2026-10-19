import AppKit
import ScratchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var windowController: MainWindowController?
    /// The coordinator owns the autosaver, which does not keep itself alive: it stays here for the app's lifetime.
    private var coordinator: SessionCoordinator?
    /// The window's toolbar keeps its delegate weakly.
    private var toolbarController: ToolbarController?
    /// Only with `-ScratchFrameMonitor` (the performance tests).
    private var frameMonitor: FrameMonitor?

    // MARK: Launch

    /// The launch sequence: open the storage, restore the session, show the window with the active note and put the
    /// cursor in it. It does as little as possible before the first frame (spec §7).
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainMenu.install(in: NSApp)
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

    private func launch() throws {
        let environment = try AppEnvironment.bootstrap(arguments: CommandLine.arguments)
        self.environment = environment

        if let appearance = environment.options.appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        }

        let editor = EditorViewController()
        let sidebar = SidebarViewController()
        let content = MainSplitViewController(sidebar: sidebar, editor: editor)
        let windowController = MainWindowController(environment: environment, content: content)
        self.windowController = windowController

        let coordinator = SessionCoordinator(storage: environment.storage, editor: editor, sidebar: sidebar)
        self.coordinator = coordinator
        let toolbarController = ToolbarController()
        toolbarController.onNewNote = { [weak coordinator] in coordinator?.newNote() }
        self.toolbarController = toolbarController
        windowController.window?.toolbar = toolbarController.makeToolbar()

        coordinator.restore()
        windowController.showWindow(nil)
        editor.focus()

        if let file = environment.options.frameMonitorFile {
            let monitor = FrameMonitor(file: file, clipView: editor.clipView)
            monitor.start()
            frameMonitor = monitor
        }
    }

    /// The app cannot work without its storage. Say why, then quit.
    private func quit(after error: any Error) {
        FileHandle.standardError.write(Data("Scratch cannot start: \(error)\n".utf8))
        NSAlert(error: error).runModal()
        exit(EXIT_FAILURE)
    }
}
