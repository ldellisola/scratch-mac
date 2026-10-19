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

Not written yet. Plan 1, Task 8 describes the path from keystroke to disk (editor, session coordinator, autosaver,
storage queue, stores) here.

## Threading

Not written yet. Plan 1, Task 8 records the threading model here.
