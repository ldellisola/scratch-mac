# Delete and Recently Deleted

Deleting a note, the Recently Deleted section at the bottom of the sidebar, restoring, deleting for good, and the purge
after 30 days. Spec: [§6.7 Deleting](../superpowers/specs/2026-10-19-scratchpad-design.md), §6.2 (Recently Deleted),
§6.3 (a deleted note's tab closes) and §6.6 (a relaunch drops the tab of a deleted note), guarding the anti-goal "Lost
text" (§4): only the owner removes a note. The rules live in ScratchCore (`NoteStore.delete`, `restore`,
`deletePermanently`, `deletedSummaries`, `purge`, plan 2 task 3). The sidebar around it is in [sidebar.md](sidebar.md),
the tabs in [tabs.md](tabs.md).

Status: plan 2, task 9.

## Behaviour

- **Nothing removes a note except the owner.** Delete moves a note to Recently Deleted, and only Recently Deleted is
  purged, 30 days after the deletion (spec §6.7).
- **Delete** is in the context menu (right-click) of a note's row, and ⌘⌫ deletes the highlighted note **while the
  sidebar has the keyboard**.
  - ⌘⌫ is handled by the sidebar's table (`SidebarTableView.keyDown`) and is not a menu key equivalent. With the cursor
    in the editor it is the text system's "delete to the start of the line", and the note is not touched (plan 2
    "Review Focus" 2). ⌘⌫ on a note that is in Recently Deleted already does nothing, and beeps.
  - Deleting closes the tab that shows the note. When that was the only tab, the tab gets a new empty note, which the
    sidebar does not list (plan 2 "Review Focus" 5). Another tab's note, or the same tab's, is shown as after ⌘W.
  - The keyboard stays where it was: a delete from the sidebar does not put the cursor in the editor, so a second ⌘⌫
    deletes the next highlighted note and cannot become a ⌘⌫ in a note.
  - Typing that is not saved yet is written first, and the deletion never changes the note's text, its edit time or its
    pin (plan 2 "Review Focus" 1): the note in Recently Deleted has everything that was typed.
- **The Recently Deleted header** is the last header of the sidebar and exists only while a note is deleted. It reads
  "Recently Deleted (N)", with an arrow that points right while the notes are hidden and down while they are shown.
  - It starts collapsed, at every launch: the expanded state is not saved [call]. A click on the header shows or hides
    the deleted notes under it, most recently deleted first. While searching there is no Recently Deleted.
  - Its text has the accessibility identifier `sidebar.recentlyDeleted`. The other headers have `sidebar.group`.
- **A deleted note's row** has its title in grey and the context menu Restore and Delete Permanently….
  - **Restore** takes the note out of Recently Deleted, into its group by its last edit and with its pin.
  - **Delete Permanently…** asks, in a sheet on the window: "Delete “<title>” permanently? This can't be undone." with
    the buttons "Delete" (the red, destructive one) and "Cancel" [call]. Only "Delete" removes the note, text and all,
    and a tab that shows it closes.
- **Viewing a deleted note.** A click on a deleted row opens it in the current tab, like any note, and ⌘-click in a new
  tab. The editor shows it **read-only**.
  - The text and the title cannot be edited (typing, pasting, cutting and ⌘Z all leave them alone: a read-only note
    offers no undo history), the tab is dimmed and the pin button and ⇧⌘P are off.
  - **Restoring** a note that is open makes it editable in place: the same tab, cursor, scroll position and undo history.
