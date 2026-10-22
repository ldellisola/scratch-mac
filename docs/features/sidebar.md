# Sidebar

The note list in the glass sidebar: group headers, the edit time on each row, pinning and full-text search. Spec:
[§6.2 Sidebar: the note list](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.1 (the sidebar's width is
remembered), §6.7 (what Recently Deleted holds), guarding the anti-goal "Lost text" (§4): pinning never changes a
note's text. The rules live in ScratchCore (`SidebarSections`, `NoteTimeLabel`, `SearchQuery`, `NoteStore`, plan 2
tasks 2, 3 and 5). Opening a note, tabs and ⌘-click are in [tabs.md](tabs.md).

Status: plan 2, tasks 8 and 9. Deleting, restoring and the Recently Deleted section are in
[recently-deleted.md](recently-deleted.md).

## Behaviour

- **A search field** ("Search", `sidebar.search`) sits above the list, below the toolbar. ⌥⌘F (Edit > Search Notes)
  puts the cursor in it, and shows the sidebar first when it is hidden. ⌘F is still the find bar of the note.
- **The list is in groups**, each under a small grey header (`sidebar.group`, not a row):
  - **Pinned** first, then **Today**, **Yesterday** and **Earlier**, then **Recently Deleted**.
  - A group with no notes has no header. Recently Deleted is there only when a note is in it, and starts collapsed:
    its header reads "Recently Deleted (N)", and a click on it shows or hides the deleted notes
    ([recently-deleted.md](recently-deleted.md)).
  - Today and Yesterday are calendar days in the Mac's time zone, not spans of 24 hours (`SidebarSections`). The groups
    are worked out again with the current time every time the list is shown, and the app reads the list when it
    becomes active, so Today rolls over at midnight.
  - Pinned notes and the notes of each day are in order of the last edit, newest first.
- **A row** has the title (bold) or else the first line (in the note font), the edit time on the right
  (`sidebar.row.time`) and a preview line below, in the system font. A pinned note has a small orange pin before its
  title, and a group's header starts at the same left edge as the titles under it (mockup B).
  - **A row never takes its title or its preview from a fence line or an attachment line** (from 0.5.0, plan 5 task 1).
    A note that starts with a fenced block is listed by its first line of code, not by "```swift", and a line
    `[[attachment:<id>]]` is a picture or a file, not words. A note that holds nothing else is listed as "Untitled"
    (dimmed): a note with only an image has no title and is still a note. The sidebar columns of the notes that were saved
    before 0.5.0 are worked out again by the migration to schema version 3, without touching a note's edit time.
  - The time is the time of day for Today and Yesterday (`10:42`, or `10:42 AM` in a 12-hour locale), the month and the
    day for earlier this year (`Oct 14`) and the year too before that (`Oct 14, 2025`): the locale's own formats
    (`NoteTimeLabel`).
  - A group header cannot be highlighted or opened. The arrow keys step over it, and a click on it does nothing.
- **Pinning.**
  - The row's context menu (right-click) has Pin, or Unpin for a pinned note, and Delete (a note in Recently Deleted
    has Restore and Delete Permanently… instead).
  - The toolbar's pin button (`toolbar.pin`), left of the new note button, and ⇧⌘P (File > Pin Note) pin or unpin the
    note of the active tab. The button shows a filled pin and the label "Unpin" while the note is pinned.
  - Pinning only sets the pin. The note's text and its edit time stay as they are, so it does not move to the top of its
    group, and typing that is not saved yet is neither lost nor written over: pin and text are stored independently
    (`NoteStore.save` never writes the pin).
- **Search.**
  - Each keystroke in the field filters the list. It matches the title and the text together, every word as the start
    of a word, ignoring case and accents: "kube roll" finds a note that has "kubectl" and "rollout".
  - While searching, the list shows the matches in their groups, without Recently Deleted. Nothing in the text is
    special: quotes, `*`, `-`, `NEAR`, `AND` and emoji are only characters (`SearchQuery`). Text with no letter or digit
    in it filters nothing.
  - Clearing the field (select all and delete, the cancel button) or pressing Escape in it shows the whole list again.
  - The search runs on the storage queue, and a result that a newer keystroke has replaced is dropped.
