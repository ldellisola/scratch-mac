import AppKit
import ScratchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var windowController: MainWindowController?

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

    private func launch() throws {
        let environment = try AppEnvironment.bootstrap(arguments: CommandLine.arguments)
        self.environment = environment

        if let appearance = environment.options.appearance {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        }

        let (note, tab) = try Self.activeTab(in: environment.storage, now: Date())
        let editor = EditorViewController(textKit: environment.options.textKit ?? .two)
        // Plan 1, task 8 replaces this placeholder with the note list.
        let sidebar = NSViewController()
        sidebar.view = NSView()
        let content = MainSplitViewController(sidebar: sidebar, editor: editor)
        let windowController = MainWindowController(environment: environment, content: content)
        self.windowController = windowController

        editor.show(note, selection: tab.selection, scrollY: tab.scrollY)
        windowController.showWindow(nil)
        editor.focus()
    }

    /// The tab to show and its note, from the saved session (spec §6.6): the active tab, or else the first tab that
    /// still has a note. A tab whose note is missing or deleted is dropped. Without a usable session it starts a new
    /// empty note and saves a one-tab session for it. Plan 1, task 8 moves this into the session coordinator.
    private static func activeTab(in storage: ScratchStorage, now: Date) throws -> (note: Note, tab: TabState) {
        if let state = try storage.session.load() {
            let others = state.tabs.indices.filter { $0 != state.activeTabIndex }
            let active = state.tabs.indices.filter { $0 == state.activeTabIndex }
            for index in active + others {
                let tab = state.tabs[index]
                if let note = try storage.notes.note(tab.noteID), note.deletedAt == nil {
                    return (note, tab)
                }
            }
        }
        let note = try storage.notes.create(now: now)
        let tab = TabState(noteID: note.id, selection: 0, scrollY: 0)
        try storage.session.save(SessionState(tabs: [tab], activeTabIndex: 0))
        return (note, tab)
    }

    /// The app cannot work without its storage. Say why, then quit.
    private func quit(after error: any Error) {
        FileHandle.standardError.write(Data("Scratch cannot start: \(error)\n".utf8))
        NSAlert(error: error).runModal()
        exit(EXIT_FAILURE)
    }
}
