import AppKit
import ScratchCore

/// Connects the editor, the sidebar and the storage: it decides which note is open, keeps that note's text and the
/// session saved, and keeps the sidebar list current. The editor and the sidebar only report what the user did.
///
/// **Threading.** Everything here runs on the main thread (the class is `@MainActor`). Writes go to one private serial
/// queue, so typing never waits for the disk. The two exceptions wait for that queue on purpose: `persistNow()` and
/// `open(_:)`, which must not leave a write behind.
///
/// **Lifetime.** The coordinator owns its `Autosaver`, and the autosaver does not keep itself alive: a dirty autosaver
/// that is released skips its pending save. Whoever creates the coordinator must therefore keep it for as long as the
/// app runs (`AppDelegate` does). The autosaver's save closure holds the coordinator weakly.
///
/// There is one tab, so the session is the current note, its cursor and its scroll position, and the font size. Later
/// tasks of plan 2 add more tabs.
///
/// **Undo.** Every note has an undo manager of its own for as long as the app runs (spec §6.6). The coordinator keeps
/// them and gives the editor the one of the note it shows, so leaving a note and coming back finds its history.
@MainActor
final class SessionCoordinator {
    private let storage: ScratchStorage
    private let editor: EditorViewController
    private let sidebar: SidebarViewController
    private let storageQueue = DispatchQueue(label: "io.github.ldellisola.Scratch.storage", qos: .utility)
    /// Calls `saveNow()` 300 ms after the last change and at most 1 s after the first one. Set at the end of `init`.
    private var autosaver: Autosaver!

    /// The note in the editor, with the user's edits. Nil until `restore()` has run.
    private var current: Note?
    /// Whether `current` has edits that are not handed to the storage queue yet.
    private var currentIsDirty = false
    /// The undo history of each note that was shown in this session. It does not survive quitting (spec §6.6).
    private var undoManagers: [NoteID: UndoManager] = [:]
    /// The note font size, the same for every note (spec §6.4). Restored with the session and saved with it.
    private var fontSize = FontSize.standard
    /// Notes that nobody has used yet: created in this session, or restored empty. Leaving one of them while it is
    /// still empty discards it (spec §6.3).
    private var untouchedNoteIDs: Set<NoteID> = []

    /// The note list as last read from the storage, without the filtering `renderSidebar()` does.
    private var latestSummaries: [NoteSummary] = []
    /// Numbers the reads of the note list. A result is shown only when no newer read was asked for since, so a slow,
    /// stale list never overwrites a newer one.
    private var summariesRequest = 0

