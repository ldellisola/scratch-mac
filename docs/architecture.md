# Architecture

The design is in [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](superpowers/specs/2026-10-19-scratchpad-design.md),
section 9.2. This page records how the code is actually organised. Update it when the structure changes.

## Modules and the dependency rule

```
App (AppKit shell)  ──depends on──▶  ScratchCore (Foundation + CSQLite)  ──links──▶  system SQLite
        │
        └───────────depends on──▶  ScratchCode (Foundation + tree-sitter)  ──▶  the tree-sitter runtime, 17 grammars
```

- **`Packages/ScratchCore`** is a Swift package with no AppKit or SwiftUI imports. It holds everything rule-based:
  the note model, storage and full-text search (`NoteStore`, `SearchQuery`, the FTS5 index), the tab rules (`TabList`),
  the sidebar's groups and time labels, session state, autosave policy, launch options and fixtures, and the marker
  parser (`Markup/`: the spans of a line and the fenced code blocks of a note, as UTF-16 ranges the editor applies
  directly) and the rules for the keys that edit it (`ListEditing`, `InlineEditing`: what Return, Tab, ⇧Tab, ⇧⌘L, ⌘B
  and a click on a checkbox change, as a `TextEdit`) and the attachments (`Attachments/`: the token line
  `[[attachment:<id>]]`, the `attachments` table and the copied files under `<data directory>/attachments/<id>/`, the rules
  of the keys and the paste around a token, and the text that a copy writes). It builds and tests with plain
  `swift test` on macOS and on Linux.
- **`Packages/ScratchCode`** is a second Swift package, also with no AppKit or SwiftUI imports, and the only one with a
  third-party dependency: tree-sitter (`docs/decisions/0007-tree-sitter.md`, which lists every package, its version and
  its licence). It holds what is about code and nothing about notes: `CodeLanguage` (the 17 languages, their fence names,
  aliases and labels), `Highlighter` (text and a language in, `HighlightToken`s out, as UTF-16 ranges, nil over the cap
  of 5,000 lines or 300,000 units; and the share of a parse that is an error), and `CodeDetector` (is a text of two lines
  or more code, and which language: offline, deterministic, and "prose" when unsure). `ScratchCore` does not depend on
  it, so the core stays Foundation-only and its tests stay fast; the highlight queries are a resource bundle that the
  app carries (`scripts/check-release-zip.sh` checks that it does).
- **`App/`** is the thin AppKit shell: window, sidebar, editor view. It maps core values to UI and UI events to core
  calls. Logic found in the shell that could live in the core is a refactoring target. The app project is generated
  by XcodeGen from `App/project.yml`, and the generated project is not committed.
- **`CSQLite`** is a system-library target inside the package. Its module map links `sqlite3` and has no `pkgConfig`,
  so macOS builds link the system SQLite and never a Homebrew copy.

**The rule:** App depends on Core and Code, never the other way round. Core and Code must not import AppKit or SwiftUI,
and Core does not depend on Code. The Linux CI job builds both packages, and neither framework exists on Linux, so a
forbidden import fails the build.

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
- **Code blocks are drawn from attributes, and coloured off the main thread** (`docs/features/code.md`).
  `MarkupStyler` gives the lines of a fenced block (from `CodeBlockIndex`) their indent and the fence lines their 6 pt
  height and null glyphs, and `MarkupLayoutManager` draws the tint and the language label behind and over them. It then
  asks `CodeBlockStyler` to colour the blocks it styled or that an edit changed:

  ```
  MarkupStyler -> CodeBlockStyler.blocksDidChange (a request: the code, its fence name, a hash)
    -> private serial queue: CodeDetector (a fence with no name) and Highlighter.tokens (ScratchCode)
    -> main thread, when the run loop is next about to wait: the result is applied to every block that still holds the
       same fence name and code (otherwise it is dropped), as temporary attributes of the layout manager
  ```

  A colour is never a character and never an attribute of the text, so storage, copy and search never see it, and a
  keystroke in a block keeps the colours of its line until the new result replaces them. A result is for a text, not a
  place, so a result for text that was edited since is dropped and never lands on newer text.
