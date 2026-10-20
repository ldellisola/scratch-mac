import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/autosave-and-restore.md ("Write errors are not silent": a note whose write
/// failed is kept and written again, also when its tab was left) and docs/features/tabs.md (an emptied note is kept, only
/// a note nobody ever typed in is discarded, docs/decisions/0004). The coordinator runs on a real storage in a directory
/// of its own, and `PRAGMA query_only` makes every write fail the way a failing disk does: file permissions would not,
/// because SQLite keeps its file open.
@MainActor
final class SaveFailureTests: XCTestCase {
    /// A coordinator on its own storage, with the editor it drives. `first` is open in the only tab (or the first of
    /// several), `second` is stored and in no tab.
    @MainActor
    private struct Harness {
        let storage: ScratchStorage
        let coordinator: SessionCoordinator
        let editor: EditorViewController
        let window: NSWindow
        let directory: URL
        let first: Note
        let second: Note

        /// Types `text` at the cursor, as the owner does: through the text view, which tells the editor's delegate.
        func type(_ text: String) {
            editor.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }

        /// Makes every write of the storage fail with `SQLITE_READONLY`, reads still work.
        func failWrites() throws {
            try storage.database.execute("PRAGMA query_only = 1")
        }

        /// Makes the writes work again.
        func allowWrites() throws {
            try storage.database.execute("PRAGMA query_only = 0")
        }

        func cleanUp() {
            try? storage.database.execute("PRAGMA query_only = 0")
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Opens a storage with two notes, "alpha" and "beta", puts "alpha" in the first tab, then the notes of `moreTabs`
    /// in the tabs after it, and restores the session the way a launch does.
    private func makeHarness(moreTabs: [Note] = []) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchSaveFailureTests-\(UUID().uuidString)", isDirectory: true)
        let storage = try ScratchStorage.open(LaunchOptions(dataDirectory: directory, isIsolated: true))
        let earlier = Date(timeIntervalSinceNow: -3600)
        let first = Note(id: NoteID.make(), title: "", body: "alpha", createdAt: earlier, modifiedAt: earlier)
        let second = Note(id: NoteID.make(), title: "", body: "beta", createdAt: earlier, modifiedAt: earlier)
        try storage.notes.saveAll([first, second] + moreTabs)
        let tabs = ([first] + moreTabs).map { TabState(noteID: $0.id, selection: 0, scrollY: 0) }
        try storage.session.save(SessionState(tabs: tabs, activeTabIndex: 0))

        let editor = EditorViewController()
        let sidebar = SidebarViewController()
        let tabStrip = TabStripViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        _ = sidebar.view
        _ = tabStrip.view
        let coordinator = SessionCoordinator(storage: storage, editor: editor, sidebar: sidebar, tabStrip: tabStrip)
        coordinator.restore()
        return Harness(
            storage: storage, coordinator: coordinator, editor: editor, window: window, directory: directory,
            first: first, second: second)
    }

    // MARK: Failed saves

    /// Plan 3 task 7: typing in a note, then switching to another while the disk fails, must not lose the typing. The
    /// note that was left is written again by the next save.
    func testFailedSaveOfLeftNoteIsRetried() throws {
        let host = try makeHarness()
        defer { host.cleanUp() }
        host.type("one ")
        host.coordinator.persistNow()
        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, "one alpha", "the first save")

        try host.failWrites()
        host.type("two ")
        let typed = host.editor.currentText
        XCTAssertEqual(typed, "one two alpha")
        host.coordinator.open(host.second.id, inNewTab: false)
        XCTAssertEqual(host.editor.currentText, "beta", "the second note is shown")
        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, "one alpha", "the write failed")

        try host.allowWrites()
        host.coordinator.persistNow()

        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, typed)
        XCTAssertEqual(try host.storage.notes.note(host.second.id)?.body, "beta")
    }

    /// The same, when the failed write is the note's first: nothing of the typing is in the storage yet.
    func testFailedFirstSaveOfLeftNoteIsRetried() throws {
        let host = try makeHarness()
        defer { host.cleanUp() }
        try host.failWrites()
        host.type("typed while failing ")
        let typed = host.editor.currentText

        host.coordinator.open(host.second.id, inNewTab: false)
        try host.allowWrites()
        host.coordinator.persistNow()

        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, typed)
    }

    /// Plan 3 task 7: a note whose write failed is shown from what the owner typed, not from the older text in the
    /// storage, when they switch back to it. An undo step holds ranges of that text, so it has to be the same text.
    func testSwitchingBackShowsUnsavedText() throws {
        let host = try makeHarness()
        defer { host.cleanUp() }
        host.type("one ")
        try host.failWrites()
        host.type("two ")
        let typed = host.editor.currentText
        host.coordinator.open(host.second.id, inNewTab: false)
        XCTAssertEqual(host.editor.currentText, "beta")

        host.coordinator.open(host.first.id, inNewTab: false)

        XCTAssertEqual(host.editor.currentText, typed, "the note shows the text it was left with")
        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, "alpha", "nothing was written yet")
        XCTAssertEqual(host.editor.activeUndoManager?.canUndo, true, "the typing can still be undone")

        // The text that was only in memory is written once the disk works.
        try host.allowWrites()
        host.coordinator.persistNow()
        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, typed)
    }

    /// A note that is saved again while it is still open must not be written back from an older copy: the retry of the
    /// copy that failed and the save of the text typed after it end with the newest text.
    func testNewerTypingWinsOverAFailedOlderCopy() throws {
        let host = try makeHarness()
        defer { host.cleanUp() }
        try host.failWrites()
        host.type("first ")
        host.coordinator.persistNow()
        host.type("second ")
        let typed = host.editor.currentText

        try host.allowWrites()
        host.coordinator.persistNow()

        XCTAssertEqual(try host.storage.notes.note(host.first.id)?.body, typed)
    }

    // MARK: Emptied notes

    /// Plan 3 task 7, docs/decisions/0004: the first edit of a note makes it the owner's for good. A new note that is
    /// typed in and then emptied is kept when its tab closes, and a note nobody typed in is still discarded.
    func testTypedThenEmptiedNoteIsKeptWhenItsTabCloses() throws {
        let host = try makeHarness()
        defer { host.cleanUp() }
        let known = Set(try host.storage.notes.summaries().map(\.id))

        host.coordinator.newNoteInNewTab()
        let created = try XCTUnwrap(
            try host.storage.notes.summaries().map(\.id).first { !known.contains($0) }, "the new note")
        host.type("x")
        host.editor.textView.deleteBackward(nil)
        XCTAssertEqual(host.editor.currentText, "")
        host.coordinator.closeActiveTab()

        let kept = try host.storage.notes.note(created)
        XCTAssertNotNil(kept, "the emptied note is still stored")
        XCTAssertEqual(kept?.body, "")
        XCTAssertTrue(try host.storage.notes.summaries().contains { $0.id == created }, "and listed")
    }

    /// A note that nobody typed in is discarded with its tab, as before (spec §6.3).
    func testUntouchedNewNoteIsStillDiscardedWhenItsTabCloses() throws {
        let host = try makeHarness()
        defer { host.cleanUp() }
        let known = Set(try host.storage.notes.summaries().map(\.id))

        host.coordinator.newNoteInNewTab()
        let created = try XCTUnwrap(
            try host.storage.notes.summaries().map(\.id).first { !known.contains($0) }, "the new note")
        host.coordinator.closeActiveTab()

        XCTAssertNil(try host.storage.notes.note(created), "the untouched note is gone")
    }

    /// Plan 3 task 7: at a restore, an empty note counts as untouched only when its edit time is still its creation time.
    /// A note that was emptied (its edit time moved) is kept when its tab closes, and a note that was only created is
    /// discarded.
    func testRestoredEmptiedNoteIsKeptAndRestoredUntouchedNoteIsDiscarded() throws {
        let created = Date(timeIntervalSinceNow: -7200)
        let emptied = Note(
            id: NoteID.make(), title: "", body: "", createdAt: created, modifiedAt: created.addingTimeInterval(600))
        let untouched = Note(id: NoteID.make(), title: "", body: "", createdAt: created, modifiedAt: created)
        let host = try makeHarness(moreTabs: [emptied, untouched])
        defer { host.cleanUp() }

        host.coordinator.closeTab(at: 1, focusingEditor: false)
        host.coordinator.closeTab(at: 1, focusingEditor: false)

        XCTAssertNotNil(try host.storage.notes.note(emptied.id), "the emptied note is kept")
        XCTAssertNil(try host.storage.notes.note(untouched.id), "the note nobody typed in is discarded")
    }
}
