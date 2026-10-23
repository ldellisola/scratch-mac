import AppKit
import ScratchCore

/// Connects the editor, the tab strip, the sidebar and the storage: it decides which notes are open in which tabs and
/// which tab is active, keeps the active note's text and the session saved, pins, deletes and restores notes, and keeps
/// the sidebar list and the tab titles current. The editor, the tab strip and the sidebar only report what the user did.
/// The sidebar's data (the reads, the search, the groups) is `NoteListModel`'s.
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
///
/// **Failed writes.** A write that fails never costs text. The note that was being written goes into `unsavedNotes`
/// (the storage queue reports it there, so it is known when `persistNow()` returns, and not a turn of the main queue
/// later), every save writes those notes again before the note of the active tab, and a note that is shown again is
/// shown from there and not from the storage, whose copy is older.
///
/// **Deleted notes.** Deleting a note moves it to Recently Deleted (`NoteStore.delete`) and closes its tab (spec §6.7).
/// A note in Recently Deleted opens like any other, in the active tab, and the editor shows it read-only: that is the
/// only way a tab holds a deleted note, so the tab list never does after a launch (`restoredTabs` drops such tabs).
/// Restoring a note that is open makes it editable in place. Thirty days after its deletion a note is purged
/// (`purgeExpiredNotes`), and its tab, if it has one, closes. The writes of deleting, restoring and deleting for good run
/// on the main thread, after `persistNow()` has emptied the storage queue: they are one statement each, the owner just
/// asked for them, and a tab only closes when the write worked. The purge runs on the storage queue.
///
/// **Attachments.** The coordinator is the editor's `AttachmentImporting`: a file that is pasted, dropped or chosen is
/// registered on the main thread (`AttachmentImporter`) and copied on the storage queue, so `persistNow()` and quitting wait
/// for the copy, and a copy never runs beside the purge or the sweep. The sweep at launch (`sweepUnreferencedAttachments`)
/// removes the rows and files that no stored note names and that are more than a day old.
@MainActor
final class SessionCoordinator: AttachmentImporting {
    private let storage: ScratchStorage
    private let editor: EditorViewController
    private let tabStrip: TabStripViewController
    private let storageQueue: DispatchQueue
    /// The sidebar's data: it reads the note list on `storageQueue` and shows it.
    private let noteList: NoteListModel
    /// Calls `saveNow()` 300 ms after the last change and at most 1 s after the first one. Set at the end of `init`.
    private var autosaver: Autosaver!
    /// Makes the attachments of what is pasted, dropped or chosen: the row at once, the copy on `storageQueue`.
    private let attachmentImporter: AttachmentImporter

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
    /// Notes that nobody has used yet: created in this session, or restored empty with the edit time they were created
    /// with. Leaving one of them while it is still empty discards it (spec §6.3). The first edit of a note takes it out
    /// for good, also when the owner empties it again (docs/decisions/0004).
    private var untouchedNoteIDs: Set<NoteID> = []
    /// The notes whose last write failed, with the owner's text: written again by every save, shown again from here.
    private let unsavedNotes = UnsavedNotes()
    /// What the tab strip shows for each open tab. It comes from the note when the note is shown, and from the note
    /// list after each save, so a tab title follows an edit about as fast as the sidebar row does.
    private var tabItems: [NoteID: TabStripItem] = [:]

    /// When Recently Deleted was last purged, which a purge at most once an hour follows (`purgeExpiredNotes`).
    private var lastPurge: Date?
    /// How long after a purge the next one may run: the app becoming active asks for one each time.
    private static let purgeInterval: TimeInterval = 60 * 60

    /// The notes that were open in tabs when the session was restored, whose texts `warmUpHighlighting()` reads (on the
    /// storage queue) and hands to the highlighter once the first frame is out, and then forgets.
    private var warmUpNoteIDs: [NoteID] = []