- **The queries are warmed up after the first frame, and the label has its room.** `AppDelegate` asks
  `SessionCoordinator.warmUpHighlighting()` once the frame is out, which reads the notes that were open in tabs on the
  storage queue (the launch itself reads the active note only) and hands them to `CodeBlockStyler.warmUp`: on the highlight queue, one language at a time, `Highlighter.prepare` compiles the query of
  each language that their fences name, so the first block in it is not coloured 240 to 270 ms late. The first line of code of
  a block with a label has a tail indent for the label (`MarkupAppearance.firstCodeLineStyle`), which `MarkupStyler` keeps
  current (`CodeBlockStyler` tells it when a label is written), so the label never covers code.
- **A paste is a plain paste first, and a second edit wraps code in a fence.** `NoteTextView.paste` inserts the
  pasteboard's text as always. When it has read the paste, `PasteClassifier.wrap` asks `CodeDetector` about it (never for
  one line, a paste into code, or one with a fence line in it) and answers a `TextEdit` that puts the pasted text between
  two fences, and the highlighter starts on the colours of that block at once (`CodeBlockStyler.prefetch`, on its queue).
  On a later turn of the main run loop, once the undo group of the paste has closed, the same edit is applied with
  `apply`: the paste and the wrap are two undo steps, and the block finds its colours when it appears. The label menu (`CodeBlockMenu`) is the same kind of edit on the fence lines, one undo step each.
  The `paste-code` signpost runs from the paste until the colours are on screen.
- **An attachment is a token line that is drawn over, and its file is kept by reference**
  (`docs/features/attachments.md`, `docs/decisions/0008-attachments.md`). The note's text holds the line
  `[[attachment:<id>]]` and nothing else of the attachment, so storage, search and autosave are the path above. The styler
  gives a token line null glyphs (all but the first character, which keeps the line a fragment of its own) and a height that
  fits its preview or chip, and `MarkupLayoutManager` draws it from an `AttachmentMark` that holds everything it needs:

  ```
  paste, drop or the paperclip -> NoteTextView.readSelection / attachFiles (the order of spec §6.5)
    -> AttachmentImporter: the row (AttachmentStore.register) on the main thread, a token line in the text (one undo step)
    -> storage queue: AttachmentStore.copyIn / writeIn (a temporary file renamed onto the name); then markCopied on main
  MarkupStyler (a token line) -> AttachmentCatalog (the rows, read a batch of paragraphs at a time)
    -> AttachmentPreviews: ImageIO thumbnails on a private serial queue -> main thread: the display of that line is invalidated
  ```

  The editor's selection delegate and `deleteBackward`/`deleteForward` ask `AttachmentEditing` (core) to keep a token whole,
  a double-click opens the stored file, a drag out hands the file's URL to the pasteboard, and `writeSelection` asks
  `AttachmentCopying` for the text of a copy (file names for tokens) and writes the file itself when the selection is one
  token. **A stored file is removed by reference and never by count**: `ScratchStorage.deletePermanently` and `purge` remove
  the notes and then ask `AttachmentStore.removeUnreferenced` about the ids that were in them, and the launch sweep
  (`SessionCoordinator.sweepUnreferencedAttachments`) removes unreferenced attachments older than 24 hours. Both read every
  stored body (`NoteStore.referencedAttachmentIDs`) in the same transaction as the removal, so deleting a token and pressing
  ⌘Z always brings the file back.
- A write that fails never costs text: `UnsavedNotes` (ScratchCore) keeps the note with the owner's text until a write of
  it succeeds, `persistNow()` and every save write those notes again, and `SessionCoordinator.loadNote` shows a note
  from there when it is opened again (`docs/features/autosave-and-restore.md`, "Write errors are not silent").
