import AppKit
import ScratchCore

/// Connects the editor, the tab strip, the sidebar and the storage: it decides which notes are open in which tabs and
/// which tab is active, keeps the active note's text and the session saved, pins notes, and keeps the sidebar list and
/// the tab titles current. The editor, the tab strip and the sidebar only report what the user did. The sidebar's data
/// (the reads, the search, the groups) is `NoteListModel`'s.
///
/// **Threading.** Everything here runs on the main thread (the class is `@MainActor`). Writes go to one private serial
/// queue, so typing never waits for the disk. The exceptions wait for that queue on purpose: `persistNow()`, which
/// every change of the active tab calls first so that no write is left behind for the note being left.
///
/// **Lifetime.** The coordinator owns its `Autosaver`, and the autosaver does not keep itself alive: a dirty autosaver
/// that is released skips its pending save. Whoever creates the coordinator must therefore keep it for as long as the
/// app runs (`AppDelegate` does). The autosaver's save closure holds the coordinator weakly.
///
/// **Tabs.** The open tabs are a `TabList` (ScratchCore), which holds the rules of spec §6.3: there is always a tab, and
/// a note is open in at most one. The editor shows the note of the active tab, and that note, `current`, is the only
/// one whose text is held here with unsaved edits. A note in another tab is as saved: leaving a tab writes it first.
/// A change of the tabs writes the session at once (`writeSessionNow`), and not 300 ms later with the next autosave, so
/// that a crash right after opening or closing a tab keeps the tabs.
///
/// **Undo.** Every note has an undo manager of its own for as long as the app runs (spec §6.6). The coordinator keeps
/// them and gives the editor the one of the note it shows, so leaving a note and coming back finds its history.
@MainActor
final class SessionCoordinator {
    private let storage: ScratchStorage
    private let editor: EditorViewController
    private let tabStrip: TabStripViewController
    private let storageQueue: DispatchQueue
    /// The sidebar's data: it reads the note list on `storageQueue` and shows it.
    private let noteList: NoteListModel
    /// Calls `saveNow()` 300 ms after the last change and at most 1 s after the first one. Set at the end of `init`.
    private var autosaver: Autosaver!

    /// The open tabs and the active one. Nil until `restore()` has run.
    private var tabs: TabList?
    /// The note of the active tab, with the user's edits. Nil until `restore()` has run.
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
    /// What the tab strip shows for each open tab. It comes from the note when the note is shown, and from the note
    /// list after each save, so a tab title follows an edit about as fast as the sidebar row does.
    private var tabItems: [NoteID: TabStripItem] = [:]

    /// Every live note as of the last read of the note list, whatever the search field says. The pin button and the
    /// menu item read the pin of the active note from it.
    private var latestLive: [NoteSummary] = []

    /// Called with whether the note of the active tab is pinned, and whether it may be pinned, after the tabs or the
    /// note list changed. `AppDelegate` shows it on the toolbar's pin button and the Pin Note menu item.
    var onActiveNotePinChange: ((_ pinned: Bool, _ enabled: Bool) -> Void)?

