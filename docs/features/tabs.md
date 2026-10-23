# Tabs

The tab strip in the toolbar, and the rules for opening, closing and switching tabs. Spec:
[§6.3 Tabs](../superpowers/specs/2026-10-19-scratchpad-design.md) (tabs are views onto notes), §6.2 (clicking a note in
the sidebar, ⌘-click) and §6.6 (a relaunch restores the tabs), guarding the anti-goals "Lost text" and "Fake glass"
(§4). Where a new tab opens, and which empty notes are discarded, are settled by
[docs/decisions/0004](../decisions/0004-new-tabs-and-emptied-notes.md), which amends §6.3. The rules themselves live in
ScratchCore (`TabList`, plan 2 task 4).

Status: plan 2, task 7, and plan 3, task 7 (emptied notes). The sidebar's groups, search and pinning are in [sidebar.md](sidebar.md) (task 8). Deleting a
note, which closes its tab, and a deleted note that is shown read-only in a tab are in
[recently-deleted.md](recently-deleted.md) (task 9).

## Behaviour

- **A tab is a view onto a note.** Closing a tab never deletes the note. The note stays in the sidebar list, and opening
  it again shows it in a tab again.
- **There is always one tab, and a note is open in at most one tab.** Opening a note that has a tab focuses that tab
  and does not make a second one.
- **New note.** ⌘N, ⌘T (File > New Note and New Tab), the toolbar's new note button and the strip's "+" button all
  create a new empty note in a new tab at the **end of the strip**, wherever the active tab is, and put the cursor in
  it (docs/decisions/0004). The note is not listed in the sidebar until it has text.
- **An untouched note is discarded when its tab closes**, or when another note replaces it in its tab, so that ⌘T does
  not litter the list (spec §6.3, as amended by docs/decisions/0004). A note is untouched while it was created in this
  session (or was empty when the app restored it) and is still empty. Switching to another tab keeps it. A note that
  has any text or title stays, tab or no tab. **A note that already existed and that the owner empties is kept**, listed
  as "Untitled" (dimmed), until the owner deletes it: emptying a note is not deleting it. This holds for every emptied
  note: the first edit of a note's text or title takes it out of the untouched ones for good, also one created in this
  session, and a note that is empty when the session is restored counts as untouched only when its edit time is still
  its creation time, so a note that was emptied and still open in a tab at quit is kept too (docs/decisions/0004,
  closed in 0.3.0).
- **Close.** ⌘W (File > Close Tab) closes the active tab, and the close button inside a tab closes that tab. VoiceOver reads
  that button as "Close <the tab's title>" (accessibility.md); the raised tab has a 1 pt outline with Increase Contrast. When the
  active tab closes, the tab that takes its place is shown (the one on its right, or else the new last tab). Closing the
  only tab leaves one tab with a new empty note, which is not listed. Closing the tab of a note that is still an empty,
  unused note leaves things as they are.
- **Close Window is ⇧⌘W** (File > Close Window). Closing the window quits the app, as before.
- **Switching.** Click a tab, or ⌃Tab and ⌃⇧Tab (Window > Show Next Tab, Show Previous Tab, which wrap around), or ⌘1 to
  ⌘8 for that tab and ⌘9 for the last one. A number past the last tab does nothing. The cursor goes into the note.
- **From the sidebar.**
  - A click on a row shows that note in the current tab. When the note is open in another tab, that tab is focused
    instead.
  - ⌘-click opens it in a new tab right after the active one (or focuses its tab). Unlike a new note, which goes to the
    end of the strip (docs/decisions/0004).
  - The arrow keys only move the sidebar's highlight. Return opens the highlighted row in the current tab.
  - The note that replaced an unused empty note discards it.
- **Each tab keeps its cursor and its scroll position** while it is open, and an undo history that lasts for the
  session (spec §6.6): ⌘Z after switching away and back still undoes the typing in the tab.
- **A relaunch restores the tabs**, in their order, with the active one. A tab whose note is gone or deleted is
  dropped (also one that showed a deleted note read-only), and so is a second tab for the same note. When no tab is
  left, the app starts one tab with a new empty note.
- **The session is written at once after every open, close or switch**, and not with the next autosave, so a crash right
  after changing the tabs keeps them. The text of the active note still goes out with the autosave, and with every
  switch.