- A cursor or scroll change takes the same path through `EditorViewController.onViewStateChange`, but writes only the
  session (the open note's id, selection and scroll position), and does not re-read the note list.
- Quitting and deactivating skip the timer: `AppDelegate` calls `SessionCoordinator.persistNow()`, which runs the same
  save at once and waits until the storage queue is empty. Opening another note does the same for the note it leaves.
- Launching reads the session, then what every saved tab needs of its note without the body (`NoteStore.tabInfo`: one
  query; a tab whose note is gone or deleted is dropped) and the active note in full (`SessionCoordinator.restoredTabs`),
  before the window shows: one body is read, whatever the other tabs hold (spec §7). The note list is read on the storage
  queue after that (`SessionCoordinator.restore()`), and so are the other tabs' bodies, for the query warm-up, once the
  first frame is out.
- A launch measures itself: `LaunchTimer.mark` records the phases `main`, `storage`, `restore` and `window` as the launch
  goes (a clock read each), the main run loop's first idle moment after the window is shown marks `firstFrame`, and only
  then `LaunchTimer.finish` hands the marks to its own utility queue, which appends the record to `launch-times.json`
  (`LaunchLog`) and writes it. Help > Launch Times… shows that log (`docs/features/launch-times.md`).
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
- **The copy of an attachment runs on the storage queue**, after the row was written on the main thread, so inserting a
  50 MB file returns to the run loop at once and `persistNow()` (and so quitting and a change of tab) waits for a copy that
  is under way. **One private serial queue decodes previews** (`io.github.ldellisola.Scratch.previews`, QoS user-initiated,
  `AttachmentPreviews`, ImageIO thumbnails in the order the styler asked, so the images on screen come first); the main
  thread only invalidates the display of the lines of an image that arrived. A preview or a copy never runs on the main
  thread, and nothing they run waits for the main thread.
- **One private serial highlight queue** (`io.github.ldellisola.Scratch.highlight`, QoS user-initiated, made by
  `MarkupStyler` for `CodeBlockStyler`) runs `CodeDetector` and `Highlighter` for the code
  blocks, one request at a time, so highlighting never runs on the main thread and never competes with itself. `Highlighter` is thread-safe (a parser for each call, a compiled query for each language, shared behind a
  lock). The main thread only writes the colours back, at most 8 ms at a time. The one detection that runs on the main
  thread is a paste's (`PasteClassifier`): it reads at most 300 lines and takes 3 to 12 ms for 500 lines.
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
- **Signposts** (`Signposts.editor`, subsystem `io.github.ldellisola.Scratch`, category `editor`) mark three intervals that
  the performance tests read: `keystroke` (`NoteTextView.keyDown`), `switch-note` (`SessionCoordinator.open`) and
  `paste-code` (`NoteTextView.paste`). The first two end when the main run loop is next about to wait (`RunLoopIdle`), so
  they include the layout and drawing that TextKit does after the work returns. `paste-code` stays open until the colours
  of the block that the paste made are on screen, because they are written in later turns on purpose.
- **`FrameMonitor`**, started only by `-ScratchFrameMonitor <path>`, scrolls the note by itself and records the main
  thread's work per frame. It observes the main run loop and the editor's clip view and does not touch the data flow.
- **`IdleMonitor`**, started only by `-ScratchIdleMonitor <path>`, reads the process's CPU time (`getrusage`) 3.5 seconds
  after launch and again 5 seconds later, counts the passes of the main run loop in between, and writes the percentage of
  one core and the wake-ups. Like `FrameMonitor` it observes and does not touch the data flow.
- **`LaunchReference`** is an application target of its own (`App/LaunchReference`, an empty window with a TextKit 1 text
  view) that the performance tests launch to learn what a launch costs on the CI runner whatever the app does. Nothing but
  `ScratchPerfTests` depends on it, and it is not in the `Scratch` scheme, so it is never in the app or in a release.
- The performance tests, their metrics and the CI check: AGENTS.md ("Performance"),
  `docs/decisions/0003-ci-performance-checks.md` and `docs/decisions/0009-performance-at-1-0.md`.
