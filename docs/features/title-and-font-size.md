# Title and font size

The optional title above a note, the one font size of every note, and the undo history that each note keeps for the
session. Spec: [§6.4 Editor and formatting](../superpowers/specs/2026-10-19-scratchpad-design.md) (the title, one
font, ⌘+ / ⌘− / ⌘0) and §6.6 (undo is per note and lasts for the session), guarding the anti-goal "Lost text" (§4).

Status: plan 2, task 6. Sessions, scroll and the rest of the persistence are in
[autosave-and-restore.md](autosave-and-restore.md).

## Behaviour

- **A note may have a title.** A borderless single-line field sits above the text, inside the editor and below the
  toolbar. It does not scroll with the text. It is bold SF Mono, three points larger than the text, and shows a dimmed
  "Untitled" while it is empty.
- **Return or Tab in the title moves the cursor to the text.** ⇧Tab is left to AppKit.
- **The title is saved like the text.** Each edit marks the note changed, so it is written within about a second and
  the note goes to the top of the sidebar (a changed note is the most recently edited). A note whose only content is a
  title is not empty, so it is listed and is not discarded when left. The title is not part of the text: copying the
  note's text does not include it. The sidebar and the tabs show the title when there is one, else the first line (not
  a fence line or an attachment line: [sidebar.md](sidebar.md)).
- **One font size for every note.** 13 pt by default, 9 to 32 pt in steps of 1 pt (`FontSize`). View > Bigger is ⌘+ (and
  ⌘=, which needs no Shift), Smaller is ⌘−, Actual Size is ⌘0. The title follows the text (size + 3). What is typed and
  what is pasted takes the size too, so a paste never brings its own size (spec §6.5). The line at the top of the
  window stays at the top when the size changes.
- **The size is remembered.** It is part of the saved session, so a relaunch shows it.
- **Undo history is per note and lasts for the session.** Typing in note A, switching to note B and coming back leaves
  A's typing undoable with ⌘Z, and B's history is not mixed into it. Loading a note is never an undo step. Quitting
  ends the history (spec §6.6).
- **A read-only note** (a note in Recently Deleted, [recently-deleted.md](recently-deleted.md)) takes no typing in the
  text or in the title, and offers no undo: its history, if it has one, comes back when the note is restored
  (`setReadOnly(false)`, which makes the note that is shown editable in place).

## Where it lives

- `App/Sources/Editor/TitleField.swift`: the field, its font and its placeholder.
- `App/Sources/Editor/EditorViewController.swift`: the container of the title field and the scroll view, `show(_:tab:
  undoManager:isReadOnly:)`, `setFontSize(_:)`, `focusTitle()` and `focusBody()`, and the reports `onTitleChange` and
  `onTextChange`. It is the text view's delegate (`undoManager(for:)`) and the title field's (Return and Tab).
- `App/Sources/Editor/NoteTextView.swift`: `noteFont(size:)`, `applyFontSize(_:)` (font, colour and typing attributes
  in one place) and `noteUndoManager`.
- `App/Sources/Session/SessionCoordinator.swift`: keeps one `UndoManager` per note (`undoManagers`), turns a title edit
  into a changed note (`titleDidChange`), and holds, restores and saves the font size (`changeFontSize`).
- `App/Sources/Window/AppCommands.swift` and `MainMenu.swift`: the View menu items. `AppDelegate` connects them to the
  coordinator, and answers `windowWillReturnUndoManager` with the undo manager of the note in the editor, so the Edit
  menu undoes the same history that typing writes to.
- ScratchCore: `FontSize` (the limits and the steps), `SessionState.fontSize`.

## Tests

| Behaviour | Test |
|---|---|
| The note's title is shown in the title field | `EditorViewControllerTests.testShowFillsTheTitleField` |
| Return and Tab in the title focus the text, ⇧Tab does not | `EditorViewControllerTests.testReturnInTitleFocusesBody` |
| An edit of the title is reported, loading one is not | `EditorViewControllerTests.testTitleEditsAreReported` |
| ⌘+ sizes the text, the typing attributes and the title (size + 3, bold) | `EditorViewControllerTests.testFontSizeAppliesToTextTypingAndTitle` |
| The next note shown takes the size | `EditorViewControllerTests.testFontSizeAppliesToTheNextNote` |
| A paste after a size change takes the new size | `EditorViewControllerTests.testPasteAfterFontSizeChangeUsesNewSize` |
| Undo history is per note | `EditorViewControllerTests.testUndoHistoryIsPerNote` |
| Showing a note does not clear its history | `EditorViewControllerTests.testShowDoesNotClearUndo` |
| A read-only note takes no typing, and the next editable note does | `EditorViewControllerTests.testReadOnlyRejectsTyping` |
| A read-only note offers no undo, and restoring it gives the history back and makes it editable | `EditorViewControllerTests.testReadOnlyNoteOffersNoUndo`, `testSetReadOnlyFalseMakesTheShownNoteEditable` |
| A typed title becomes the sidebar title, and the text is not part of it | `TitleUITests.testTitleBecomesSidebarTitle` |
| The title survives a relaunch | `TitleUITests.testTitleSurvivesRelaunch` |
| ⌘= twice gives 15 pt, which survives a relaunch | `TitleUITests.testFontSizeIsRemembered` |

The limits and steps of the size are unit-tested in ScratchCore (`FontSizeTests`), and the saved size in
`SessionStoreTests`. The undo of a switch between tabs through ⌘Z is a UI test of plan 2 task 7.
