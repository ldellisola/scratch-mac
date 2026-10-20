# Autosave and restore

What is saved, when, and what a relaunch brings back, plus the sidebar and the new note button that go with it.
Spec: [§6.6 Saving, launching and quitting](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.2 (the sidebar
list) and §6.3 (a new note that stays empty is discarded), guarding the anti-goal "Lost text" (§4).

Status: plan 1 (walking skeleton). One note is open at a time, in a single tab. Later plans add tabs (plan 2), pinning,
search and deleting.

## Guarantees

- **No save step, ever.** Nothing in the app asks to save.
- **Every change reaches the disk within about one second.** The autosaver saves 300 ms after the last change and at
  most 1 s after the first unsaved change, so continuous typing still saves about once a second. A change is typed
  text, the cursor position or the scroll position. The save runs on a private queue, so typing never waits for it.
- **A force-kill or crash loses at most that second.** Text typed more than a second before the process was killed is
  in the database on the next launch.
- **Quitting and switching to another app write immediately.** ⌘Q right after the last keystroke loses nothing, because
  `applicationWillTerminate` and `applicationDidResignActive` write synchronously.
- **Opening another note saves the note being left first.** A new note that is still empty when it is left is
  discarded, so pressing the new note button again and again does not litter the list (spec §6.3).
- **A relaunch restores the session**: the note that was open, with the cursor and the scroll position where they were.
  A saved cursor offset that no longer fits the text is moved to the nearest valid position, and never splits a
  character. A session that points at a note that no longer exists, or is damaged, never keeps the app from
  launching: the app shows the first note it can, or else starts a new empty one.
- **The first launch opens one empty note**, ready to type in.
- **The sidebar lists the notes**, pinned first and then the most recently edited first, with the open note
  highlighted. A row shows the title (bold) or else the first line (in the note font), and a preview line below it.
  Clicking a row shows that note.
- **The toolbar's new note button** starts an empty note and puts the cursor in it. The note is not listed until it has
  text. It shows up in the sidebar about 300 ms after the first character.
- **Write errors are not silent.** A failed save is written to the standard error stream, the text stays in the editor,
  and the autosaver tries again.

Not guaranteed: undo history does not survive quitting (spec §6.6). A power cut can lose the last moments of typing,
because the database commits with `synchronous=NORMAL` in WAL mode: committed data survives any crash of the app,
not necessarily a loss of power.

## Where it lives

- `App/Sources/Session/SessionCoordinator.swift`: the one place that decides which note is open and when anything is
  written. It owns the `Autosaver` (ScratchCore), keeps the current `Note` and reads the note list.
- `App/Sources/Editor/EditorViewController.swift` reports edits (`onTextChange`) and cursor or scroll changes
  (`onViewStateChange`).
- `App/Sources/Sidebar/SidebarViewController.swift` shows the rows and reports the chosen one (`onSelect`).
- `App/Sources/Window/ToolbarController.swift` has the new note button (`onNewNote`).
- `App/Sources/AppDelegate.swift` creates all of them, keeps the coordinator and the toolbar controller alive, and calls
  `persistNow()` when the app quits or deactivates.
- ScratchCore: `Autosaver` (when to save), `NoteStore` and `SessionStore` (what is stored), `TextOffset.clamp` (the
  restored cursor). See `docs/architecture.md` for the data flow and the threading.

## Tests

UI tests in `App/Tests/ScratchUITests/`. Each launches the app in a data directory of its own and types without
clicking the editor first, which also proves that the editor is ready to type at launch.

| Behaviour | Test |
|---|---|
| Text typed, then SIGKILL (`NSRunningApplication.forceTerminate()`) more than a second later, is there on relaunch | `PersistenceUITests.testTypedTextSurvivesForceKill` |
| ⌘Q right after typing keeps the text | `PersistenceUITests.testQuitImmediatelyAfterTypingKeepsText` |
| The cursor comes back where it was (a typed character lands at the saved offset) | `PersistenceUITests.testCursorRestoredAfterRelaunch` |
| The launch shows the session's active note | `LaunchUITests.testLaunchShowsActiveNoteFromFixture` |
| The sidebar lists the fixture's notes, pinned first | `SidebarUITests.testSidebarListsFixtureNotesPinnedFirst` |
| Clicking a row shows that note | `SidebarUITests.testClickingRowShowsNote` |
| The new note button starts a note that is listed once it has text | `SidebarUITests.testNewNoteButtonCreatesListedNote` |
| An untouched new note is discarded when left | `SidebarUITests.testUntouchedNewNoteIsDiscarded` |

The rules under these live in ScratchCore and have unit tests there: the autosave timing (`AutosaverTests`), the stored
note and session (`NoteStoreTests`, `SessionStoreTests`), the clamped cursor (`TextOffsetTests`, including emoji and
CRLF) and a multi-megabyte body (`NoteStoreTests.largeBodyRoundTrips`).

Not covered by an automated test yet: saving the note being left when another is opened right after typing, the scroll
position of a restored note, and a failing write.
