# Architecture

The design is in [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](superpowers/specs/2026-10-19-scratchpad-design.md),
section 9.2. This page records how the code is actually organised. Update it when the structure changes.

## Modules and the dependency rule

```
App (AppKit shell)  ──depends on──▶  ScratchCore (Foundation + CSQLite)  ──links──▶  system SQLite
```

- **`Packages/ScratchCore`** is a Swift package with no AppKit or SwiftUI imports. It holds everything rule-based:
  the note model, storage and full-text search (`NoteStore`, `SearchQuery`, the FTS5 index), the tab rules (`TabList`),
  the sidebar's groups and time labels, session state, autosave policy, launch options and fixtures, and the marker
  parser (`Markup/`: the spans of a line and the fenced code blocks of a note, as UTF-16 ranges the editor applies
  directly) and the rules for the keys that edit it (`ListEditing`, `InlineEditing`: what Return, Tab, ⇧Tab, ⇧⌘L, ⌘B
  and a click on a checkbox change, as a `TextEdit`). Later plans add paste classification, copy-out and code
  detection. It builds and tests with plain `swift test` on macOS and on Linux.
- **`App/`** is the thin AppKit shell: window, sidebar, editor view. It maps core values to UI and UI events to core
  calls. Logic found in the shell that could live in the core is a refactoring target. The app project is generated
  by XcodeGen from `App/project.yml`, and the generated project is not committed.
- **`CSQLite`** is a system-library target inside the package. Its module map links `sqlite3` and has no `pkgConfig`,
  so macOS builds link the system SQLite and never a Homebrew copy.

**The rule:** App depends on Core, never the other way round. Core must not import AppKit or SwiftUI. The Linux CI
job builds Core, and neither framework exists on Linux, so a forbidden import fails the build.

## Data flow

Typing a character, as the owner sees it, and where it ends up (`docs/features/autosave-and-restore.md`):

```
key press
  -> NoteTextView (NSTextView) -> EditorViewController.textDidChange -> onTextChange(text)
  -> SessionCoordinator: updates the current Note (body, modifiedAt) and calls Autosaver.markDirty()
  -> Autosaver (ScratchCore): one one-shot timer, 300 ms after the last change and at most 1 s after the first
  -> SessionCoordinator.saveNow() on the main thread: copies the notes to write (the ones whose last write failed, then
     the changed Note) and the SessionState
  -> storage queue: NoteStore.save for each note, SessionStore.save; a note whose write fails is recorded in
     UnsavedNotes, so the next save writes it again
  -> SessionCoordinator then asks NoteListModel.refresh(), which queues a read on the same storage queue:
     NoteStore.summaries() (and search, and deletedSummaries(), as needed)
  -> main thread: NoteListModel.didRead -> SessionCoordinator.didReadLiveSummaries (tab titles, pin state)
     -> SidebarSections.make -> SidebarViewController.reload
```

- **Formatting is attributes, never text** (`docs/features/formatting.md`). `MarkupStyler` is the text storage's
  delegate, so it runs inside every edit, before `textDidChange`: it restyles the paragraphs the edit touched, from the
  core's `MarkupParser` and `CodeBlockIndex` (the fenced blocks, carried over the edit). It sets fonts, colours,
  paragraph styles and a `scratchMarker` role on each marker character, and the stored characters stay exactly what was
  typed, so the data flow above, copy and search never see the formatting. `MarkupLayoutManager` turns the `hidden`
  roles into null glyphs and draws the bullets and boxes. A change of the selection goes through
  `EditorViewController` to `MarkupStyler.selectionDidChange`, which shows the markers of the bold and code runs the
  caret touches.
- **The keys that edit text go through the core.** Return, Tab, ⇧Tab, ⌘B, ⇧⌘L and a click on a box in `NoteTextView`
  hand the paragraphs under the selection to `ListEditing` or `InlineEditing`, and apply the `TextEdit` they answer
  with `NoteTextView.apply` (`shouldChangeText`, `replaceCharacters`, `didChangeText`, one undo step). From
  `didChangeText` on it is the path of a typed character, and the styler restyles what changed. A ⌘-click on a link
  asks `MarkupStyler.link(at:)` and opens it with `NSWorkspace`.
- A write that fails never costs text: `UnsavedNotes` (ScratchCore) keeps the note with the owner's text until a write of
  it succeeds, `persistNow()` and every save write those notes again, and `SessionCoordinator.loadNote` shows a note
  from there when it is opened again (`docs/features/autosave-and-restore.md`, "Write errors are not silent").
