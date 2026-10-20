# Tabs

The tab strip above the editor, and the rules for opening, closing and switching tabs. Spec:
[§6.3 Tabs](../superpowers/specs/2026-10-19-scratchpad-design.md) (tabs are views onto notes), §6.2 (clicking a note in
the sidebar, ⌘-click) and §6.6 (a relaunch restores the tabs), guarding the anti-goals "Lost text" and "Fake glass"
(§4). The rules themselves live in ScratchCore (`TabList`, plan 2 task 4).

Status: plan 2, task 7. Sidebar groups, search and pinning follow in task 8, and deleting a note, which closes its tab,
in task 9.

## Behaviour

- **A tab is a view onto a note.** Closing a tab never deletes the note. The note stays in the sidebar list, and opening
  it again shows it in a tab again.
- **There is always one tab, and a note is open in at most one tab.** Opening a note that has a tab focuses that tab
  and does not make a second one.
- **New note.** ⌘N, ⌘T (File > New Note and New Tab), the toolbar's new note button and the strip's "+" button all
  create a new empty note in a new tab at the end of the strip, and put the cursor in it. The note is not listed in the
  sidebar until it has text.
- **A new empty note nobody typed in is discarded when its tab closes**, or when another note replaces it in its tab,
  so that ⌘T does not litter the list (spec §6.3). A note that has any text or title stays, tab or no tab.
- **Close.** ⌘W (File > Close Tab) closes the active tab, and the close button inside a tab closes that tab. When the
  active tab closes, the tab that takes its place is shown (the one on its right, or else the new last tab). Closing the
  only tab leaves one tab with a new empty note, which is not listed. Closing the tab of a note that is still an empty,
  unused note leaves things as they are.
- **Close Window is ⇧⌘W** (File > Close Window). Closing the window quits the app, as before.
- **Switching.** Click a tab, or ⌃Tab and ⌃⇧Tab (Window > Show Next Tab, Show Previous Tab, which wrap around), or ⌘1 to
  ⌘8 for that tab and ⌘9 for the last one. A number past the last tab does nothing. The cursor goes into the note.
- **From the sidebar.**
  - A click on a row shows that note in the current tab. When the note is open in another tab, that tab is focused
    instead.
  - ⌘-click opens it in a new tab right after the active one (or focuses its tab).
  - The arrow keys only move the sidebar's highlight. Return opens the highlighted row in the current tab.
  - The note that replaced an unused empty note discards it.
- **Each tab keeps its cursor and its scroll position** while it is open, and an undo history that lasts for the
  session (spec §6.6): ⌘Z after switching away and back still undoes the typing in the tab.
- **A relaunch restores the tabs**, in their order, with the active one. A tab whose note is gone or deleted is
  dropped, and so is a second tab for the same note. When no tab is left, the app starts one tab with a new empty note.
- **The session is written at once after every open, close or switch**, and not with the next autosave, so a crash right
  after changing the tabs keeps them. The text of the active note still goes out with the autosave, and with every
  switch.
- **The tab strip.** A Liquid Glass bar (`NSGlassEffectView`, corner radius 14, 32 pt tall) below the toolbar, 12 pt from
  the left. It is as wide as its tabs, and no wider than the editor area less 12 pt on each side.
  - A tab is 120 to 200 pt wide, and shares the strip when they do not all fit. Its title is the note's title, or else
    the first line of the note, or else "Untitled". A titled tab is bold, an untitled one is in the note font.
  - The active tab is raised: a white pill (a lighter one in dark mode) with a soft shadow. The other tabs have no
    background.
  - A tab's title follows the note's about as fast as the sidebar row does: after the autosave.
- **Selecting a tab starts the `switch-note` signpost**, the interval that opening a note from the sidebar measures.

## Where it lives

- `App/Sources/Tabs/TabStripViewController.swift`: the strip (`TabStripViewController`, and `TabStripView` with its
  glass), the layout of the tabs (`TabStripLayout`, `TabStripContentView`) and one tab (`TabItemView`).
- `App/Sources/Window/EditorAreaViewController.swift`: the strip above the editor, below the toolbar.
- `App/Sources/Session/SessionCoordinator.swift`: the tab list (`TabList`), `newNoteInNewTab`, `open(_:inNewTab:)`,
  `selectTab`, `closeTab`, the restore, and the session write after each change.
- `App/Sources/Sidebar/SidebarViewController.swift`: `onOpen(id, inNewTab)`, from the table's click action and Return.
- `App/Sources/Window/AppCommands.swift` and `MainMenu.swift`: the File and Window menu items.
  `App/Sources/Window/ToolbarController.swift`'s new note button calls the same `newNoteInNewTab`.
- ScratchCore: `TabList`, `TabOpening`, `TabClosing` and `TabState` (the rules and the saved form).

## Tests

UI tests in `App/Tests/ScratchUITests/TabsUITests.swift`, on the `typical` fixture, which opens two tabs: "Deploy
checklist" (active) and the untitled curl note. `UITestSupport.tabs(in:)`, `tabTitles(in:)`, `activeTabTitle(in:)` and
`activeTabIndex(in:)` read the strip: each tab is a button with the identifier `tab.item`, its label is the title, and
it is selected when it is the active tab.

| Behaviour | Test |
|---|---|
| Both tabs come back, the first active, with the sidebar's titles | `TabsUITests.testRestoresBothTabsWithFirstActive` |
| ⌘T opens a new empty tab at the end, and the note is not listed | `TabsUITests.testCommandTOpensNewEmptyTab` |
| Closing a tab keeps its note in the list | `TabsUITests.testClosingTabKeepsNote` |
| Closing the last tab leaves one tab with a new empty note that is not listed (plan 2 Review Focus 5) | `TabsUITests.testClosingLastTabLeavesEmptyNote` |
| ⌘-click on a row opens the note in a new tab after the active one | `TabsUITests.testCommandClickOpensNoteInNewTab` |
| Clicking a note that is open in another tab focuses that tab | `TabsUITests.testClickingNoteOpenInOtherTabFocusesIt` |
| ⌃Tab and ⌃⇧Tab switch tabs and wrap | `TabsUITests.testControlTabCyclesAndWraps` |
| ⌘9 selects the last tab, ⌘1 to ⌘8 that tab, a number past the last does nothing | `TabsUITests.testCommandNineSelectsLastTab` |
| The tabs and the active tab survive a relaunch | `TabsUITests.testTabsAndActiveTabSurviveRelaunch` |
| Undo history survives a switch to another tab and back | `TabsUITests.testUndoSurvivesTabSwitch` |
| An untouched new tab is discarded when it closes, also from the database | `TabsUITests.testUntypedNewTabIsDiscardedOnClose` |
| The sidebar's new note button opens a tab, and a replaced untouched note is discarded | `SidebarUITests.testNewNoteButtonCreatesListedNote`, `testUntouchedNewNoteIsDiscarded` |

The rules under these (where a tab opens, which tab is active after a close, wrapping, ⌘9) have unit tests in
ScratchCore: `TabListTests`.