- **A relaunch drops the tab of a deleted note** (Plan 1's rule, `SessionCoordinator.restore`), and when no tab is left
  the app starts a new empty note.
- **The purge.** Notes that were deleted more than 30 days ago (`NoteStore.recentlyDeletedRetention`) are removed from
  Recently Deleted.
  - It runs on the storage queue at launch, one turn of the main queue after the restore (so the first frame does not
    wait for it), and when the app becomes active, but not when the last purge was less than an hour ago.
  - A purged note that is open in a tab closes the tab. A live note is never purged, however old it is.

## Where it lives

- `App/Sources/Sidebar/SidebarViewController.swift`: the rows' context menus, the question of Delete Permanently…, the
  header click and ⌘⌫ on the highlighted row. It reports `onDelete`, `onRestore`, `onDeletePermanently` and
  `onToggleRecentlyDeleted`.
- `App/Sources/Sidebar/SidebarTableView.swift`: ⌘⌫ (`onCommandDelete`), and the click that the Recently Deleted header
  takes (`takesClick`), because a header cannot be highlighted and the table sends no action for it.
- `App/Sources/Sidebar/SidebarRowViews.swift`: the header with its arrow (`GroupRowCellView.configureRecentlyDeleted`),
  and the grey title of a deleted row.
- `App/Sources/Session/NoteListModel.swift`: `recentlyDeletedExpanded` and `toggleRecentlyDeleted()`.
- `App/Sources/Session/SessionCoordinator.swift`: `deleteNote`, `restoreNote`, `deleteNotePermanently` and
  `purgeExpiredNotes`, which write to the storage and close the tabs. A deleted note is shown read-only
  (`show(_:tab:)`).
- `App/Sources/Editor/EditorViewController.swift` and `NoteTextView.swift`: `setReadOnly(_:)`, and no undo manager while
  the note is read-only.
- `App/Sources/AppDelegate.swift`: the purge at launch and when the app becomes active.
- ScratchCore: `NoteStore` (`delete`, `restore`, `deletePermanently`, `deletedSummaries`, `purge`),
  `SidebarSections` (the Recently Deleted section) and the `recently-deleted` fixture.

## Tests

UI tests in `App/Tests/ScratchUITests/DeleteUITests.swift`. They use the `typical` fixture (six notes, two tabs) and the
`recently-deleted` fixture: "Groceries" (live, open), "Old meeting notes" (deleted 2 days ago) and "Ancient" (deleted 31
days ago, so the purge removes it at launch).

| Behaviour | Test |
|---|---|
| The context menu's Delete moves a note to Recently Deleted, and the header counts it | `DeleteUITests.testContextMenuDeleteMovesNoteToRecentlyDeleted` |
| ⌘⌫ in the sidebar deletes the highlighted note | `DeleteUITests.testCommandBackspaceInSidebarDeletes` |
| ⌘⌫ in the editor deletes text, never the note (plan 2 Review Focus 2) | `DeleteUITests.testCommandBackspaceInEditorKeepsNote` |
| Deleting the open note closes its tab | `DeleteUITests.testDeletingOpenNoteClosesItsTab` |
| Deleting the note of the only tab leaves one empty note (plan 2 Review Focus 5) | `DeleteUITests.testDeletingNoteInOnlyTabLeavesEmptyNote` |
| A note deleted while its typing is unsaved keeps the typing (plan 2 Review Focus 1) | `DeleteUITests.testDeleteWhileTypingKeepsTheTyping` |
| Recently Deleted starts collapsed, and a click on the header shows and hides it | `DeleteUITests.testRecentlyDeletedStartsCollapsedAndToggles` |
| Restore brings a note back to the list | `DeleteUITests.testRestoreBringsNoteBack` |
| Restoring the open note makes it editable in place | `DeleteUITests.testRestoringOpenNoteMakesItEditable` |
| Delete Permanently… asks, Cancel keeps the note, Delete removes it | `DeleteUITests.testDeletePermanentlyAsksThenRemoves` |
| A deleted note cannot be edited, and the pin is off | `DeleteUITests.testDeletedNoteIsReadOnly` |
| A relaunch drops the tab of a deleted note | `DeleteUITests.testDeletedNoteTabIsDroppedAtRelaunch` |
| Notes deleted more than 30 days ago are purged at launch | `DeleteUITests.testExpiredNotesArePurgedAtLaunch` |
| A read-only note offers no undo, and restoring gives it back | `EditorViewControllerTests.testReadOnlyNoteOffersNoUndo` |

The rules under these have unit tests in ScratchCore: `NoteStoreDeletionTests` (delete, restore, delete permanently, the
purge, and a save that never undoes a pin or a deletion) and `FixtureTests.recentlyDeletedFixture`.
