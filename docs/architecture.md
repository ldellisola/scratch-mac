# Architecture

The design is in [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](superpowers/specs/2026-10-19-scratchpad-design.md),
section 9.2. This page records how the code is actually organised. Update it when the structure changes.

## Modules and the dependency rule

```
App (AppKit shell)  ──depends on──▶  ScratchCore (Foundation + CSQLite)  ──links──▶  system SQLite
```

- **`Packages/ScratchCore`** is a Swift package with no AppKit or SwiftUI imports. It holds everything rule-based:
  the note model, storage, session state, autosave policy, launch options and fixtures. Later plans add the marker
  parser, list editing rules, paste classification, copy-out, code detection and search. It builds and tests with
  plain `swift test` on macOS and on Linux.
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
  -> SessionCoordinator.saveNow() on the main thread: copies the changed Note and the SessionState
  -> storage queue: NoteStore.save, SessionStore.save, then NoteStore.summaries()
  -> main thread: SessionCoordinator.didReadSummaries -> SidebarViewController.reload
```

- A cursor or scroll change takes the same path through `EditorViewController.onViewStateChange`, but writes only the
  session (the open note's id, selection and scroll position), and does not re-read the note list.
- Quitting and deactivating skip the timer: `AppDelegate` calls `SessionCoordinator.persistNow()`, which runs the same
  save at once and waits until the storage queue is empty. Opening another note does the same for the note it leaves.
- Launching reads the session, then only the note of the active tab, before the window shows. The note list is read on
  the storage queue after that (`SessionCoordinator.restore()`).
- A click on a sidebar row goes `SidebarViewController.onSelect` -> `SessionCoordinator.open(_:)`. The toolbar's new
  note button goes `ToolbarController.onNewNote` -> `SessionCoordinator.newNote()`.
- The sidebar never shows a new note that nobody has used: the coordinator filters it out of the list, and deletes its
  row when the user leaves it untouched (`NoteStore.discard`).

## Threading

- **The main thread** runs AppKit, `SessionCoordinator` (it is `@MainActor`, like the whole app target: default actor
  isolation is MainActor) and the `Autosaver`'s timers, because `DispatchAutosaveScheduler` is created on the main
  queue. The autosaver's save closure therefore runs on the main thread, where it may touch the editor.
- **One serial storage queue**, `io.github.ldellisola.Scratch.storage` (QoS utility), does every autosave write and the
  note list reads that follow. Writes go in one order, and typing never waits for the disk. The coordinator hands it
  copies (`Note` and `SessionState` are values), never the editor.
- **`Database`** serialises every SQLite call with a mutex, so the main thread may also call the stores directly. It does
  so for the rare, small calls: restoring the session, creating a note, loading the note that is opened and
  discarding an untouched one. They wait for a write that is running.
- **`persistNow()` and `open(_:)` wait for the storage queue on purpose** (`storageQueue.sync {}`), so that they never
  leave a write behind that a later read could miss. They run on the main thread only. Nothing the queue runs ever waits
  for the main thread (it hands results over with `DispatchQueue.main.async`), so this cannot deadlock.
- **The coordinator owns its `Autosaver`**, and the autosaver does not keep itself alive: a dirty one that is released
  skips its pending save. `AppDelegate` keeps the coordinator for the app's lifetime, and the save closure holds the
  coordinator weakly.
- A note list read carries a number, and only the newest read is shown, so a slow, stale list never replaces a newer one.