- **The tab strip.** A Liquid Glass capsule (`NSGlassEffectView`, corner radius 17, 34 pt tall, the height of the toolbar's own
  capsules) in the **toolbar row**, the view of a toolbar item after the sidebar's tracking separator (plan 6 task 7,
  mockup B). The toolbar's items are, from the left: the sidebar button, the tracking separator, the strip, a flexible space,
  the pin and the paperclip (one glass group), a space and the new note button (another). It is as wide as its tabs, and no
  wider than the room the toolbar leaves before its buttons (below).
  - The item has no border and no shared background (`isBordered = false`), so the toolbar
    puts no second capsule round the strip's own, and visibility priority `high`; the three buttons have `user`, so none of
    them goes into the overflow menu.
  - **Its width is made to fit, never left to the toolbar:** a toolbar that is short of room moves items into its overflow
    menu, so the strip's required width constraint is `min(its tabs' width, the room)`, at least 96 pt. The room is the window's
    width less where the strip starts (the editor area's left edge and 16 pt with the sidebar shown, 150 pt from the window's
    edge with it hidden) less 176 pt for the buttons (two capsules, the space between and the margin are about 140 pt).
    `MainSplitViewController.onContentLayout` reports the three numbers after every layout, and
    `ToolbarController.updateTabStripWidth` hands the answer (`TabStripLayout.maximumWidth(windowWidth:leading:)`) to the
    strip (`maximumWidth`). So a window made narrower, and the sidebar hidden or shown, change the strip, and twelve tabs share
    it down to 48 pt each.
  - A tab is 120 to 200 pt wide, and shares the strip when they do not all fit. Its title is the note's title, or else
    the first line of the note that is not a fence line or an attachment line, or else "Untitled". That line is shown as
    the editor shows it, without its list marker, its `**` or its backticks, and as typed inside a fenced block (from
    1.0.0: [sidebar.md](sidebar.md), "A row shows a line as the editor shows it"). A titled tab is bold, an untitled one
    is in the note font.
  - The active tab is raised: a white pill (a lighter one in dark mode) with a soft shadow. The other tabs have no
    background.
  - A tab's title follows the note's about as fast as the sidebar row does: after the autosave.
- **Selecting a tab starts the `switch-note` signpost**, the interval that opening a note from the sidebar measures.

## Where it lives

- `App/Sources/Tabs/TabStripViewController.swift`: the strip (`TabStripViewController`, and `TabStripView` with its
  glass), the layout of the tabs (`TabStripLayout`, `TabStripContentView`) and one tab (`TabItemView`).
- `App/Sources/Window/ToolbarController.swift`: the toolbar's items, among them the strip's (`makeTabStripItem`) and the
  width it is given (`updateTabStripWidth`). `App/Sources/Window/EditorAreaViewController.swift` is the editor alone: it
  starts at the top of the window, with the toolbar in its safe area, and its title field sits 10 pt below that.
  `MainSplitViewController.onContentLayout` is what tells the toolbar about the room.
- `App/Sources/Session/SessionCoordinator.swift`: the tab list (`TabList`), `newNoteInNewTab`, `open(_:inNewTab:)`,
  `selectTab`, `closeTab`, the restore, and the session write after each change.
- `App/Sources/Sidebar/SidebarViewController.swift`: `onOpen(id, inNewTab)`, from the table's click action and Return.
  A click on a group header opens nothing.
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
| An untouched new tab is discarded when it closes, also from the database | `TabsUITests.testUntypedNewTabIsDiscardedOnClose`, `SaveFailureTests.testUntouchedNewNoteIsStillDiscardedWhenItsTabCloses` |
| A note typed in and then emptied is kept when its tab closes, and listed as "Untitled" | `TabsUITests.testTypedThenEmptiedNoteIsKeptWhenItsTabCloses`, `SaveFailureTests.testTypedThenEmptiedNoteIsKeptWhenItsTabCloses` |
| A note emptied and open at quit is kept after the relaunch, and when its tab closes | `TabsUITests.testEmptiedNoteSurvivesRelaunch`, `SaveFailureTests.testRestoredEmptiedNoteIsKeptAndRestoredUntouchedNoteIsDiscarded` |
| A tab's title has no list marker, bold stars or code backticks outside a fenced block, whichever tab is active | `SessionRestoreTests.testTabsShowTheirTitlesWithoutMarkers`, `NoteTests.checkboxTitleHasNoMarker` |
| The sidebar's new note button opens a tab, and a replaced untouched note is discarded | `SidebarUITests.testNewNoteButtonCreatesListedNote`, `testUntouchedNewNoteIsDiscarded` |
| The strip is a toolbar item (no border, no shared glass, the buttons never in the overflow), in the order of the plan, and the real window's toolbar has it, outside the editor area | `TabStripViewControllerTests.testToolbarItemOrder`, `testTabStripIsAToolbarItem`, `testTheWindowsToolbarHoldsTheStrip`, `testEditorAreaIsTheEditorAlone` |
| The strip is as wide as its tabs, never wider than its maximum, never below its floor, and the maximum leaves room for the buttons | `TabStripViewControllerTests.testStripIsAsWideAsItsTabs`, `testStripIsNeverWiderThanItsMaximum`, `testStripKeepsAFloorOfWidth`, `testMaximumWidthLeavesRoomForTheButtons` |
| The active tab is in the row of the toolbar's buttons, left of them, with no band under the toolbar (plan 6 Review Focus 4) | `TabsUITests.testTabStripIsInTheToolbarRow` |
| Twelve tabs keep the pin, the paperclip and the new note button in reach, with the sidebar shown, hidden and shown again | `TabsUITests.testTwelveTabsKeepTheToolbarButtons` |
| The close button names its tab ("Close Deploy checklist"), and the toolbar's buttons have labels | `AccessibilityUITests.testCloseButtonNamesItsTab`, `testToolbarButtonsHaveLabels` |

The rules under these (where a tab opens, which tab is active after a close, wrapping, ⌘9) have unit tests in
ScratchCore: `TabListTests`.