    /// How many notes `restore()` read in full: the note of the active tab, and no other (spec §7: before the first frame a
    /// launch reads one body). Zero when the launch started a new note. A test reads it.
    private(set) var notesReadAtRestore = 0

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
        self.attachmentImporter = AttachmentImporter(
            store: storage.attachments, queue: queue, catalog: editor.attachmentCatalog)

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
        sidebar.onDelete = { [weak self] id in self?.deleteNote(id) }
        sidebar.onRestore = { [weak self] id in self?.restoreNote(id) }
        sidebar.onDeletePermanently = { [weak self] id in self?.deleteNotePermanently(id) }
        sidebar.onToggleRecentlyDeleted = { [weak self] in self?.noteList.toggleRecentlyDeleted() }
        noteList.onLiveSummaries = { [weak self] summaries in self?.didReadLiveSummaries(summaries) }
        tabStrip.onSelect = { [weak self] index in self?.selectTab(at: index) }
        tabStrip.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabStrip.onNewTab = { [weak self] in self?.newNoteInNewTab() }
        editor.attachmentImporter = self
    }

    // MARK: Attachments

    /// How old an attachment must be before the launch sweep may remove it when no stored note names it: a file whose token
    /// is in text that was never saved (a crash within the second of autosave) is kept for a day, so that nothing the owner
    /// can still get back is taken (plan 5, "Never lose an attachment").
    static let attachmentSweepAge: TimeInterval = 24 * 60 * 60

    /// The editor pasted, dropped or chose `sources` for the note `noteID`: each is registered and copied
    /// (`AttachmentImporter`), and the ids come back in order for the editor to put their tokens in the text.
    func importAttachments(_ sources: [AttachmentSource], into noteID: NoteID) -> [AttachmentID] {
        attachmentImporter.importAttachments(sources, into: noteID)
    }

    /// The launch sweep: on the storage queue, after the purge that was asked for before it, removes the rows and files of the
    /// attachments created more than a day before `now` that no stored note, in Recently Deleted too, names
    /// (`AttachmentStore.sweep`). A file that something names is never removed.
    func sweepUnreferencedAttachments(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.attachmentSweepAge)
        let storage = self.storage
        storageQueue.async { [storage] in
            do {
                try storage.attachments.sweep(createdBefore: cutoff, notes: storage.notes)
            } catch {
                report("cannot sweep the attachments: \(error)")
            }
        }
    }

    // MARK: Warming up

    /// Has the highlight queue compile the queries of the languages that the fences of the notes in the open tabs name, so
    /// that the first block in such a language, in the note that is shown or in one that a tab switch shows, is coloured
    /// without waiting for its query (plan 5 task 7). `AppDelegate` calls it once the first frame is out. The notes' texts are
    /// read on the storage queue, which is what the launch no longer does before the first frame (plan 6 task 3), the
    /// fences are looked for on the highlight queue and the queries are compiled there (`CodeBlockStyler.warmUp`). A second
    /// call has nothing to do.
    func warmUpHighlighting() {
        let ids = warmUpNoteIDs
        warmUpNoteIDs = []
        guard !ids.isEmpty else { return }
        let storage = self.storage
        editor.textView.styler.codeBlockStyler.warmUp(
            languagesInTextsFrom: { ids.compactMap { (try? storage.notes.note($0))?.body } }, on: storageQueue)
    }

    // MARK: Restoring

    /// Shows the tabs of the saved session, with the active note, its cursor and scroll position, and starts loading
    /// the note list. Without a usable session it starts one tab with a new empty note. Before the window shows, the body of
    /// the active note is read and no other (spec §7): the other tabs get their title and the rest from one query that reads
    /// no body (`NoteStore.tabInfo`), and the list loads on the storage queue.
    func restore() {
        let (list, note) = restoredTabs()
        tabs = list
        current = note
        // The active note was read in full, so whether nobody ever used it is known from its own text.
        untouchedNoteIDs.remove(note.id)
        if Self.isNeverUsed(note) { untouchedNoteIDs.insert(note.id) }
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
    /// Only the note of the active tab is read in full (`notesReadAtRestore`). What a tab needs of any other note, its title,
    /// whether it is deleted and whether nobody ever used it, comes from `NoteStore.tabInfo`, which reads no body. The
    /// tab strip's items and the set of untouched notes of the other tabs are filled in here from it.
    ///
    /// When the storage cannot be read at all, the owner still gets an editor: it holds a new note that stays unsaved,
    /// and every save tries again.
    private func restoredTabs() -> (list: TabList, note: Note) {
        do {
            if let state = try storage.session.load() {
                fontSize = state.fontSize
                let infos = try storage.notes.tabInfo(state.tabs.map(\.noteID))
                var kept: [TabState] = []
                var keptItems: [NoteID: TabStripItem] = [:]
                var keptUntouched: Set<NoteID> = []
                var activeKept: Int?
                for (index, tab) in state.tabs.enumerated() where keptItems[tab.noteID] == nil {
                    guard let info = infos[tab.noteID], info.deletedAt == nil else { continue }
                    if index == state.activeTabIndex { activeKept = kept.count }
                    kept.append(tab)
                    keptItems[tab.noteID] = Self.item(for: info)
                    if info.isNeverUsed { keptUntouched.insert(tab.noteID) }
                }
                if !kept.isEmpty {
                    let list = TabList(tabs: kept, activeIndex: activeKept ?? 0)
                    notesReadAtRestore += 1
                    if let active = try storage.notes.note(list.active.noteID), active.deletedAt == nil {
                        tabItems = keptItems
                        untouchedNoteIDs = keptUntouched
                        // Their fences say which queries to compile, once the first frame is out.
                        warmUpNoteIDs = kept.map(\.noteID)
                        return (list, active)
                    }
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
    /// A note in Recently Deleted opens the same way, and the editor shows it read-only.
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
    ///
    /// The cursor goes into the note that is shown after the tab closed, unless `focusingEditor` is false: deleting a
    /// note from the sidebar leaves the keyboard where it is, so that ⌘⌫ in the sidebar cannot become ⌘⌫ in a note.
    func closeTab(at index: Int, focusingEditor: Bool = true) {
        guard let list = tabs, current != nil, list.tabs.indices.contains(index) else { return }
        if list.tabs.count == 1 {
            closeOnlyTab(focusingEditor: focusingEditor)
        } else if index == list.activeIndex {
            closeActiveTabOfSeveral(focusingEditor: focusingEditor)
        } else {
            closeOtherTab(at: index)
        }
    }

    /// Closes the active tab while others are open: the tab that takes its place is shown.
    private func closeActiveTabOfSeveral(focusingEditor: Bool) {
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
        if focusingEditor { editor.focus() }
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
    private func closeOnlyTab(focusingEditor: Bool) {
        guard let leaving = current, let list = tabs else { return }
        if isUntouched(leaving) {
            if focusingEditor { editor.focus() }
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
        if focusingEditor { editor.focus() }
    }

    // MARK: Changing the active note

    /// Reads the note `id` from the storage for showing, also when it is in Recently Deleted (the editor shows it
    /// read-only). Nil, and a new read of the note list, when it is gone: the list was stale.
    ///
    /// A note whose last write failed is shown as the owner left it: its title, text and edit time come from
    /// `unsavedNotes`, and the rest (the pin, the deletion) from the storage, which a save never writes. The undo
    /// history of the note holds ranges of the text it was left with, so showing the older stored text would break it.
    private func loadNote(_ id: NoteID) -> Note? {
        do {
            guard var note = try storage.notes.note(id) else {
                noteList.refresh()
                return nil
            }
            if let unsaved = unsavedNotes.note(id) {
                note.title = unsaved.title
                note.body = unsaved.body
                note.modifiedAt = unsaved.modifiedAt
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

    /// Shows `note` in the editor with its own undo history, which switching notes never clears. A note in Recently
    /// Deleted is read-only (spec §6.2).
    private func show(_ note: Note, tab: TabState) {
        editor.show(note, tab: tab, undoManager: undoManager(for: note.id), isReadOnly: note.deletedAt != nil)
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

    /// True for a stored note that nobody ever typed in: it is empty, and its edit time is still its creation time
    /// (`NoteStore.create` sets both to one date, and every save of typed text changes the edit time). A note that
    /// the owner emptied is empty too, and is not this: it is theirs, and it is kept (docs/decisions/0004).
    private static func isNeverUsed(_ note: Note) -> Bool {
        note.isEmpty && note.modifiedAt == note.createdAt
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
        unsavedNotes.forget(note.id)
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
        noteWasEdited(note.id)
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
        noteWasEdited(note.id)
        currentIsDirty = true
        autosaver.markDirty()
    }

    /// The owner edited the note `id`, in its text or its title. From the first edit on it is theirs, even if they empty
    /// it again: it is no longer an untouched note, so closing its tab or replacing it in its tab keeps it, and a
    /// relaunch finds it with an edit time that is not its creation time (docs/decisions/0004).
    private func noteWasEdited(_ id: NoteID) {
        untouchedNoteIDs.remove(id)
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

    /// The autosaver's save: captures what is unsaved on the main thread, then writes it on the storage queue. The notes
    /// whose last write failed go first, then the note of the active tab when it has edits, and the session after them.
    /// Each note is a write of its own: one that fails is reported to `unsavedNotes` and does not keep the others from
    /// being written. A changed note is followed by a read of the note list (`NoteListModel.refresh`).
    private func saveNow() {
        guard tabs != nil, let note = current else { return }
        var writes = unsavedNotes.all
        if currentIsDirty {
            // The text in the editor is newer than any copy of this note that failed, and replaces it.
            writes.removeAll { $0.id == note.id }
            writes.append(note)
        }
        currentIsDirty = false
        recordViewState()
        guard let session = tabs?.session(fontSize: fontSize) else { return }

        let storage = self.storage
        let unsavedNotes = self.unsavedNotes
        storageQueue.async { [weak self, storage, unsavedNotes, writes] in
            var failed = false
            for toSave in writes {
                do {
                    try storage.notes.save(toSave)
                    unsavedNotes.writeSucceeded(toSave)
                } catch {
                    report("cannot save note \(toSave.id.rawValue): \(error)")
                    unsavedNotes.writeFailed(toSave)
                    failed = true
                }
            }
            do {
                try storage.session.save(session)
            } catch {
                report("cannot save the session: \(error)")
                failed = true
            }
            if failed {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.saveFailed() }
                }
            }
        }
        // A changed note is followed by a read of the list, which the storage queue runs after the writes above: its
        // title, preview and place in the list changed.
        if !writes.isEmpty { noteList.refresh() }
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

    /// A write failed. The notes that failed are in `unsavedNotes` already, so this only asks for another save.
    private func saveFailed() {
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
        // A deleted note cannot be pinned (the button and the menu item are off for it too).
        guard let note = current, note.deletedAt == nil else { return }
        togglePin(note.id)
    }

    /// Whether the note of the active tab is pinned, as the note list last read it, and whether it can be pinned.
    private func updatePinState() {
        guard let note = current else { return }
        let isPinned = latestLive.first { $0.id == note.id }?.pinnedAt != nil
        onActiveNotePinChange?(isPinned, note.deletedAt == nil)
    }

    // MARK: Deleting and restoring

    /// Moves the note `id` to Recently Deleted (a row's context menu, or ⌘⌫ in the sidebar) and closes the tab that
    /// shows it (spec §6.7). When that was the only tab, it gets a new empty note.
    ///
    /// What is typed in the note and not saved yet is written first, so that the note goes to Recently Deleted with all
    /// its text. Only the deletion is stored, and `NoteStore.save` never changes it, so no later save of the note's
    /// text can bring it back. When the write fails, nothing else happens and the note stays where it is.
    func deleteNote(_ id: NoteID) {
        guard tabs != nil, current != nil else { return }
        persistNow()
        do {
            try storage.notes.delete(id, now: Date())
        } catch {
            report("cannot delete note \(id.rawValue): \(error)")
            return
        }
        // Not a note that nobody used any more: that would let closing its tab remove the row for good.
        untouchedNoteIDs.remove(id)
        noteList.forget(id)
        // The tabs are read after `persistNow()`, which records the cursor and scroll position in them.
        if let index = tabs?.index(of: id) {
            closeTab(at: index, focusingEditor: false)
        } else {
            noteList.refresh()
        }
    }

    /// Takes the note `id` out of Recently Deleted. A note that is open in a tab stays there and becomes editable at
    /// once, and its tab is no longer dimmed.
    func restoreNote(_ id: NoteID) {
        guard let list = tabs, current != nil else { return }
        do {
            try storage.notes.restore(id)
        } catch {
            report("cannot restore note \(id.rawValue): \(error)")
            return
        }
        if list.index(of: id) != nil, let item = tabItems[id] {
            tabItems[id] = TabStripItem(title: item.title, hasTitle: item.hasTitle, isDeleted: false)
        }
        if current?.id == id {
            current?.deletedAt = nil
            editor.setReadOnly(false)
        }
        renderTabs()
        updatePinState()
        noteList.refresh()
    }

    /// Removes the note `id` from Recently Deleted for good, after the sidebar asked the owner. A tab that shows it
    /// closes. Nothing happens to a note that is not deleted (`NoteStore.deletePermanently`). The files of its
    /// attachments go with it unless another note names them (`ScratchStorage.deletePermanently`, spec §6.4).
    func deleteNotePermanently(_ id: NoteID) {
        guard tabs != nil, current != nil else { return }
        persistNow()
        do {
            try storage.deletePermanently(id)
        } catch {
            report("cannot delete note \(id.rawValue) permanently: \(error)")
            return
        }
        didRemoveNotes([id])
    }

    /// Removes the notes of Recently Deleted that were deleted more than 30 days ago, and the files of their attachments
    /// that no other note names (`ScratchStorage.purge`, spec §6.2). It runs on the storage queue, at launch one
    /// main-queue turn after `restore()` and when the app becomes active, but not when the last purge was less than an
    /// hour ago. A purged note that is open in a tab closes the tab.
    func purgeExpiredNotes(now: Date) {
        if let last = lastPurge, now.timeIntervalSince(last) < Self.purgeInterval { return }
        lastPurge = now
        let cutoff = now.addingTimeInterval(-NoteStore.recentlyDeletedRetention)
        let storage = self.storage
        storageQueue.async { [weak self, storage] in
            do {
                guard try storage.purge(deletedBefore: cutoff) > 0 else { return }
            } catch {
                report("cannot purge Recently Deleted: \(error)")
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didPurge() }
            }
        }
    }

    /// Some notes were purged. The purge does not say which, so the open notes are looked up: a tab whose note is gone
    /// closes.
    private func didPurge() {
        guard let list = tabs else { return }
        didRemoveNotes(list.tabs.map(\.noteID).filter { !noteExists($0) })
    }

    /// The notes `ids` are gone from the storage. Forgets what the coordinator holds of them, closes their tabs and
    /// reads the note list again. The note of the active tab goes last: closing it shows the tab next to it, which must
    /// not be one that is gone too.
    private func didRemoveNotes(_ ids: [NoteID]) {
        var closedATab = false
        let activeID = current?.id
        for id in ids.filter({ $0 != activeID }) + ids.filter({ $0 == activeID }) {
            untouchedNoteIDs.remove(id)
            unsavedNotes.forget(id)
            undoManagers[id] = nil
            noteList.forget(id)
            // The indexes change with every close, so each tab is looked up again.
            if let index = tabs?.index(of: id) {
                closeTab(at: index, focusingEditor: false)
                closedATab = true
            }
        }
        if !closedATab { noteList.refresh() }
    }

    /// Whether the storage has the note `id`. A note that cannot be read counts as there, so that a read error never
    /// closes a tab.
    private func noteExists(_ id: NoteID) -> Bool {
        do {
            return try storage.notes.note(id) != nil
        } catch {
            return true
        }
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

    /// The tab strip's item for a note that `NoteStore.tabInfo` described: the note's text was not read.
    private static func item(for info: TabNoteInfo) -> TabStripItem {
        TabStripItem(
            title: info.displayTitle.isEmpty ? "Untitled" : info.displayTitle, hasTitle: info.hasTitle,
            isDeleted: info.deletedAt != nil)
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