    init(
        storage: ScratchStorage, editor: EditorViewController, sidebar: SidebarViewController,
        tabStrip: TabStripViewController
    ) {
        let queue = DispatchQueue(label: "io.github.ldellisola.Scratch.storage", qos: .utility)
        self.storage = storage
        self.editor = editor
        self.tabStrip = tabStrip
        self.storageQueue = queue
        self.noteList = NoteListModel(storage: storage, storageQueue: queue, sidebar: sidebar)

        // The autosaver fires on the main queue, where `assumeIsolated` is valid. It calls `flush` from the main
        // thread too (`persistNow`).
        autosaver = Autosaver(scheduler: DispatchAutosaveScheduler(queue: .main)) { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        editor.onTextChange = { [weak self] text in self?.textDidChange(text) }
        editor.onTitleChange = { [weak self] title in self?.titleDidChange(title) }
        editor.onViewStateChange = { [weak self] in self?.viewStateDidChange() }
        sidebar.onOpen = { [weak self] id, inNewTab in self?.open(id, inNewTab: inNewTab) }
        sidebar.onSearch = { [weak self] text in self?.noteList.setSearchText(text) }
        sidebar.onTogglePin = { [weak self] id in self?.togglePin(id) }
        noteList.onLiveSummaries = { [weak self] summaries in self?.didReadLiveSummaries(summaries) }
        tabStrip.onSelect = { [weak self] index in self?.selectTab(at: index) }
        tabStrip.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabStrip.onNewTab = { [weak self] in self?.newNoteInNewTab() }
    }

    // MARK: Restoring

    /// Shows the tabs of the saved session, with the active note, its cursor and scroll position, and starts loading
    /// the note list. Without a usable session it starts one tab with a new empty note. The notes of all the saved
    /// tabs are read before the window shows, which is a few small reads (spec §7): the list loads on the storage
    /// queue.
    func restore() {
        let (list, note) = restoredTabs()
        tabs = list
        current = note
        if note.isEmpty { untouchedNoteIDs.insert(note.id) }
        tabItems[note.id] = Self.item(for: note)
        editor.setFontSize(fontSize)
        show(note, tab: list.active)
        renderTabs()
        renderSidebar()
        updatePinState()
        noteList.refresh()
    }

    /// The tabs to show and the note of the active one, from the saved session (spec §6.6). A tab whose note is missing
    /// or deleted is dropped, and so is a second tab for the same note. The active tab is the saved one, or else the
    /// first that is left. Without a usable session it creates an empty note and saves a one-tab session for it.
    ///
    /// When the storage cannot be read at all, the owner still gets an editor: it holds a new note that stays unsaved,
    /// and every save tries again.
    private func restoredTabs() -> (list: TabList, note: Note) {
        do {
            if let state = try storage.session.load() {
                fontSize = state.fontSize
                var kept: [TabState] = []
                var notes: [NoteID: Note] = [:]
                var activeKept: Int?
                for (index, tab) in state.tabs.enumerated() where notes[tab.noteID] == nil {
                    guard let note = try storage.notes.note(tab.noteID), note.deletedAt == nil else { continue }
                    notes[note.id] = note
                    if index == state.activeTabIndex { activeKept = kept.count }
                    kept.append(tab)
                }
                if !kept.isEmpty {
                    let list = TabList(tabs: kept, activeIndex: activeKept ?? 0)
                    for note in notes.values {
                        tabItems[note.id] = Self.item(for: note)
                        if note.isEmpty { untouchedNoteIDs.insert(note.id) }
                    }
                    if let active = notes[list.active.noteID] { return (list, active) }
                }
            }
            let note = try storage.notes.create(now: Date())
            let list = TabList(tabs: [TabState(noteID: note.id, selection: 0, scrollY: 0)], activeIndex: 0)
            try storage.session.save(list.session(fontSize: fontSize))
            return (list, note)
        } catch {
            report("cannot read the saved session: \(error)")
            let now = Date()
            let note = Note(id: NoteID.make(), title: "", body: "", createdAt: now, modifiedAt: now)
            currentIsDirty = true
            autosaver.markDirty()
            let list = TabList(tabs: [TabState(noteID: note.id, selection: 0, scrollY: 0)], activeIndex: 0)
            return (list, note)
        }
    }

    // MARK: Opening notes

    /// Starts a new empty note, opens it in a new tab at the end of the strip, and puts the cursor in it (⌘N, ⌘T and
    /// the toolbar button). The note is not listed until it has text, and it is discarded when its tab closes while it
    /// is still empty (spec §6.3).
    func newNoteInNewTab() {
        guard tabs != nil, current != nil else { return }
        let note: Note
        do {
            note = try storage.notes.create(now: Date())
        } catch {
            report("cannot create a note: \(error)")
            return
        }
        untouchedNoteIDs.insert(note.id)

        leaveCurrentNote(discardingIfUntouched: false)
        guard var list = tabs else { return }
        // As in a browser, a new tab goes at the end. A note opened from the sidebar goes next to the active tab
        // instead (`TabList.open`).
        list.select(list.tabs.count - 1)
        _ = list.open(note.id, inNewTab: true)
        tabs = list
        showActive(note)
        tabsDidChange()
        editor.focus()
    }

    /// Shows the note `id`, which the user opened from the sidebar.
    ///
    /// - A note that is open in a tab focuses that tab, whatever `inNewTab` says.
    /// - Otherwise, with `inNewTab`, it opens in a new tab right after the active one.
    /// - Otherwise it replaces the note in the active tab, and the note that was there is discarded when it was never
    ///   used.
    ///
    /// The cursor stays where it is: a click in the sidebar must not take the sidebar's keyboard focus away.
    func open(_ id: NoteID, inNewTab: Bool) {
        guard let list = tabs, current != nil else { return }
        if let existing = list.index(of: id) {
            if existing == list.activeIndex {
                // Nothing to show. A click may have moved the sidebar's highlight (⌘-click toggles it): put it back.
                renderSidebar()
            } else {
                switchToTab(existing, focusingEditor: false)
            }
            return
        }

        // The performance tests measure this interval: from the click until the note is on screen.
        Signposts.beginEditorInterval("switch-note")
        guard let note = loadNote(id) else { return }
        leaveCurrentNote(discardingIfUntouched: !inNewTab)
        guard var updated = tabs else { return }
        if case .replaced(_, let previous) = updated.open(id, inNewTab: inNewTab) {
            tabItems[previous] = nil
        }
        tabs = updated
        showActive(note)
        tabsDidChange()
        noteList.refresh()
    }

    // MARK: Switching tabs

    /// Shows the tab at `index` and puts the cursor in its note (a click on the tab).
    func selectTab(at index: Int) {
        switchToTab(index, focusingEditor: true)
    }

    /// ⌃Tab: the tab to the right, or the first tab after the last.
    func selectNextTab() {
        guard var list = tabs else { return }
        list.selectNext()
        selectTab(at: list.activeIndex)
    }

    /// ⌃⇧Tab: the tab to the left, or the last tab before the first.
    func selectPreviousTab() {
        guard var list = tabs else { return }
        list.selectPrevious()
        selectTab(at: list.activeIndex)
    }

    /// ⌘1 to ⌘9: tab 1 to 8, or the last tab for 9 (`TabList.select(number:)`).
    func selectTab(number: Int) {
        guard var list = tabs else { return }
        list.select(number: number)
        selectTab(at: list.activeIndex)
    }

    /// Makes the tab at `index` the active one. The note being left is saved first. Every tab stays open, so an empty
    /// note that was never used stays too.
    private func switchToTab(_ index: Int, focusingEditor: Bool) {
        guard let list = tabs, current != nil, list.tabs.indices.contains(index), index != list.activeIndex else {
            return
        }
        // Selecting a tab is the same interval as opening a note: from the click until the note is on screen.
        Signposts.beginEditorInterval("switch-note")
        guard let next = loadNote(list.tabs[index].noteID) else { return }
        leaveCurrentNote(discardingIfUntouched: false)
        tabs?.select(index)
        showActive(next)
        tabsDidChange()
        if focusingEditor { editor.focus() }
    }

    // MARK: Closing tabs

    /// ⌘W.
    func closeActiveTab() {
        guard let list = tabs else { return }
        closeTab(at: list.activeIndex)
    }

    /// Closes the tab at `index`. The note stays in the list: a tab is a view onto a note, and only a note that was
    /// never used is discarded with its tab (spec §6.3). Closing the only tab leaves a tab with a new empty note.
    func closeTab(at index: Int) {
        guard let list = tabs, current != nil, list.tabs.indices.contains(index) else { return }
        if list.tabs.count == 1 {
            closeOnlyTab()
        } else if index == list.activeIndex {
            closeActiveTabOfSeveral()
        } else {
            closeOtherTab(at: index)
        }
    }

    /// Closes the active tab while others are open: the tab that takes its place is shown.
    private func closeActiveTabOfSeveral() {
        guard var list = tabs else { return }
        guard case .closed(let closedID) = list.close(at: list.activeIndex) else { return }
        // Closing a tab shows another note: the interval of opening one.
        Signposts.beginEditorInterval("switch-note")
        guard let next = loadNote(list.active.noteID) else { return }
        leaveCurrentNote(discardingIfUntouched: true)
        tabs = list
        tabItems[closedID] = nil
        showActive(next)
        tabsDidChange()
        noteList.refresh()
        editor.focus()
    }

    /// Closes a tab that is not active. The note in the editor does not change.
    private func closeOtherTab(at index: Int) {
        guard var list = tabs else { return }
        guard case .closed(let closedID) = list.close(at: index) else { return }
        tabs = list
        tabItems[closedID] = nil
        discardIfUnused(closedID)
        tabsDidChange()
        noteList.refresh()
    }

    /// Closes the only tab: there is always one, so it gets a new empty note. When its note is such a note already,
    /// nothing is left to replace.
    private func closeOnlyTab() {
        guard let leaving = current, let list = tabs else { return }
        if isUntouched(leaving) {
            editor.focus()
            return
        }
        let note: Note
        do {
            note = try storage.notes.create(now: Date())
        } catch {
            report("cannot create a note: \(error)")
            return
        }
        untouchedNoteIDs.insert(note.id)

        leaveCurrentNote(discardingIfUntouched: true)
        guard var updated = tabs else { return }
        updated.replaceNote(at: updated.activeIndex, with: note.id)
        tabs = updated
        tabItems[list.active.noteID] = nil
        showActive(note)
        tabsDidChange()
        noteList.refresh()
        editor.focus()
    }

    // MARK: Changing the active note

    /// Reads the note `id` from the storage for showing. Nil, and a new read of the note list, when it is gone or
    /// deleted: the list was stale.
    private func loadNote(_ id: NoteID) -> Note? {
        do {
            guard let note = try storage.notes.note(id), note.deletedAt == nil else {
                noteList.refresh()
                return nil
            }
            return note
        } catch {
            report("cannot open note \(id.rawValue): \(error)")
            return nil
        }
    }

    /// Leaves the note in the editor: writes everything that is unsaved, including the session with the cursor and
    /// scroll position of its tab, and returns when it is on disk. With `discardingIfUntouched`, a note nobody used is
    /// discarded instead: its tab is going away.
    ///
    /// It does not change `current`. The caller sets it, and shows the next note.
    private func leaveCurrentNote(discardingIfUntouched: Bool) {
        guard let leaving = current else { return }
        let discardsLeaving = discardingIfUntouched && isUntouched(leaving)
        // An untouched note is not worth a write. Its row goes below.
        if discardsLeaving { currentIsDirty = false }
        // After this every write for the leaving note is done.
        persistNow()
        if discardsLeaving { discard(leaving) }
    }

    /// Makes `note` the note of the active tab, which `tabs` already says, and shows it with that tab's cursor and
    /// scroll position.
    private func showActive(_ note: Note) {
        guard let list = tabs else { return }
        current = note
        currentIsDirty = false
        tabItems[note.id] = Self.item(for: note)
        show(note, tab: list.active)
    }

    /// Shows `note` in the editor with its own undo history, which switching notes never clears.
    private func show(_ note: Note, tab: TabState) {
        editor.show(note, tab: tab, undoManager: undoManager(for: note.id), isReadOnly: false)
    }

    /// What follows every change of the tabs: the strip and the sidebar show them, and the session is written at once.
    private func tabsDidChange() {
        renderTabs()
        renderSidebar()
        updatePinState()
        writeSessionNow()
    }

    /// The undo manager of the note `id`, made when the note is first shown.
    private func undoManager(for id: NoteID) -> UndoManager {
        if let existing = undoManagers[id] { return existing }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }

    /// True for the note in the editor when nobody has used it: it is new (or was restored empty) and is still empty.
    private func isUntouched(_ note: Note) -> Bool {
        note.isEmpty && untouchedNoteIDs.contains(note.id)
    }

    /// Discards the note `id` of a tab that was closed, when it is an empty note that nobody used. The note was saved
    /// when its tab was left, so the storage has its text.
    private func discardIfUnused(_ id: NoteID) {
        guard untouchedNoteIDs.contains(id) else { return }
        do {
            if let note = try storage.notes.note(id), note.isEmpty { discard(note) }
        } catch {
            report("cannot read note \(id.rawValue): \(error)")
        }
    }

    /// Deletes the row of a note that was never used. Needs an idle storage queue, so call it after `persistNow()`.
    private func discard(_ note: Note) {
        untouchedNoteIDs.remove(note.id)
        undoManagers[note.id] = nil
        tabItems[note.id] = nil
        latestLive.removeAll { $0.id == note.id }
        noteList.forget(note.id)
        do {
            try storage.notes.discard(note.id)
        } catch {
            report("cannot discard the empty note \(note.id.rawValue): \(error)")
        }
    }

    // MARK: Saving

    /// Writes everything that is unsaved, and returns when it is on disk. For quitting, deactivating and changing the
    /// active tab. Call it on the main thread only, and never from a block that runs on the storage queue.
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

    /// Records where the cursor is and how far the active tab is scrolled, in the tab list.
    private func recordViewState() {
        guard var list = tabs else { return }
        list.updateViewState(
            at: list.activeIndex, selection: editor.currentSelection, scrollAnchor: editor.currentScrollAnchor)
        tabs = list
    }

    /// The autosaver's save: captures what is unsaved on the main thread, then writes it on the storage queue. A
    /// changed note is followed by a read of the note list (`NoteListModel.refresh`).
    private func saveNow() {
        guard tabs != nil, let note = current else { return }
        let unsavedNote = currentIsDirty ? note : nil
        currentIsDirty = false
        recordViewState()
        guard let session = tabs?.session(fontSize: fontSize) else { return }

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
            }
        }
        // A changed note is followed by a read of the list, which the storage queue runs after the write above: its
        // title, preview and place in the list changed.
        if unsavedNote != nil { noteList.refresh() }
    }

    /// Hands the session to the storage queue at once, after a change of the tabs, instead of waiting for the
    /// autosaver: a crash right after the change must keep the tabs. It does not wait for the write, and it leaves the
    /// text of the active note to the autosaver, whose write goes to the same queue after it.
    private func writeSessionNow() {
        guard let session = tabs?.session(fontSize: fontSize) else { return }
        let storage = self.storage
        storageQueue.async { [storage] in
            do {
                try storage.session.save(session)
            } catch {
                report("cannot save the session: \(error)")
            }
        }
    }

    /// A write failed. The text is still in the editor, so keep it marked as unsaved and try again.
    private func saveFailed(_ note: Note?) {
        if let note, note.id == current?.id { currentIsDirty = true }
        autosaver.markDirty()
    }

    // MARK: Pinning

    /// Pins the note `id`, or unpins it when it is pinned (a row's context menu). The pin is stored as it is in the
    /// storage and not as the list shows it, and only the pin changes: the text, the edit time and any typing that is
    /// not saved yet are left alone (`NoteStore.save` never writes the pin, Plan 2 "Review Focus" 1).
    func togglePin(_ id: NoteID) {
        let storage = self.storage
        storageQueue.async { [storage] in
            do {
                let isPinned = try storage.notes.note(id)?.pinnedAt != nil
                try storage.notes.setPinned(id, !isPinned, now: Date())
            } catch {
                report("cannot pin note \(id.rawValue): \(error)")
            }
        }
        // The read goes to the storage queue after the write above.
        noteList.refresh()
    }

    /// ⇧⌘P and the toolbar's pin button: pins the note of the active tab, or unpins it.
    func togglePinOfActiveNote() {
        guard let note = current else { return }
        togglePin(note.id)
    }

    /// Whether the note of the active tab is pinned, as the note list last read it, and whether it can be pinned.
    private func updatePinState() {
        guard let note = current else { return }
        let isPinned = latestLive.first { $0.id == note.id }?.pinnedAt != nil
        onActiveNotePinChange?(isPinned, note.deletedAt == nil)
    }

    // MARK: The note list and the tab titles

    /// Reads the note list again when the app becomes active, so that the day groups and the time labels are those of
    /// today after a long time away. Every autosave reads the list too, so only a read that is older than half a minute
    /// is worth another (and none is right after the launch's own).
    func refreshNoteList() {
        noteList.refresh(ifOlderThan: 30)
    }

    /// The note list was read. The tab titles of the open notes follow it, and so does the pin of the active note, and
    /// the list is told which notes it must not show before it shows what was read.
    private func didReadLiveSummaries(_ summaries: [NoteSummary]) {
        latestLive = summaries
        if let list = tabs {
            let open = Set(list.tabs.map(\.noteID))
            for summary in summaries where open.contains(summary.id) {
                tabItems[summary.id] = Self.item(for: summary)
            }
            renderTabs()
        }
        updateNoteListState()
        updatePinState()
    }

    /// Shows the note list with the current note highlighted. A new note that nobody has used yet is not listed (spec
    /// §6.3: it never appears in the list unless it gets text). The note in the editor counts as empty when its text
    /// is, and a note in another tab when its saved row is.
    private func renderSidebar() {
        updateNoteListState()
        noteList.render()
    }

    /// Tells the note list which note is open and which notes are not to be listed, without showing it.
    private func updateNoteListState() {
        let currentID = current?.id
        noteList.selectedNoteID = currentID
        noteList.hiddenNoteID = current.flatMap { isUntouched($0) ? $0.id : nil }
        noteList.hiddenWhileEmptyNoteIDs = untouchedNoteIDs.filter { $0 != currentID }
    }

    /// Shows the open tabs in the tab strip.
    private func renderTabs() {
        guard let list = tabs else { return }
        let untitled = TabStripItem(title: "Untitled", hasTitle: false, isDeleted: false)
        tabStrip.show(list.tabs.map { tabItems[$0.noteID] ?? untitled }, activeIndex: list.activeIndex)
    }

    /// The tab strip's item for a note that is loaded.
    private static func item(for note: Note) -> TabStripItem {
        let title = note.displayTitle
        return TabStripItem(
            title: title.isEmpty ? "Untitled" : title, hasTitle: note.hasTitle, isDeleted: note.deletedAt != nil)
    }

    /// The tab strip's item for a row of the note list, which shows the same title as the row.
    private static func item(for summary: NoteSummary) -> TabStripItem {
        TabStripItem(
            title: summary.displayTitle.isEmpty ? "Untitled" : summary.displayTitle, hasTitle: summary.hasTitle,
            isDeleted: summary.deletedAt != nil)
    }
}

/// Storage errors have nowhere to go in a window that never asks anything, so they go to the standard error stream.
private nonisolated func report(_ message: String) {
    FileHandle.standardError.write(Data("Scratch: \(message)\n".utf8))
}
