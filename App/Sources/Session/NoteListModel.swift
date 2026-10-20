import AppKit
import ScratchCore

/// The data behind the sidebar (spec §6.2): it reads the note list from the storage, filters it by what the owner typed
/// in the search field, groups it into Pinned, Today, Yesterday, Earlier and Recently Deleted, and shows the sections
/// in the sidebar. `SessionCoordinator` owns it, tells it which note is open and which notes are not to be listed, and
/// asks it to read again after every change of a note.
///
/// **Threading.** The class is `@MainActor`. The reads run on the coordinator's storage queue, after every write that
/// is already queued, so a read after a write sees it. Each read has a number, and a result is shown only when no newer
/// read was asked for since, so a slow, stale list never replaces a newer one.
///
/// **Time.** The groups and the time labels are recomputed with `Date()` and the current calendar every time the list
/// is shown, so a note edited yesterday moves from Today to Yesterday at midnight (`AppDelegate` asks for a new read
/// when the app becomes active).
@MainActor
final class NoteListModel {
    private let storage: ScratchStorage
    private let storageQueue: DispatchQueue
    private let sidebar: SidebarViewController

    /// Called with every live note's row after each read, before the sidebar shows it, whatever the search field says.
    /// The coordinator updates the tab titles and the pin button from it, and what it hides (`hiddenNoteID`).
    var onLiveSummaries: (([NoteSummary]) -> Void)?

    /// The note of the active tab while nobody has used it: a new note with no text is not listed (spec §6.3).
    var hiddenNoteID: NoteID?
    /// Notes that nobody has used and that are open in another tab. Each is not listed while its saved row is empty.
    var hiddenWhileEmptyNoteIDs: Set<NoteID> = []
    /// The note of the active tab, whose row is highlighted.
    var selectedNoteID: NoteID?
    /// Whether the rows of Recently Deleted are shown under its header. It is not saved: the section starts collapsed
    /// at every launch [call].
    private(set) var recentlyDeletedExpanded = false

    /// What the search field holds.
    private var searchText = ""
    /// Numbers the reads: the result of read `n` is shown only while `n` is the latest.
    private var request = 0
    /// When the last read was asked for.
    private var lastRefresh = Date.distantPast

    /// Every live note, as of the last read.
    private var live: [NoteSummary] = []
    /// The notes that match `searchText`, as of the last read. Nil while the list is not filtered.
    private var results: [NoteSummary]?
    /// The notes in Recently Deleted, as of the last read.
    private var deleted: [NoteSummary] = []

    init(storage: ScratchStorage, storageQueue: DispatchQueue, sidebar: SidebarViewController) {
        self.storage = storage
        self.storageQueue = storageQueue
        self.sidebar = sidebar
    }

    // MARK: Reading

    /// Reads the note list again: every live note, the notes that match the search text while there is one, and the
    /// notes in Recently Deleted (not while searching, because a search does not show them). Shows the result when it
    /// arrives, unless a newer read was asked for.
    func refresh() {
        request += 1
        lastRefresh = Date()
        let request = self.request
        let text = searchText
        let searching = SearchQuery.ftsExpression(text) != nil
        let storage = self.storage
        storageQueue.async { [weak self, storage] in
            let notes = storage.notes
            guard let all = try? notes.summaries() else { return }
            var found: [NoteSummary]?
            var removed: [NoteSummary]?
            if searching {
                guard let matches = try? notes.search(text) else { return }
                found = matches
            } else {
                removed = try? notes.deletedSummaries()
            }
            let results = found
            let deleted = removed
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.didRead(all: all, results: results, deleted: deleted, request: request)
                }
            }
        }
    }

    /// Reads the note list again unless a read was asked for less than `age` seconds ago. For the app becoming active:
    /// it does so at every launch too, right after the read that the restore asked for, and a second read and a second
    /// reload of the rows would only delay the first frames.
    func refresh(ifOlderThan age: TimeInterval) {
        guard Date().timeIntervalSince(lastRefresh) >= age else { return }
        refresh()
    }

    /// The search field changed. An empty text, or one with no word in it (`SearchQuery`), shows the whole list.
    func setSearchText(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        refresh()
    }

    private func didRead(all: [NoteSummary], results: [NoteSummary]?, deleted: [NoteSummary]?, request: Int) {
        guard request == self.request else { return }
        live = all
        self.results = results
        if let deleted { self.deleted = deleted }
        onLiveSummaries?(all)
        render()
    }

    /// The owner clicked the header of Recently Deleted: shows its rows when they are hidden, and hides them when they
    /// are shown. It needs no read.
    func toggleRecentlyDeleted() {
        recentlyDeletedExpanded.toggle()
        render()
    }

    /// Takes the row of the note `id` out of what is shown, until the next read. For a note that was just discarded,
    /// deleted or removed for good.
    func forget(_ id: NoteID) {
        live.removeAll { $0.id == id }
        results?.removeAll { $0.id == id }
        deleted.removeAll { $0.id == id }
    }

    // MARK: Showing

    /// Shows what the last read found, with the current hidden notes and selection. Needs no read: the coordinator calls
    /// it after the active tab or what is hidden changed.
    func render() {
        let now = Date()
        let isSearching = results != nil
        let shown = (results ?? live).filter { !isHidden($0) }
        // While searching, the sections are the results and nothing else: no Recently Deleted.
        let sections = SidebarSections.make(
            live: shown, deleted: isSearching ? [] : deleted, now: now, calendar: .current)
        sidebar.reload(
            sections, selecting: selectedNoteID, recentlyDeletedExpanded: recentlyDeletedExpanded, now: now)
    }

    /// True for the row of a note that is not listed yet: the note of the active tab while it is new and empty, and a
    /// new note in another tab while its saved row is empty.
    private func isHidden(_ summary: NoteSummary) -> Bool {
        if summary.id == hiddenNoteID { return true }
        return hiddenWhileEmptyNoteIDs.contains(summary.id) && !summary.hasTitle && summary.displayTitle.isEmpty
    }
}