    init(storage: ScratchStorage, editor: EditorViewController, sidebar: SidebarViewController) {
        self.storage = storage
        self.editor = editor
        self.sidebar = sidebar

        // The autosaver fires on the main queue, where `assumeIsolated` is valid. It calls `flush` from the main
        // thread too (`persistNow`).
        autosaver = Autosaver(scheduler: DispatchAutosaveScheduler(queue: .main)) { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        editor.onTextChange = { [weak self] text in self?.textDidChange(text) }
        editor.onTitleChange = { [weak self] title in self?.titleDidChange(title) }
        editor.onViewStateChange = { [weak self] in self?.viewStateDidChange() }
        sidebar.onSelect = { [weak self] id in self?.open(id) }
    }

    // MARK: Restoring

    /// Shows the note of the saved session, with its cursor and scroll position, and starts loading the note list.
    /// Without a usable session it starts a new empty note. Only the active note is read before the window shows
    /// (spec §7): the list loads on the storage queue.
    func restore() {
        let (note, tab) = activeTab()
        current = note
        currentIsDirty = false
        if note.isEmpty { untouchedNoteIDs.insert(note.id) }
        editor.setFontSize(fontSize)
        show(note, tab: tab)
        renderSidebar()
        requestSummaries()
    }

    /// The tab to show and its note, from the saved session (spec §6.6): the active tab, or else the first tab that
    /// still has a note. A tab whose note is missing or deleted is dropped. Without a usable session it creates an
    /// empty note and saves a one-tab session for it.
    ///
    /// When the storage cannot be read at all, the owner still gets an editor: it holds a new note that stays unsaved,
    /// and every save tries again.
    private func activeTab() -> (note: Note, tab: TabState) {
        do {
            if let state = try storage.session.load() {
                fontSize = state.fontSize
                let others = state.tabs.indices.filter { $0 != state.activeTabIndex }
                let active = state.tabs.indices.filter { $0 == state.activeTabIndex }
                for index in active + others {
                    let tab = state.tabs[index]
                    if let note = try storage.notes.note(tab.noteID), note.deletedAt == nil {
                        return (note, tab)
                    }
                }
            }
            let note = try storage.notes.create(now: Date())
            let tab = TabState(noteID: note.id, selection: 0, scrollY: 0)
            try storage.session.save(SessionState(tabs: [tab], activeTabIndex: 0, fontSize: fontSize))
            return (note, tab)
        } catch {
            report("cannot read the saved session: \(error)")
            let now = Date()
            let note = Note(id: NoteID.make(), title: "", body: "", createdAt: now, modifiedAt: now)
            currentIsDirty = true
            autosaver.markDirty()
            return (note, TabState(noteID: note.id, selection: 0, scrollY: 0))
        }
    }

    // MARK: Opening notes

    /// Starts a new empty note, shows it and puts the cursor in it. The note is not listed until it has text, and it
    /// is discarded when the user leaves it untouched (spec §6.3).
    func newNote() {
        guard current != nil else { return }
        do {
            let note = try storage.notes.create(now: Date())
            untouchedNoteIDs.insert(note.id)
            switchTo(note)
            editor.focus()
        } catch {
            report("cannot create a note: \(error)")
        }
    }

    /// Shows the note `id` in the tab. The note being left is saved first, or discarded when it was never used.
    func open(_ id: NoteID) {
        guard let leaving = current, leaving.id != id else { return }
        // The performance tests measure this interval: from the click until the note is on screen.
        Signposts.beginEditorInterval("switch-note")
        do {
            guard let note = try storage.notes.note(id), note.deletedAt == nil else {
                // The note is gone, so the list is stale.
                requestSummaries()
                return
            }
            switchTo(note)
        } catch {
            report("cannot open note \(id.rawValue): \(error)")
        }
    }

    /// Leaves the current note and shows `next`, which is not the current note.
    private func switchTo(_ next: Note) {
        guard let leaving = current else { return }
        let discardsLeaving = isUntouched(leaving)
        // An untouched note is not worth a write. Its row goes below.
        if discardsLeaving { currentIsDirty = false }
        // After this every write for the leaving note is done, and the session says which note it was.
        persistNow()
        if discardsLeaving { discard(leaving) }

        current = next
        currentIsDirty = false
        show(next, tab: TabState(noteID: next.id, selection: 0, scrollY: 0))
        // The session now points at `next`: the autosaver writes it soon.
        autosaver.markDirty()
        renderSidebar()
        requestSummaries()
    }

    /// Shows `note` in the editor with its own undo history, which switching notes never clears.
    private func show(_ note: Note, tab: TabState) {
        editor.show(note, tab: tab, undoManager: undoManager(for: note.id), isReadOnly: false)
    }

    /// The undo manager of the note `id`, made when the note is first shown.
    private func undoManager(for id: NoteID) -> UndoManager {
        if let existing = undoManagers[id] { return existing }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }

    /// True for a note that nobody has used: it is new (or was restored empty) and is still empty.
    private func isUntouched(_ note: Note) -> Bool {
        note.isEmpty && untouchedNoteIDs.contains(note.id)
    }

    /// Deletes the row of a note that was never used. Needs an idle storage queue, so call it after `persistNow()`.
    private func discard(_ note: Note) {
        untouchedNoteIDs.remove(note.id)
        undoManagers[note.id] = nil
        latestSummaries.removeAll { $0.id == note.id }
        do {
            try storage.notes.discard(note.id)
        } catch {
            report("cannot discard the empty note \(note.id.rawValue): \(error)")
        }
    }

    // MARK: Saving

    /// Writes everything that is unsaved, and returns when it is on disk. For quitting, deactivating and switching
    /// notes. Call it on the main thread only.
    ///
    /// The session is written every time, even when no change was reported, so that the cursor and scroll position
    /// are right whatever happened since the last save.
    func persistNow() {
        autosaver.markDirty()
        autosaver.flush()
        storageQueue.sync {}
    }

    private func textDidChange(_ text: String) {
        guard var note = current else { return }
        note.body = text
        note.modifiedAt = Date()
        current = note
        currentIsDirty = true
        autosaver.markDirty()
    }

    /// The title field changed. The title is part of the note, so it is saved like its text, and the note moves to the
    /// top of the sidebar.
    private func titleDidChange(_ title: String) {
        guard var note = current else { return }
        note.title = title
        note.modifiedAt = Date()
        current = note
        currentIsDirty = true
        autosaver.markDirty()
    }

    /// The font size changes to what `transform` makes of the current one, within the limits of `FontSize`: the editor
    /// shows it at once, and the session saves it with the next write (spec §6.4: the size is remembered).
    func changeFontSize(_ transform: (Double) -> Double) {
        let size = FontSize.clamped(transform(fontSize))
        guard size != fontSize else { return }
        fontSize = size
        editor.setFontSize(size)
        autosaver.markDirty()
    }

    /// The cursor or the scroll position moved. The session holds them, so it is saved soon (spec §6.6).
    private func viewStateDidChange() {
        autosaver.markDirty()
    }

    /// The autosaver's save: captures what is unsaved on the main thread, then writes it on the storage queue. A
    /// changed note is followed by a read of the list, because its title, preview and place in the list changed.
    private func saveNow() {
        guard let note = current else { return }
        let unsavedNote = currentIsDirty ? note : nil
        currentIsDirty = false
        let tab = TabState(
            noteID: note.id, selection: editor.currentSelection, scrollY: editor.currentScrollY,
            scrollAnchor: editor.currentScrollAnchor)
        let session = SessionState(tabs: [tab], activeTabIndex: 0, fontSize: fontSize)
        let request: Int
        if unsavedNote != nil {
            summariesRequest += 1
            request = summariesRequest
        } else {
            request = 0
        }

        let storage = self.storage
        storageQueue.async { [weak self, storage] in
            do {
                if let unsavedNote { try storage.notes.save(unsavedNote) }
                try storage.session.save(session)
            } catch {
                report("cannot save: \(error)")
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.saveFailed(unsavedNote) }
                }
                return
            }
            guard unsavedNote != nil else { return }
            let summaries = try? storage.notes.summaries()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didReadSummaries(summaries, request: request) }
            }
        }
    }

    /// A write failed. The text is still in the editor, so keep it marked as unsaved and try again.
    private func saveFailed(_ note: Note?) {
        if let note, note.id == current?.id { currentIsDirty = true }
        autosaver.markDirty()
    }

    // MARK: The note list

    /// Reads the note list on the storage queue, after every write that is already queued, and shows it.
    private func requestSummaries() {
        summariesRequest += 1
        let request = summariesRequest
        let storage = self.storage
        storageQueue.async { [weak self, storage] in
            let summaries = try? storage.notes.summaries()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didReadSummaries(summaries, request: request) }
            }
        }
    }

    private func didReadSummaries(_ summaries: [NoteSummary]?, request: Int) {
        guard request == summariesRequest, let summaries else { return }
        latestSummaries = summaries
        renderSidebar()
    }

    /// Shows the note list with the current note highlighted. A new note that nobody has used yet is not listed (spec
    /// §6.3: it never appears in the list unless it gets text).
    private func renderSidebar() {
        let hiddenID = current.flatMap { isUntouched($0) ? $0.id : nil }
        sidebar.reload(latestSummaries.filter { $0.id != hiddenID }, selecting: current?.id)
    }
}

/// Storage errors have nowhere to go in a window that never asks anything, so they go to the standard error stream.
private nonisolated func report(_ message: String) {
    FileHandle.standardError.write(Data("Scratch: \(message)\n".utf8))
}
