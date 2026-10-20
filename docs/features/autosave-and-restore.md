# Autosave and restore

What is saved, when, and what a relaunch brings back, plus the sidebar and the new note button that go with it.
Spec: [§6.6 Saving, launching and quitting](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.2 (the sidebar
list) and §6.3 (a new note that stays empty is discarded), guarding the anti-goal "Lost text" (§4).

Status: plan 1 (walking skeleton), plan 2, tasks 6 and 7 (the title, the font size, the scroll anchor, the undo
history, and tabs) and plan 3, task 7 (failed writes, the top inset). Notes are open in tabs: see [tabs.md](tabs.md). Pinning and search are in
[sidebar.md](sidebar.md), deleting in [recently-deleted.md](recently-deleted.md).

## Guarantees

- **No save step, ever.** Nothing in the app asks to save.
- **Every change reaches the disk within about one second.** The autosaver saves 300 ms after the last change and at
  most 1 s after the first unsaved change, so continuous typing still saves about once a second. A change is typed
  text or a typed title, the cursor position, the scroll position or the font size. The save runs on a private queue,
  so typing never waits for it.
- **A force-kill or crash loses at most that second.** Text typed more than a second before the process was killed is
  in the database on the next launch.
- **Quitting and switching to another app write immediately.** ⌘Q right after the last keystroke loses nothing, because
  `applicationWillTerminate` and `applicationDidResignActive` write synchronously.
- **Leaving a note saves it first.** Opening another note, switching to another tab and closing a tab write the note
  being left, and the session, before the next note shows. A new note that is still empty when its tab closes, or when
  another note replaces it in the tab, is discarded, so pressing the new note button again and again does not litter
  the list (spec §6.3).
- **A change of the tabs is written at once**, not with the next autosave: the session (the tabs, the active tab and
  the font size) goes to the storage queue right after an open, close or switch, so a crash a moment later keeps the
  tabs.
- **A relaunch restores the session**: the tabs in their order, the active one, and in each tab the cursor and the
  scroll position where they were, and the font size. A saved cursor offset that no longer fits the text is moved to the nearest valid position, and
  never splits a character. A session that points at a note that no longer exists, or is damaged, never keeps the app from
  launching: the app drops the tabs it cannot show and shows the first it can, or else starts a new empty note.
- **The scroll position is saved as an anchor, not as points.** The anchor is the UTF-16 offset of the first character
  of the line at the top of the visible text (`TabState.scrollAnchor`), so the same text is at the top after a relaunch
  even when the window has another width or the font another size. A session saved by Scratch 0.1.0 has no anchor and
  restores its scroll offset in points (`TabState.scrollY`) once. The editor can only position text when it has a
  width, so at launch it keeps the anchor and scrolls to it in the first layout, and a save before that layout writes
  the anchor it was given. The text above the anchor is laid out for this (TextKit lays out lazily), which takes a
  moment in a very long note.
- **A note at its top shows the gap above its first line.** The text starts 12 pt below the top of the editor (the text
  container's inset), and a note shown without an anchor, with anchor 0 or scrolled to its top has that gap on screen,
  as the first note of the typical fixture has. AppKit scrolls a text view to its selection whenever the view is resized
  (at launch, when the scrollers change style, when the window or the sidebar is resized), which moved a long note's
  first line up to the top of the window; `NoteTextView.scrollToVisible(_:)` finishes the scroll to the top when that
  leaves less than the gap above the text.
- **The first launch opens one empty note**, ready to type in.
- **The sidebar lists the notes**, pinned first and then the most recently edited first, with the open note
  highlighted. A row shows the title (bold) or else the first line (in the note font), a preview line below it and
  the edit time. Clicking a row shows that note in the current tab (⌘-click: in a new tab). The groups, pinning and
  search are in [sidebar.md](sidebar.md).
- **The toolbar's new note button** (and ⌘N, ⌘T) starts an empty note in a new tab and puts the cursor in it. The note
  is not listed until it has text. It shows up in the sidebar about 300 ms after the first character.
- **Write errors are not silent, and never cost text.** A failed save is written to the standard error stream, the text
  stays in the editor, and the autosaver tries again. A note whose write failed is kept in memory (`UnsavedNotes`, in
  `SessionCoordinator.unsavedNotes`), also when the owner has already switched to another note or tab: every save writes
  it again, before the note of the active tab, until a write succeeds, and `persistNow()` (quitting, deactivating,
  leaving a note) does the same. Switching back to such a note shows the text the owner left, not the older text in the
  database. The session is written even when a note's write failed.

Within a session every note keeps its own undo history, and switching notes never clears it. It does not survive
quitting (spec §6.6: it lasts for the session). See [title-and-font-size.md](title-and-font-size.md). A power cut can lose the last moments of typing,
because the database commits with `synchronous=NORMAL` in WAL mode: committed data survives any crash of the app,
not necessarily a loss of power.

## Where it lives

- `App/Sources/Session/SessionCoordinator.swift`: the one place that decides which note is open and when anything is
  written. It owns the `Autosaver` (ScratchCore) and keeps the current `Note`. After each save it asks
  `NoteListModel` (`App/Sources/Session/NoteListModel.swift`) to read the note list again.
- `App/Sources/Editor/EditorViewController.swift` reports edits (`onTextChange`, `onTitleChange`) and cursor or scroll
  changes (`onViewStateChange`), and gives the scroll position as `currentScrollAnchor`.
- `App/Sources/Sidebar/SidebarViewController.swift` shows the sections and rows it is given and reports the one that
  was opened (`onOpen`).
- `App/Sources/Tabs/TabStripViewController.swift` shows the tabs and reports a click, a close and the "+" button.
- `App/Sources/Window/ToolbarController.swift` has the new note button (`onNewNote`).
- `App/Sources/AppDelegate.swift` creates all of them, keeps the coordinator and the toolbar controller alive, and calls
  `persistNow()` when the app quits or deactivates.
- ScratchCore: `Autosaver` (when to save), `UnsavedNotes` (the notes whose write failed), `NoteStore` and `SessionStore`
  (what is stored), `TextOffset.clamp` (the restored cursor). See `docs/architecture.md` for the data flow and the threading.

## Tests

UI tests in `App/Tests/ScratchUITests/`. Each launches the app in a data directory of its own and types without
clicking the editor first, which also proves that the editor is ready to type at launch.

| Behaviour | Test |
|---|---|
| Text typed, then SIGKILL (`NSRunningApplication.forceTerminate()`) more than a second later, is there on relaunch | `PersistenceUITests.testTypedTextSurvivesForceKill` |
| ⌘Q right after typing keeps the text | `PersistenceUITests.testQuitImmediatelyAfterTypingKeepsText` |
| The cursor comes back where it was (a typed character lands at the saved offset) | `PersistenceUITests.testCursorRestoredAfterRelaunch` |
| The scroll position comes back as the same text at the top (read from the `debug.state` element) | `TitleUITests.testScrollPositionSurvivesRelaunch` |
| A note shown before the first layout, or after it, is scrolled to its anchor | `EditorViewControllerTests.testScrollAnchorRoundTrips`, `testScrollAnchorAppliesWhenAlreadyLaidOut` |
| A note without an anchor shows its top, and the anchor given is the one saved | `EditorViewControllerTests.testNoteWithoutAnchorShowsItsTop`, `testScrollAnchorIsSavedAsGiven` |
| A note at its top shows the text view's top inset (the clip view is at `-contentInsets.top`, not past it) | `EditorViewControllerTests.testNoteWithoutAnchorShowsItsTopInset`, `testScrollToTheFirstLineKeepsTheTopInsetOnScreen`, `TitleUITests.testHugeNoteShowsItsTopInsetAtLaunch` |
| A failed write of a note that was left is retried by the next save | `SaveFailureTests.testFailedSaveOfLeftNoteIsRetried`, `testFailedFirstSaveOfLeftNoteIsRetried`, `testNewerTypingWinsOverAFailedOlderCopy` |
| Switching back to a note whose write failed shows the text that was left | `SaveFailureTests.testSwitchingBackShowsUnsavedText` |
| The record of failed writes keeps the newest copy of a note, and forgets it when a write succeeds | ScratchCore `UnsavedNotesTests` |
| The launch shows the session's active note | `LaunchUITests.testLaunchShowsActiveNoteFromFixture` |
| The sidebar lists the fixture's notes, pinned first | `SidebarUITests.testSidebarListsFixtureNotesPinnedFirst` |
| Clicking a row shows that note | `SidebarUITests.testClickingRowShowsNote` |
| The new note button starts a note that is listed once it has text | `SidebarUITests.testNewNoteButtonCreatesListedNote` |
| An untouched new note is discarded when another note replaces it | `SidebarUITests.testUntouchedNewNoteIsDiscarded` |
| The tabs and the active tab come back | `TabsUITests.testTabsAndActiveTabSurviveRelaunch` |

The rules under these live in ScratchCore and have unit tests there: the autosave timing (`AutosaverTests`), the stored
note and session (`NoteStoreTests`, `SessionStoreTests`), the clamped cursor (`TextOffsetTests`, including emoji and
CRLF) and a multi-megabyte body (`NoteStoreTests.largeBodyRoundTrips`).

Not covered by an automated test yet: a crash right after a change of the tabs. (Saving the note being left when another
is opened right after typing, and a failing write, are `SaveFailureTests`: `PRAGMA query_only = 1` on
`ScratchStorage.database` makes every write fail, which file permissions cannot do on an open SQLite file.)