- A cursor or scroll change takes the same path through `EditorViewController.onViewStateChange`, but writes only the
  session (the open note's id, selection and scroll position), and does not re-read the note list.
- Quitting and deactivating skip the timer: `AppDelegate` calls `SessionCoordinator.persistNow()`, which runs the same
  save at once and waits until the storage queue is empty. Opening another note does the same for the note it leaves.
- Launching reads the session, then the note of every saved tab (`SessionCoordinator.restoredTabs`: a few small reads
  on the main thread, a tab whose note is gone or deleted is dropped), before the window shows. The note list is read
  on the storage queue after that (`SessionCoordinator.restore()`).
- A click on a sidebar row goes `SidebarViewController.onOpen` (the table's click action) ->
  `SessionCoordinator.open(_:inNewTab:)`. A click on a tab goes `TabStripViewController.onSelect` ->
  `SessionCoordinator.selectTab(at:)`. The toolbar's new note button, ⌘N and ⌘T go `ToolbarController.onNewNote` or
  `AppCommands.onNewNote` -> `SessionCoordinator.newNoteInNewTab()`. ⌘W, ⌃Tab and ⌘1 to ⌘9 reach the coordinator the
  same way through `AppCommands` (`docs/features/tabs.md`).
- The open tabs are a `TabList` (ScratchCore) held by the coordinator. A change of the tabs writes the note being left,
  shows the next note, redraws the tab strip and the sidebar, and hands the session to the storage queue at once.
- Deleting goes `SidebarViewController.onDelete` (a row's context menu, or ⌘⌫ while the table has the keyboard) ->
  `SessionCoordinator.deleteNote`: `persistNow()`, `NoteStore.delete` on the main thread, close the tab that shows the
  note, then a read of the note list. Restore and Delete Permanently… (after a sheet) go the same way
  (`restoreNote`, `deleteNotePermanently`). A deleted note that is opened from Recently Deleted is shown read-only. The
  purge (`purgeExpiredNotes`) runs on the storage queue at launch and when the app becomes active
  (`docs/features/recently-deleted.md`).
- The sidebar never shows a new note that nobody has used: the coordinator filters it out of the list, and deletes its
  row when its tab closes or another note replaces it while it is untouched (`NoteStore.discard`). A note the owner
  empties is not untouched in this sense and is kept (`docs/decisions/0004-new-tabs-and-emptied-notes.md`).

## Threading

- **The main thread** runs AppKit, `SessionCoordinator` (it is `@MainActor`, like the whole app target: default actor
  isolation is MainActor) and the `Autosaver`'s timers, because `DispatchAutosaveScheduler` is created on the main
  queue. The autosaver's save closure therefore runs on the main thread, where it may touch the editor.
- **One serial storage queue**, `io.github.ldellisola.Scratch.storage` (QoS utility), does every autosave write and the
  note list reads that follow. Writes go in one order, and typing never waits for the disk. The coordinator hands it
  copies (`Note` and `SessionState` are values), never the editor. The one thing that the queue writes and the main
  thread reads without a hop is `UnsavedNotes`, a mutex-guarded record of the notes whose write failed: the queue
  records an outcome as the write ends, so the record is right when `persistNow()` returns, which a callback on the main
  queue would not be.
- **`Database`** serialises every SQLite call with a mutex, so the main thread may also call the stores directly. It does
  so for the rare, small calls: restoring the session, creating a note, loading the note that is opened,
  discarding an untouched one, and deleting, restoring or deleting for good a note the owner chose. They wait for a write
  that is running.
- **`persistNow()` and every change that leaves the note in the editor wait for the storage queue on purpose**
  (`storageQueue.sync {}`), so that they never leave a write behind that a later read could miss. Opening another note,
  selecting another tab, `newNoteInNewTab`, closing the active tab and closing the only tab (when its note has been
  used) reach it through `leaveCurrentNote`, and `deleteNote` and `deleteNotePermanently` call it themselves.
  **Closing a tab that is not the active one does not wait** (`closeOtherTab`): the note in the editor does not
  change, and the closed tab's note was written when it was left. Neither does a click that changes nothing (the
  active tab, the note already shown). They run on the main thread only. Nothing the queue runs ever waits for the main
  thread (it hands results over with `DispatchQueue.main.async`), so this cannot deadlock.
- **The coordinator owns its `Autosaver`**, and the autosaver does not keep itself alive: a dirty one that is released
  skips its pending save. `AppDelegate` keeps the coordinator for the app's lifetime, and the save closure holds the
  coordinator weakly.
- A note list read (`NoteListModel.refresh`) carries a number, and only the newest read is shown, so a slow, stale list
  never replaces a newer one. A read goes to the storage queue after every write that is already queued, so it sees
  that write: `togglePin` queues `setPinned` and then asks for a read.

## The text system and the performance instrumentation

- **The editor is an `NSTextView` on TextKit 1**, built by `TextViewFactory` (`docs/decisions/0001-textkit-version.md`).
  The factory builds the stack by hand (storage, layout manager with non-contiguous layout, container, view), and
  `NoteTextView.ownedTextStorage` keeps the storage alive. A text view made any other way is TextKit 2 and slower in
  a long note.
- **Styling is bounded work on the main thread.** A keystroke restyles its paragraphs. A note that is shown is styled
  around the visible lines first (±200 paragraphs, before the first frame) and the rest in chunks of 1,000 paragraphs
  with a time budget, one per main run loop turn (`RunLoopIdle`), so a note of 10,000 lines switches within budget and
  is fully styled a few turns later (`MarkupStyler.isFullyStyled`). A paste of more than 20,000 characters is styled in
  the same chunks. Showing another note cancels the job. `MarkupLayoutManager` is `nonisolated` (AppKit does not
  annotate `NSLayoutManager` for the main actor), the styler is `@MainActor`.
- **Signposts** (`Signposts.editor`, subsystem `io.github.ldellisola.Scratch`, category `editor`) mark two intervals that
  the performance tests read: `keystroke` (`NoteTextView.keyDown`) and `switch-note` (`SessionCoordinator.open`). Both
  end when the main run loop is next about to wait (`RunLoopIdle`), so they include the layout and drawing that
  TextKit does after the work returns.
- **`FrameMonitor`**, started only by `-ScratchFrameMonitor <path>`, scrolls the note by itself and records the main
  thread's work per frame. It observes the main run loop and the editor's clip view and does not touch the data flow.
- The performance tests, their metrics and the CI check: AGENTS.md ("Performance") and `docs/decisions/0003-ci-performance-checks.md`.
