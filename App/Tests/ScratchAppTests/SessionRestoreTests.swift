import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/autosave-and-restore.md ("Launch") and plan 6, Review Focus 3: a launch reads the
/// body of the active tab's note before the first frame and no other (spec §7). The other tabs get their title, their
/// deletion and whether they were ever used from `NoteStore.tabInfo`, which reads no body, and every rule of the restore that
/// there was stays: a tab of a missing or deleted note is dropped, so is a second tab for one note, the active tab is the saved
/// one when it is kept, and a note nobody ever typed in is still untouched. The coordinator runs on a real storage in a
/// directory of its own.
@MainActor
final class SessionRestoreTests: XCTestCase {
    private struct Harness {
        let storage: ScratchStorage
        let coordinator: SessionCoordinator
        let editor: EditorViewController
        let tabStrip: TabStripViewController
        let window: NSWindow
        let directory: URL

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }

        /// The titles of the tabs as the strip shows them.
        var titles: [String] { tabStrip.shownItems.map(\.title) }

        /// The tabs of the session as `persistNow()` writes it, and the index of the active one.
        func savedTabs() throws -> (ids: [NoteID], activeIndex: Int) {
            coordinator.persistNow()
            let state = try XCTUnwrap(storage.session.load())
            return (state.tabs.map(\.noteID), state.activeTabIndex)
        }
    }

    private static let earlier = Date(timeIntervalSinceNow: -3600)

    private func note(_ body: String, title: String = "") -> Note {
        Note(id: NoteID.make(), title: title, body: body, createdAt: Self.earlier, modifiedAt: Self.earlier)
    }

    /// A note nobody ever typed in: empty, with its edit time equal to its creation time.
    private func neverUsedNote() -> Note {
        Note(id: NoteID.make(), title: "", body: "", createdAt: Self.earlier, modifiedAt: Self.earlier)
    }

    /// A storage with `notes` in it and a saved session of `tabs` (an unknown id is a tab of a note that is gone), with
    /// the tab at `activeIndex` active. The session is not restored yet: `restore` does it.
    private func makeStorage(notes: [Note], tabs: [NoteID], activeIndex: Int) throws -> (ScratchStorage, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchSessionRestoreTests-\(UUID().uuidString)", isDirectory: true)
        let storage = try ScratchStorage.open(LaunchOptions(dataDirectory: directory, isIsolated: true))
        try storage.notes.saveAll(notes)
        let states = tabs.map { TabState(noteID: $0, selection: 0, scrollY: 0) }
        try storage.session.save(SessionState(tabs: states, activeTabIndex: activeIndex))
        return (storage, directory)
    }

    /// A coordinator on `storage`, restored the way a launch does it.
    private func restore(_ storage: ScratchStorage, directory: URL) -> Harness {
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
            storage: storage, coordinator: coordinator, editor: editor, tabStrip: tabStrip, window: window,
            directory: directory)
    }

    // MARK: Which notes are read

    /// Review Focus 3: three tabs, one of them the 10,000 lines of the huge note. Whichever is active, the launch reads one
    /// full note, and every tab has its title.
    func testRestoreReadsTheBodyOfTheActiveNoteOnly() throws {
        let huge = note((1...10_000).map { "line \($0) of the huge note" }.joined(separator: "\n"))
        let small = note("alpha\nsecond line")
        let titled = note("a body", title: "Gamma")

        for active in 0..<3 {
            let (storage, directory) = try makeStorage(
                notes: [small, huge, titled], tabs: [small.id, huge.id, titled.id], activeIndex: active)
            let host = restore(storage, directory: directory)
            defer {
                host.cleanUp()
                withExtendedLifetime(host.window) {}
            }
            XCTAssertEqual(
                host.coordinator.notesReadAtRestore, 1, "the active note is the only one read (active tab \(active))")
            XCTAssertEqual(
                host.titles, ["alpha", "line 1 of the huge note", "Gamma"],
                "every tab has its title (active tab \(active))")
            XCTAssertEqual(
                host.tabStrip.shownItems.map(\.hasTitle), [false, false, true],
                "a typed title is a title (active tab \(active))")
            let shown = [small, huge, titled][active]
            XCTAssertEqual(
                host.editor.currentText, shown.body, "the editor shows the active note (active tab \(active))")
        }
    }

    /// With no saved session a launch creates one note, and reads nothing.
    func testRestoreWithoutASessionReadsNoNote() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchSessionRestoreTests-\(UUID().uuidString)", isDirectory: true)
        let storage = try ScratchStorage.open(LaunchOptions(dataDirectory: directory, isIsolated: true))
        let host = restore(storage, directory: directory)
        defer {
            host.cleanUp()
            withExtendedLifetime(host.window) {}
        }
        XCTAssertEqual(host.coordinator.notesReadAtRestore, 0)
        XCTAssertEqual(host.titles, ["Untitled"])
    }

    // MARK: The rules of the restore

    /// A tab whose note was deleted, a tab whose note is gone, and a second tab for one note are dropped, and the saved active
    /// tab stays the active one.
    func testRestoreDropsTabsOfDeletedNotes() throws {
        let first = note("first")
        let deleted = note("deleted")
        let last = note("last")
        let missing = NoteID.make()
        let (storage, directory) = try makeStorage(
            notes: [first, deleted, last], tabs: [first.id, deleted.id, missing, first.id, last.id], activeIndex: 4)
        try storage.notes.delete(deleted.id, now: Date())
        let host = restore(storage, directory: directory)
        defer {
            host.cleanUp()
            withExtendedLifetime(host.window) {}
        }

        XCTAssertEqual(host.titles, ["first", "last"])
        XCTAssertEqual(host.editor.currentText, "last", "the saved active tab is kept, and shown")
        let saved = try host.savedTabs()
        XCTAssertEqual(saved.ids, [first.id, last.id])
        XCTAssertEqual(saved.activeIndex, 1)
    }

    /// When the saved active tab is one that is dropped, the first tab that is left is active.
    func testRestoreWithADeletedActiveTabShowsTheFirstTabThatIsLeft() throws {
        let first = note("first")
        let deleted = note("deleted")
        let last = note("last")
        let (storage, directory) = try makeStorage(
            notes: [first, deleted, last], tabs: [deleted.id, first.id, last.id], activeIndex: 0)
        try storage.notes.delete(deleted.id, now: Date())
        let host = restore(storage, directory: directory)
        defer {
            host.cleanUp()
            withExtendedLifetime(host.window) {}
        }

        XCTAssertEqual(host.titles, ["first", "last"])
        XCTAssertEqual(host.editor.currentText, "first")
        XCTAssertEqual(host.coordinator.notesReadAtRestore, 1)
    }

    /// When no tab is left the launch starts one tab with a new empty note, as it always did.
    func testRestoreWithOnlyDeletedNotesStartsANewNote() throws {
        let deleted = note("deleted")
        let (storage, directory) = try makeStorage(notes: [deleted], tabs: [deleted.id, NoteID.make()], activeIndex: 0)
        try storage.notes.delete(deleted.id, now: Date())
        let host = restore(storage, directory: directory)
        defer {
            host.cleanUp()
            withExtendedLifetime(host.window) {}
        }

        XCTAssertEqual(host.titles, ["Untitled"])
        XCTAssertEqual(host.editor.currentText, "")
        let saved = try host.savedTabs()
        XCTAssertEqual(saved.ids.count, 1)
        XCTAssertNotEqual(saved.ids.first, deleted.id)
    }

    /// A note nobody ever typed in that is open in a tab other than the active one is untouched after the restore, as it was
    /// when the notes of all the tabs were read: closing its tab discards it. A note the owner emptied is kept.
    func testRestoreKeepsTheUntouchedNotesOfOtherTabsUntouched() throws {
        let active = note("active note")
        let untouched = neverUsedNote()
        // The owner typed in this note and emptied it again: its edit time moved (docs/decisions/0004).
        let emptied = Note(
            id: NoteID.make(), title: "", body: "", createdAt: Self.earlier,
            modifiedAt: Self.earlier.addingTimeInterval(60))
        let (storage, directory) = try makeStorage(
            notes: [active, untouched, emptied], tabs: [active.id, untouched.id, emptied.id], activeIndex: 0)
        let host = restore(storage, directory: directory)
        defer {
            host.cleanUp()
            withExtendedLifetime(host.window) {}
        }
        XCTAssertEqual(host.titles, ["active note", "Untitled", "Untitled"])

        host.coordinator.closeTab(at: 2)
        host.coordinator.closeTab(at: 1)
        host.coordinator.persistNow()

        XCTAssertNil(try storage.notes.note(untouched.id), "a note nobody typed in goes with its tab")
        XCTAssertNotNil(try storage.notes.note(emptied.id), "a note the owner emptied is theirs, and is kept")
    }

    /// The active note, when it was never used, is untouched too (it is the one that was read in full): another note that
    /// replaces it in the tab discards it.
    func testRestoreKeepsTheActiveNeverUsedNoteUntouched() throws {
        let untouched = neverUsedNote()
        let other = note("other")
        let (storage, directory) = try makeStorage(notes: [untouched, other], tabs: [untouched.id], activeIndex: 0)
        let host = restore(storage, directory: directory)
        defer {
            host.cleanUp()
            withExtendedLifetime(host.window) {}
        }

        host.coordinator.open(other.id, inNewTab: false)
        host.coordinator.persistNow()

        XCTAssertNil(try storage.notes.note(untouched.id), "the untouched note is replaced, and discarded")
        XCTAssertEqual(host.titles, ["other"])
    }
}