- **The sidebar's width is remembered** (and whether it is hidden), except in an isolated data directory (tests,
  screenshots), which always starts the same. Spec §6.1.
- **A new note that nobody has used is not listed**, and so is a new note in another tab while it is empty (spec §6.3,
  [tabs.md](tabs.md)).

## Where it lives

- `App/Sources/Sidebar/SidebarViewController.swift`: the search field, the table and the rows' menu. It shows the
  sections it is given (`reload`) and reports `onOpen`, `onSearch`, `onTogglePin` and, for deleting,
  `onDelete`, `onRestore`, `onDeletePermanently` and `onToggleRecentlyDeleted`.
- `App/Sources/Sidebar/SidebarRowViews.swift`: `NoteRowCellView` (a note's row) and `GroupRowCellView` (a header).
- `App/Sources/Sidebar/SidebarTableView.swift`: the table: Return opens the highlighted row, ⌘⌫ deletes it, a click on
  the Recently Deleted header is taken before the table sees it, and the context menu of a row.
- `App/Sources/Session/NoteListModel.swift`: reads the live notes, the search results and Recently Deleted on the
  storage queue (stale reads are dropped by a request number), builds the sections (`SidebarSections.make`) with the
  current time, and hides the notes that nobody has used.
- `App/Sources/Session/SessionCoordinator.swift`: `togglePin`, `togglePinOfActiveNote`, which notes are hidden, the pin
  state it reports (`onActiveNotePinChange`).
- `App/Sources/Window/ToolbarController.swift` (the pin item), `AppCommands.swift` and `MainMenu.swift` (⇧⌘P, ⌥⌘F),
  `MainSplitViewController.swift` (the remembered width).
- ScratchCore: `SidebarSections`, `NoteTimeLabel`, `SearchQuery`, `NoteStore.search`, `setPinned`, `deletedSummaries`.

## Tests

UI tests in `App/Tests/ScratchUITests/SidebarUITests.swift`, on the `typical` fixture: "Snippets I keep reusing"
(pinned), "Deploy checklist" and a curl note (1 and 2 hours old), "Standup" and a SQL note (a day old) and "Groceries"
(5 days old).

| Behaviour | Test |
|---|---|
| The headers are Pinned, Today, Yesterday, Earlier, in that order | `SidebarUITests.testGroupHeadersInOrder` |
| A row shows its edit time | `SidebarUITests.testRowShowsTimeLabel` |
| The toolbar's pin button moves the note to Pinned | `SidebarUITests.testPinButtonMovesNoteToPinned` |
| ⇧⌘P pins and unpins | `SidebarUITests.testShiftCommandPTogglesPin` |
| The row's context menu unpins | `SidebarUITests.testContextMenuUnpins` |
| A pin clicked while typing is unsaved sticks, and so does the typing (plan 2 Review Focus 1) | `SidebarUITests.testPinWhileTypingSticks` |
| Search finds a word in the text, and a title in any case | `SidebarUITests.testSearchFiltersByBodyText`, `testSearchMatchesTitlesCaseInsensitively` |
| Clearing the field, or Escape, brings the whole list back | `SidebarUITests.testClearingSearchRestoresList`, `testEscapeClearsSearch` |
| The sidebar lists the fixture's notes, pinned first | `SidebarUITests.testSidebarListsFixtureNotesPinnedFirst` |
| A title and a preview skip fence lines and attachment lines; an image-only note has no title | `NoteTests.titleSkipsFenceLines`, `titleSkipsAttachmentLines`, `imageOnlyNoteHasEmptyTitle`, `previewSkipsFenceAndAttachmentLines` |
| The migration to schema version 3 works the titles out again, keeps every note, and leaves `modified_at` alone | `SchemaTests.migratingV2RecomputesTitles`, `migratingV2KeepsEveryNoteAndEveryOtherColumn` |

The rules under these have unit tests in ScratchCore: the groups by calendar day, also across a clock change
(`SidebarSectionsTests`), the time labels (`NoteTimeLabelTests`), the search expression and the search itself
(`SearchQueryTests`, `NoteStoreSearchTests`, including query syntax that must not fail), and pin, delete, restore and
purge (`NoteStoreDeletionTests`, and `NoteStoreTests.saveDoesNotOverwritePinOrDeletion`).
