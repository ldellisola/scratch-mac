# AGENTS.md

Entry point for every agent working on this repository. Read it first. Keep it short and current: an out-of-date
AGENTS.md is a bug, so update it in the same change that makes it wrong.

## 1. What Scratch is

Scratch is a native macOS 26 scratchpad for one person on one Apple Silicon Mac. It is a window that is always ready
to type in, never asks to save, restores everything on relaunch, and adds just enough structure (bullets, checkboxes,
bold, auto-highlighted code) for snippets, quick notes and todo lists. Pasted text always takes the note's font.
Copied text always comes out as plain text. The app is developed only by AI agents.

- Design (the source of truth for behaviour): [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](docs/superpowers/specs/2026-10-19-scratchpad-design.md)
- Roadmap (six plans, one release each): [`docs/superpowers/plans/2026-10-19-roadmap.md`](docs/superpowers/plans/2026-10-19-roadmap.md)
- Latest plan: [`docs/superpowers/plans/2026-10-22-plan-5-attachments.md`](docs/superpowers/plans/2026-10-22-plan-5-attachments.md),
  in progress for 0.5.0 (attachments: images and files pasted, dropped or attached, shown inline, opened, dragged out and
  copied; plus the 0.4.0 follow-ups). Its Tasks 1 to 5 are done: titles skip fence and attachment lines, `AttachmentID`
  and `AttachmentToken` exist, the schema is version 3, `AttachmentStore` keeps the files and removes them only when no
  note names them, the 0.4.0 follow-ups in ScratchCode are in, a token line is drawn as a preview or a chip, and files and
  images are pasted, dropped or attached with the paperclip and kept whole when selected or deleted. Plan 4, done and released as 0.4.0 (code: highlighting, code
  blocks, paste classification, the language label menu, and bold at word boundaries):
  [`2026-10-21-plan-4-code.md`](docs/superpowers/plans/2026-10-21-plan-4-code.md). Plan 3, released as 0.3.0 (the formatting):
  [`2026-10-20-plan-3-formatting.md`](docs/superpowers/plans/2026-10-20-plan-3-formatting.md). Plan 2, released as 0.2.0:
  [`2026-10-20-plan-2-notes-and-tabs.md`](docs/superpowers/plans/2026-10-20-plan-2-notes-and-tabs.md). Plan 1, released
  as 0.1.0: [`2026-10-19-plan-1-walking-skeleton.md`](docs/superpowers/plans/2026-10-19-plan-1-walking-skeleton.md).

## 2. Module map

```
Packages/ScratchCore/             Foundation-only Swift package. Builds and tests on Linux and macOS.
  Sources/CSQLite/                module map for the system SQLite library (no pkgConfig, on purpose)
  Sources/ScratchCore/Notes/      Note and NoteID: the note model, derived title and preview (a title and a preview skip
                                  blank lines, fence lines and attachment lines). NoteSummary: a sidebar
                                  row (`deletedAt` is set for Recently Deleted rows). NoteStore: reads and writes the
                                  notes table (pinned first, newest edit first), searches it (`search`), and pins,
                                  deletes, restores and purges notes (`setPinned`, `delete`, `restore`,
                                  `deletePermanently`, `deletedSummaries`, `purge`), and says which attachments the
                                  stored bodies name (`referencedAttachmentIDs`). SearchQuery: typed text to an
                                  FTS5 MATCH expression
  Sources/ScratchCore/Attachments/ AttachmentID (a lowercase UUID, like NoteID) and AttachmentToken: the line
                                  `[[attachment:<id>]]` that stands for an attachment in a note (`line(for:)`,
                                  `id(inLine:)`: the whole line and nothing else, `ids(in:)`: every token of a text, in
                                  order, `lineRanges(in:within:)`: the token lines a UTF-16 range touches,
                                  `referencedIDs(in:)`: every id whose token is anywhere in a text, which is what keeps a
                                  file). Attachment (a row: the file's name, type, size and whether its copy is in
                                  place) and AttachmentStore (the `attachments` table and the copied files under
                                  `<data dir>/attachments/<id>/<file name>`: `register`, `copyIn`, `writeIn`, `attachment`,
                                  `attachments`, `fileURL`, and the removal by reference `removeUnreferenced` and
                                  `sweep`) and AttachmentEditing (what the keys and the pasteboard do around a token line,
                                  as `TextEdit`s and `KeyAction`s: `snappedSelection` keeps the caret and a selection from
                                  ending inside a token, `deletion` is Backspace and Delete next to one, `removal`,
                                  `insertion`: the token lines of a paste, each on a line of its own; `token(touching:)`
                                  reads at most 51 units each way of a position)
  Sources/ScratchCore/Session/    SessionState and TabState (what a relaunch restores: the tabs, the active one, the
                                  font size, and each tab's cursor and `scrollAnchor`), SessionStore (JSON under key
                                  "state"), TabList (the tab rules: open, close, select, with TabOpening and
                                  TabClosing as results), FontSize (13 pt, 9 to 32, steps of 1), TextOffset (clamps a
                                  saved cursor offset to a Character boundary)
  Sources/ScratchCore/Sidebar/    SidebarSections (splits the note list into Pinned, Today, Yesterday, Earlier and
                                  Recently Deleted by calendar day), NoteTimeLabel (a row's "10:42" or "Oct 14")
  Sources/ScratchCore/Autosave/   Autosaver (decides when unsaved changes are written: 300 ms after the last change,
                                  at most 1 s after the first, no repeating timers) and the AutosaveScheduler clocks it
                                  runs on: DispatchAutosaveScheduler (production), ManualAutosaveScheduler (tests);
                                  UnsavedNotes (the notes whose write failed, kept with the owner's text until a write
                                  succeeds: thread-safe, the newest copy of a note wins)
  Sources/ScratchCore/Storage/    Database (thread-safe SQLite wrapper with transactions), Connection (the C API calls),
                                  SQLValue and Row, Schema (version 3, with the FTS5 index `notes_fts`, the
                                  `attachments` table, the migration rule, and SchemaError for a database from a newer
                                  Scratch), ScratchStorage (opens
                                  the data directory and its stores, `notes`, `session` and `attachments`; refuses a
                                  fixture on the real directory; `deletePermanently` and `purge`, which remove a note
                                  and then the files nothing names any more; its
                                  `database` is public so that tests can make writes fail, see section 7)
  Sources/ScratchCore/Launch/     LaunchOptions: the -Scratch* launch arguments (section 3), AppearanceOverride
  Sources/ScratchCore/Markup/     MarkupParser (a line, or a whole note, to `MarkupSpan`s: bullets, checkboxes, bold at
                                  word boundaries (docs/decisions/0006), inline code and links, as UTF-16 `NSRange`s),
                                  MarkupSpan and MarkupKind, LinkScanner
                                  (the `http(s)://` URLs of a line), FenceScanner (the fenced code blocks, inside which
                                  nothing is formatting), TextLines (internal: line splitting and white space over UTF-16
                                  units). The editing rules answer an action with a `TextEdit` (a range, its
                                  replacement and the selection afterwards): ListEditing (Return, Tab, ⇧Tab, ⇧⌘L and a
                                  click on a checkbox) and InlineEditing (⌘B). They read only the paragraphs that cover
                                  the selection (`ParagraphLines`, internal: those lines with document offsets, and how
                                  a selection moves when they change). The editor's styling reads CodeBlockIndex (the
                                  fenced blocks of a note, carried over each edit and scanned again only when an edit
                                  touches a fence line; `intersects` says whether a range holds a block), EditMapping
                                  (where positions go when text is replaced) and `MarkupParser.mayHaveSpans` (a cheap
                                  test that skips the parse of a line with no marker)
  Sources/ScratchCore/Fixtures/   Fixture (empty, typical, huge-note, many-notes, recently-deleted, formatting, code,
                                  attachments) and FixtureContent, their notes, session and attachments (rows and the
                                  bytes of their files)
  Tests/ScratchCoreTests/         Swift Testing, one test file per source file
Packages/ScratchCode/             Swift package, no AppKit, builds and tests on Linux and macOS. Wraps tree-sitter, the one
                                  third-party dependency (docs/decisions/0007). ScratchCore does not depend on it.
  Sources/ScratchCode/            CodeLanguage (the 17 languages: fence names, aliases, labels), HighlightKind and
                                  HighlightToken (UTF-16 ranges), Highlighter (`tokens(in:language:)`, nil over the cap of
                                  5,000 lines or 300,000 units; `errorRate(of:language:)`), CaptureMapping (capture names
                                  to the eight kinds), Grammars (internal: each language's grammar and queries, and the
                                  compiled-query cache), QueryInheritance (internal: a `; inherits: <folder>` line at the
                                  top of a query brings that folder's query in first), CodeDetector (`detect(_:)`: a
                                  text of two lines or more in, a `CodeDetection` (language or nil for code of an unknown
                                  language, confidence) or nil for prose out), DetectionFeatures (internal: the lines of
                                  a text, each with its facts and its evidence, and the shapes that decide alone),
                                  LanguageSignals (internal: the idioms of each language as points), JSONShape (internal:
                                  a strict JSON validator)
  Sources/ScratchCode/Queries/    `<folder>/highlights.scm`: the 17 languages' queries, copies of the grammars' with their
                                  licences and the changes Scratch made (docs/decisions/0007), plus `javascript-jsx`;
                                  a resource bundle, read through `Bundle.module`
  Sources/GrammarPython/          the Python grammar's generated C, vendored (its README.md says why)
  Sources/GrammarPowerShell/      the PowerShell grammar's generated C, vendored in the same way
  Sources/GrammarSQL/             the SQL grammar's generated C (41 MB parser.c from the gh-pages build of its repository),
                                  vendored in the same way
  Tests/ScratchCodeTests/         Swift Testing, one file per source file, and `Samples/<fence name>.txt`, 15 to 40 lines
                                  of ordinary code for each of the 17 languages (a test resource), and `Corpus/`: the
                                  samples the detector is tuned against, in `<fence name>/` (code), `unknown/` (code of
                                  a language Scratch lacks) and `prose/` (text that must stay plain)
App/project.yml                   XcodeGen spec: targets Scratch (app), ScratchAppTests (hosted unit tests),
                                  ScratchUITests, ScratchPerfTests; schemes Scratch and ScratchPerf. The generated
                                  App/Scratch.xcodeproj is never committed.
App/Sources/                      AppKit shell (default actor isolation MainActor). main.swift and AppDelegate (launch
                                  sequence: storage, session, window, menu bar), AppEnvironment (parses the launch
                                  arguments, opens storage; isolates a hosted test run)
App/Sources/Window/               MainWindowController (one window, closing it quits), MainSplitViewController (glass
                                  sidebar item + editor area item), EditorAreaViewController (the tab strip above the
                                  editor), MainMenu (menu bar, built in code: there is no storyboard; it has the Format
                                  menu), AppCommands (the target of the app's own menu items: the tabs, pinning,
                                  attaching a file, searching and the font size), ToolbarController (sidebar button,
                                  paperclip, pin button, new note button), TitlebarPocket (hides
                                  the line macOS 26 draws under the toolbar, section 7)
App/Sources/Tabs/                 TabStripViewController (the glass tab strip: `TabStripItem`, `TabStripView`,
                                  `TabStripLayout`, `TabStripContentView`, `TabItemView`)
App/Sources/Sidebar/              SidebarViewController (the search field and the note list in the glass sidebar: an
                                  NSTableView with group headers; a click or Return opens a note, `onOpen`; `onSearch`,
                                  `onTogglePin`, `onDelete`, `onRestore`, `onDeletePermanently` and
                                  `onToggleRecentlyDeleted`), SidebarRowViews (`NoteRowCellView`, `GroupRowCellView`),
                                  SidebarTableView (Return, ⌘⌫, the click on the Recently Deleted header, the row's
                                  context menu)
App/Sources/Session/              SessionCoordinator (the tabs and which is active, autosave, restore, new note, close,
                                  pinning, delete, restore and purge, the tab titles, the launch sweep of the attachments
                                  that no note names; the one place that writes to storage; it is the editor's
                                  `AttachmentImporting`), NoteListModel (the sidebar's data: reads the note list, the
                                  search results and Recently Deleted on the storage queue, builds the sections),
                                  AttachmentImporter (makes the attachments of what is pasted, dropped or chosen: the row
                                  at once on the main thread, the copy on the storage queue, `pendingCopies`)
App/Sources/Editor/               NoteTextView (plain-text NSTextView, plain paste and copy, the font size, the note's
                                  undo manager), TextViewFactory (builds the TextKit 1 stack, docs/decisions/0001),
                                  TitleField (the optional title above the text), EditorViewController (the title field
                                  and the editor: shows a note, reports edits, cursor and scroll anchor). NoteTextView
                                  also applies the editing rules' `TextEdit`s (`apply`, one undo step), ticks a checkbox
                                  on a click (`mouseDown`), answers ⇧⌘L (`toggleChecklist`) and ⌘B (`toggleBoldMarkers`),
                                  and handles Return, Tab and ⇧Tab on list lines (`insertNewline` and the like). The markers
                                  are rendered by MarkupStyler (the text storage's delegate: styles paragraphs from the
                                  core's parser, hides and reveals markers, styles a shown note in chunks),
                                  MarkupLayoutManager (null glyphs for hidden markers and fence lines, draws bullets and
                                  checkboxes, the tinted code blocks and their labels), MarkupAppearance (fonts, colours
                                  and paragraph styles per font size, the block styles), MarkupAttributes (the
                                  `scratchMarker`, `scratchLink` and `scratchCodeBlock` attributes, `MarkerRole`,
                                  `CodeBlockMark`, `CodeBlockMetrics`, `CodeBlockColors`, `MarkupColors`), ParagraphBatch
                                  (whole paragraphs read in one call), CodeBlockStyler (colours the code of the fenced
                                  blocks with `ScratchCode`'s highlighter on a background queue and keeps each block's
                                  language label: `blocksDidChange`, `language(ofBlockAt:)`, `pendingHighlights`,
                                  `whenHighlighted`), CodeBlockParts (a block's name, code and fence lines from its range)
                                  PasteClassifier (whether a paste is code, and the edit that wraps it in a fence:
                                  `wrap`; NoteTextView asks it after every paste, `readSelection(from:)`) and
                                  CodeBlockMenu (the menu of a block's language label, with `CodeBlockAction` and
                                  `CodeBlockChoice`, and the edits its items make: `menu`, `edit`; NoteTextView opens it
                                  from a click on a label, `labelHit`, `showCodeBlockMenu`, and applies a choice,
                                  `applyCodeBlockAction`; `MarkupLayoutManager.labelRect(forBlockAt:)` is where the label is).
                                  Attachments (plan 5): AttachmentCatalog (the rows of the attachments the editor shows,
                                  read with one query per batch of paragraphs, which files are being copied or cannot be
                                  decoded: `attachment`, `fileURL`, `preload`, `markCopying`, `markCopied`, `onChange`),
                                  AttachmentPreviews (ImageIO thumbnails on a serial queue and their cache: `image(for:id:
                                  maxPixelSize:completion:)`, `request`, `cachedImage`, `onChange`), AttachmentDrawing
                                  (`AttachmentMetrics`, the sizes, and `AttachmentDrawing`, the preview, the chip and the
                                  outline), and in MarkupAttributes `AttachmentMark` (what a token line is drawn as: its
                                  kind, size, file name, icon) with the `scratchAttachment` attribute and `MarkerRole.attachment`.
                                  MarkupStyler styles a token line (`styleAttachmentLine`) and again when the catalog or the
                                  text width changes (`attachmentDidChange`, `refreshAttachmentLayout`);
                                  `MarkupLayoutManager.attachmentRect(forTokenAt:)` is where the preview is drawn.
                                  AttachmentImporting (`AttachmentSource`: a file or the bytes of an image, and the
                                  `AttachmentImporting` protocol that NoteTextView asks to make attachments, `noteID`).
                                  NoteTextView reads a paste or a drop in the order of spec §6.5 (`readSelection(from:)`,
                                  `paste`, `attachmentSources(from:)`, `insertAttachments`, `acceptsDrop`, `performDrop`),
                                  opens the paperclip's panel (`attachFiles`, `presentOpenPanel`), keeps a token whole
                                  (`snappedSelection`, which the editor's selection delegate asks, and `deleteBackward` and
                                  `deleteForward`)
App/Sources/Support/              AccessibilityID (also compiled into the UI test targets), Signposts (the `keystroke`,
                                  `switch-note` and `paste-code` intervals the performance tests read), RunLoopIdle
                                  (runs work when the main run loop is next about to wait: after the frame is drawn, and
                                  with `order: afterMeasurementsOrder` after the signposts end), FrameMonitor
                                  (`-ScratchFrameMonitor`: scrolls the note itself and measures the frames),
                                  DebugStateElement (the invisible `debug.state` element that UI tests read the font
                                  size, scroll anchor, scroll offset, pending paste work and the attachments of the note
                                  (id and `copied`) from, in isolated launches only)
App/Resources/                    Assets.xcassets (placeholder app icon, the colours `CodeText` and `CodeBackground` of
                                  inline code and `CodeKeyword`, `CodeString`, `CodeComment`, `CodeNumber`, `CodeType`,
                                  `CodeFunction`, `CodeAttribute` and `CodePreprocessor` of highlighted code, each with a
                                  light and a dark variant)
App/Tests/ScratchAppTests/        hosted XCTest unit tests, run inside the app (NoteTextViewTests, LargeInsertTests: a
                                  50,000-line paste returns within 500 ms, FrameMonitorTests, EditorViewControllerTests:
                                  the title, font size, per-note undo, read-only and scroll anchor, TitlebarPocketTests,
                                  MarkupStylerTests: bullets, checkboxes, bold, code and links render, markers hide and
                                  reveal, fenced blocks are literal, a long note is styled in chunks, CheckboxTests: a
                                  click ticks a box, ⇧⌘L, the drawn symbol, the Format menu, ListKeyTests: Return, Tab,
                                  ⇧Tab and ⌘B, LinkTests: ⌘-click opens a link, the pointing hand, SaveFailureTests: a
                                  coordinator on a failing disk keeps and retries the notes it could not write, and
                                  the emptied-note rules, CodeBlockStylerTests: a fenced block is tinted with hidden
                                  fences, indented lines, colours and a label, CodeBlockPartsTests, CodePasteTests: a
                                  paste of code is wrapped in a fence on the next turn, prose, a paste into code and one
                                  with a fence line stay plain, `PasteClassifier.wrap`, CodeBlockMenuTests: the label
                                  menu, its edits and undo steps, the label's hit test, a block typed by hand,
                                  AttachmentRenderingTests: a token line's null glyphs and height, an image scaled to the
                                  width and 240 pt, the file chip, the Copying and Missing attachment chips, the pixels of
                                  a preview, a change of the text width, AttachmentPasteTests: files, images and text
                                  pasted in the order of spec §6.5, one undo step, a 50 MB file, drops,
                                  AttachmentEditingTests: the caret and a selection around a token, Backspace and Delete,
                                  the paperclip; AttachmentTestHost is what they share)
App/Tests/ScratchUITests/         XCUITest: UITestSupport launches the app on an isolated data directory (and relaunches
                                  it on the same one); LaunchUITests, PersistenceUITests (force-kill, quit, cursor),
                                  SidebarUITests, TitleUITests (title, font size, scroll position), TabsUITests (the
                                  tab strip, opening, closing and switching tabs), DeleteUITests (delete, Recently
                                  Deleted, restore, the purge), ChecklistUITests (⇧⌘L from the keyboard and its undo),
                                  FormattingUITests (a list, a checklist and bold typed with real keys, and copy),
                                  CodePasteUITests (⌘V of code is fenced, ⌘Z and ⌘Z again, an email stays plain),
                                  AttachmentUITests (⌘V of a file survives a relaunch, Backspace twice and ⌘Z bring it
                                  back), ScreenshotTests (one test per screenshot, section 3)
App/Tests/ScratchPerfTests/       the performance tests (UI tests in the Release build, ScratchPerf scheme): LaunchPerfTests,
                                  EditorPerfTests (keystroke, scrolling, switching notes), CodePastePerfTests (a paste of
                                  500 lines of code until its colours are on screen), PerfSupport. They share
                                  UITestSupport and AccessibilityID with the UI tests
perf/                             budgets.json (the budgets CI enforces, in milliseconds) and baseline.json (CI's own
                                  numbers, the slowest of many runs: docs/decisions/0003)
VERSION                           the app's version, MAJOR.MINOR.PATCH on one line. It names the release and feeds the
                                  app's marketing and build versions (`make project`). Bump it with every change to
                                  App/ or Packages/ (section 6, Releases)
scripts/                          install-swift-linux.sh (toolchain), session-setup.sh (SessionStart hook),
                                  ci-summary.py, publish-ci-results.sh, ci-wait.sh, ci-fetch.sh (the ci-results loop,
                                  section 4), lib-ci-results.sh (shared by those), name-screenshots.py (names the
                                  exported screenshots), perf-extract.py (a ScratchPerf result bundle to numbers),
                                  perf-check.py (numbers against baseline and budgets), check-version-bump.sh (a change
                                  to App/ or Packages/ needs a VERSION greater than main's), release-notes.sh (the
                                  release notes footer with the version filled in), check-release-zip.sh (unpacks a
                                  release zip, checks the app in it and prints its sizes), check-release-dmg.sh (attaches a release DMG
                                  read-only and checks the window and the app in it), tests/ (their tests, the DMG
                                  check's against stubs of hdiutil, codesign and lipo)
.github/workflows/ci.yml          CI. Job `linux`: lint, core tests, script tests, version bump check. Job `macos`:
                                  XcodeGen, core tests on macOS, app build and app tests, screenshots, performance tests
                                  and their check, the release zip and the release DMG. Both publish to `ci-results`.
.github/workflows/release.yml     the release: a merge to main that changes App/, Packages/ or VERSION builds
                                  `make release-zip release-dmg` and publishes a GitHub Release `v<VERSION>` with the
                                  zip and the DMG (section 6, Releases)
README.md                         what Scratch is, how to install it, the shortcuts, and the screenshots. Keep its
                                  feature list and release table current (section 6)
docs/architecture.md              module boundaries (App, ScratchCore, ScratchCode), data flow, threading
docs/release-notes-footer.md      the install and update steps (the DMG first, the zip as the alternative), put at the
                                  top of every release's notes (`scripts/release-notes.sh` replaces its `<version>`
                                  placeholders)
docs/features/                    one short behaviour spec per feature: paste-and-copy.md, autosave-and-restore.md,
                                  title-and-font-size.md, tabs.md, sidebar.md, recently-deleted.md, formatting.md, code.md,
                                  attachments.md (more as features land)
docs/images/                      the README's screenshots (window-light, window-dark, formatting, code, search,
                                  recently-deleted): copies of the `screenshots/` that CI published for a release commit
                                  (`scripts/ci-fetch.sh`, section 4: typical-light, typical-dark, formatting-light,
                                  code-light, search-light, recently-deleted-light). They
                                  change only when someone replaces them, so refresh them when a plan visibly changes
                                  the UI
docs/decisions/                   numbered decision records: 0001 (the editor uses TextKit 1, with the measurements and the
                                  marker hiding prototypes), 0002 (releases are ad-hoc signed), 0003 (what the CI
                                  performance check compares), 0004 (a new note opens at the end of the tab strip, and
                                  a note the owner empties is kept), 0005 (every release carries a DMG next to the zip),
                                  0006 (bold needs word boundaries), 0007 (tree-sitter: the packages, their versions and
                                  licences, and how to add a language)
docs/superpowers/                 design spec and plans
```

This map lists what exists. Add new directories and files to it as they land. The target layout is the File Map in
the current plan.

## 3. Commands

Run them from the repository root. `[linux]` means it also runs in the Linux cloud sessions. Everything else needs
macOS and runs on GitHub's Macs.

- `make core-test` `[linux]`: build and run the ScratchCore tests, then the ScratchCode tests (the first run fetches
  tree-sitter and its 14 grammar packages from GitHub, and compiles them and the three vendored grammars, a few minutes).
- `swift test --package-path Packages/ScratchCore --filter <name>` `[linux]`: run matching tests only (the same for
  `Packages/ScratchCode`).
- `make lint` `[linux]`: `swift format lint --strict` over `Packages` and `App`. Must exit 0.
- `make format` `[linux]`: rewrite files to the house format (`.swift-format`).
- `make script-test` `[linux]`: test the scripts in `scripts/` (the ci-results loop, `perf-check.py`,
  `perf-extract.py`, `check-version-bump.sh`, `release-notes.sh` and `check-release-dmg.sh`). Each test file ends with an
  `all ... passed` line.
- `scripts/check-version-bump.sh <base-ref>` `[linux]`: exit 1 when the branch changed App/ or Packages/ since
  `<base-ref>` without a `VERSION` that is greater than `<base-ref>`'s (compared number by number: 0.10.0 is greater than
  0.9.0), or when `VERSION` is not MAJOR.MINOR.PATCH. CI runs it with `origin/main`.
- `scripts/release-notes.sh <version>` `[linux]`: print `docs/release-notes-footer.md` with every `<version>` replaced.
- `make ci-wait SHA=<sha> [JOBS="linux macos"]` `[linux]`: wait for CI to publish results for a commit and print them.
  See section 4 for how to read the outcome.
- `scripts/ci-fetch.sh <sha> <dest>` `[linux]`: copy a commit's published CI results (summaries, log tails,
  screenshots) into `<dest>`.
- `scripts/install-swift-linux.sh` `[linux]`: install the Swift version in `.swift-version` into `/opt/swift`. Does
  nothing when it is already installed. The `SessionStart` hook runs it in cloud sessions.

- `make project` `[macOS]`: generate `App/Scratch.xcodeproj` from `App/project.yml` (needs `brew install xcodegen`).
- `make app-build` `[macOS]`: build the Debug app into `build/DerivedData`.
- `make app-test` `[macOS]`: build, then run the hosted unit tests and the UI tests. Result bundle:
  `build/results/app.xcresult`. Each test has a 2 minute limit.
- `make screenshots` `[macOS]`: run `ScreenshotTests` only and write `build/screenshots/<name>.png` for `typical-light`,
  `typical-dark`, `empty-light`, `huge-note-light`, `search-light` (typical, with "kube" typed in the search field),
  `recently-deleted-light` (the `recently-deleted` fixture, the section expanded), `formatting-light` and
  `formatting-dark` (the `formatting` fixture: every marker once, the caret at the top of the note), and `code-light` and
  `code-dark` (the `code` fixture: a block each for five languages and one with no fence name, coloured). These are the
  names in the Makefile's `SCREENSHOT_NAMES`, and each is one test in `ScreenshotTests`. The result
  bundle is `build/results/screenshots.xcresult`, and the files as exported are in `build/screenshots/raw`. `make
  app-test` skips these tests.
- `make perf` `[macOS]`: run the performance tests (the `ScratchPerf` scheme, Release build) into
  `build/results/perf.xcresult`. Turn that into numbers with `python3 scripts/perf-extract.py
  build/results/perf.xcresult <out.json>`, and compare them with `python3 scripts/perf-check.py --results <out.json>
  --baseline perf/baseline.json --budgets perf/budgets.json` (CI does both, section 4).
- `make perf-baseline` `[macOS]`: run `make perf` and write its numbers to `perf/baseline.json`. Do not use it to
  update the baseline CI compares with: that is the slowest of at least three CI runs (docs/decisions/0003).
- `make run FIXTURE=<name>` `[macOS]`: build the app and open it on a fixture in a throwaway data directory.

- `make release-zip` `[macOS]`: build the Release app into `build/release/Scratch.app`, zip it to
  `build/release/Scratch-<VERSION>.zip`, and check what is in the zip (`scripts/check-release-zip.sh`: version and build
  version, bundle identifier, arm64 only, valid ad-hoc signature, ScratchCode's highlight queries in the app; it prints the
  sizes of the zip, the app and the executable). CI runs it on every push, and the release workflow runs it to make the
  file it publishes.
- `make release-dmg` `[macOS]`: after `make release-zip` (it runs that first when `build/release/Scratch.app` is not
  there), copy that app with `ditto` into a staging folder with an `Applications` symlink, and make
  `build/release/Scratch-<VERSION>.dmg` from it (`hdiutil create`, UDZO, volume "Scratch <VERSION>", tried up to three
  times, because `hdiutil` fails now and then with "Resource busy" on GitHub's Macs). `scripts/check-release-dmg.sh`
  then attaches it read-only and checks it: the window holds `Scratch.app` and `Applications` only, the versions, the
  bundle identifier, arm64 only, a signature that verifies and is ad hoc. It always detaches again. CI runs it as its
  own step after `release-zip`, and the release workflow runs both to make the two files it publishes
  (docs/decisions/0005).

### Launch arguments

The app reads these flags (`LaunchOptions`) and ignores every other argument. UI tests, screenshots and benchmarks
always pass `-ScratchDataDir`, so they never touch real data.

| Flag | Value | Effect |
|---|---|---|
| `-ScratchDataDir <path>` | any path | use `<path>` instead of `~/Library/Application Support/Scratch` |
| `-ScratchFixture <name>` | `empty`, `typical`, `huge-note`, `many-notes`, `recently-deleted`, `formatting`, `code`, `attachments` | delete the database and the `attachments` folder in the data directory and seed that fixture |
| `-ScratchAppearance <light\|dark>` | `light` or `dark` | force the appearance |
| `-ScratchFrameMonitor <path>` | any path | 3.5 s after launch scroll the note by itself for 5 s, and write the frame times, as JSON, to `<path>` (performance tests) |

A fixture without `-ScratchDataDir` runs in a new `Scratch-<uuid>` directory under the temporary directory. A fixture
is refused on the real data directory (`StorageError.fixtureRequiresIsolatedDirectory`), also when
`-ScratchDataDir` spells that directory differently, for example with `..` or through a symbolic link.

## 4. How to verify a change

1. Write or update the test first and watch it fail for the right reason.
2. `make core-test` and `make lint`, both green.
3. If the change touches behaviour, update the matching `docs/features/*.md` and make sure a test references it.

### Performance

`make perf` runs `App/Tests/ScratchPerfTests` (UI tests on the Release build, the `ScratchPerf` scheme). CI runs it after
the screenshots, extracts the numbers (`scripts/perf-extract.py`) and compares them (`scripts/perf-check.py`) with
`perf/baseline.json` and `perf/budgets.json`. Every metric prints `OK`, `WARN` or `FAIL`, and a `FAIL` fails the job.
The `macos` job's folder in `ci-results` has `perf/report.md` (the table), `perf/results.json` (the numbers),
`perf/metrics.json` (everything `xcresulttool` knew), `perf/test-summary.json` and `perf/attachments/` (screenshots of
the keystroke test before and after, and the frame report). The measurements, and why each is what it is, are in
docs/decisions/0001 and 0003. What to know when one fails or changes:

- **The metrics.** `launch_ms`: `XCTApplicationLaunchMetric()`, the median of 10 launches. `keystroke_ms`: the
  `keystroke` signpost, `NoteTextView.keyDown` until the main run loop is idle, one character per iteration typed about
  a third into the huge note. `switch_small_ms` and `switch_huge_ms`: the `switch-note` signpost, from
  `SessionCoordinator.open` until the note is on screen. `scroll_frame_ms`: the median CPU time of the main thread per
  frame while the app scrolls the huge note by itself (`FrameMonitor`, `-ScratchFrameMonitor`). Scrolling is measured
  with this in-app monitor, not with XCTest's scroll metrics. `paste_code_ms`: the `paste-code` signpost, from
  `NoteTextView.paste` until the colours of the block that the paste made are on screen (`CodeBlockStyler.whenHighlighted`),
  one paste of 500 lines of Swift into an empty note per iteration, each with names that the app has not coloured before.
  Budget 50 (spec §7), baseline 85.3: it is a WARN on CI (55 to 85 ms, depending on the runner: the ADR 0003 addendum),
  and a FAIL above 100 (2 x the budget), which a slow runner can reach with no change to the paste: run the job again.
  All in milliseconds and all medians.
- **The CI runner is slow and noisy.** Runs of the same build differ by up to a factor of two (the first run of a job is
  the slowest), and a launch takes about 400 ms there (Calculator takes 1 s). The baseline is therefore the slowest of
  many runs, and `launch_ms` and `switch_small_ms` are budgeted at 400 and 12 instead of the spec's 200 and 8
  (docs/decisions/0003). A failure that no
  change explains: look at `perf/report.md`, then at `perf/metrics.json`, before touching the baseline. `launch_ms` is
  the usual one: it fails above 800 ms (2 x its budget), and a slow runner gets there with no change to the app. The
  commits `a698055` and `4faafbe` changed only docs and measured 800 and 1,027 ms, with all ten launches slow in
  `perf/metrics.json`, where the same app took 677 ms on another runner (`f72e30f`). Push a new commit for another
  runner.
- **A signpost interval ends when the run loop is idle** (`RunLoopIdle`, `Signposts.beginEditorInterval`), not when the
  code returns, so that TextKit's lazy layout and drawing count. A new interval for the tests belongs there too.
- **`XCTApplicationLaunchMetric(waitUntilResponsive: true)` reports one launch of ten, or none,** on macos-26. Use the
  plain one.
- **XCTest cannot report a custom number.** `scroll_frame_ms` reaches the result bundle as an attachment named
  `scroll_frame_ms` (JSON), which `perf-extract.py` reads with `xcresulttool export attachments`.
- **Perf tests type and scroll through a 10,000-line note, so `make perf` takes about 5 minutes** and its tests have wide
  time limits (`make perf`). The keystroke test attaches `keystroke-before` and `keystroke-after`: look at them when
  its number changes, to see that the characters landed in the middle of the note.

### The CI loop

Everything that needs macOS runs on GitHub's Macs, and cloud sessions cannot download Actions artifacts. So every CI
job pushes its results to the orphan `ci-results` branch, in a folder `<sha>/<job>/`. The folder holds `summary.json`
(`sha`, `job`, `status`, `steps`, `run_url`, `finished_at`), the last 300 lines of each step's log, and for macOS the
screenshots. The branch keeps the newest 30 shas.

The `macos` job adds to its folder: `perf/` (see Performance above), `test-summary.json` (from `xcresulttool`: passed and failed counts, and each
failure's test name and message in `testFailures`), `app-test-diagnostics.txt` (every compiler warning and error of the
whole build log, which the 300-line tail would cut), `failure-attachments/` (screenshots that failed UI tests
attached) and `screenshots/<name>.png` (the key screens, `make screenshots`). A hosted test's failure message is also
in `app-test.log`: search it for `error:`. To look at a screen, fetch the commit's results and open the PNG with the
Read tool: `scripts/ci-fetch.sh <sha> build/ci-fetch/<sha>`, then `build/ci-fetch/<sha>/macos/screenshots/typical-light.png`.

1. Commit and `git push -u origin <branch>`. CI runs on every push except to `ci-results`.
2. `make ci-wait SHA=$(git rev-parse HEAD)` polls the branch and prints each job's `summary.json`. Use
   `JOBS=linux` to wait for the Linux job only.
3. `scripts/ci-fetch.sh <sha> build/ci-fetch/<sha>` copies the folder out, so `build/ci-fetch/<sha>/linux/lint.log` and
   the like can be read.

Exit codes of `scripts/ci-wait.sh`: 0 all jobs succeeded, 1 a job failed (it returns as soon as one does), 2 timed out.
`make` turns every recipe failure into exit 2, so through `make ci-wait` read the last line of output instead:
`ci-wait: PASS`, `ci-wait: FAIL` or `ci-wait: TIMEOUT`. A timeout means "not finished yet": run it again.
`CI_WAIT_TIMEOUT=540` keeps one wait under the ten-minute foreground limit (default 2700 seconds, polling every
`CI_WAIT_INTERVAL`=30 seconds). `CI_RESULTS_REMOTE` and `CI_RESULTS_BRANCH` change where results are read and written.

## 5. Conventions

- Swift 6 language mode with strict concurrency. No warnings.
- `ScratchCore` and `ScratchCode` never import AppKit or SwiftUI, and `ScratchCore` does not depend on `ScratchCode`.
  App depends on both, never the other way round. The Linux build enforces it, because AppKit does not exist there.
  Rule-based logic belongs in Core (and what is about code in ScratchCode), not in the shell.
- Swift Testing (`import Testing`, `@Test`, `#expect`) in Core. XCTest/XCUITest only in the app's test targets.
- Files are small and single-purpose, and their names say what they do. One test file per source file.
- Tests reference the `docs/features/*` section they cover. A behaviour change updates its feature doc in the same
  change.
- A decision record in `docs/decisions/NNNN-title.md` for every new dependency, every changed `[call]` in the spec and
  every budget change. Plan 4 adds one runtime dependency, tree-sitter (docs/decisions/0007); adding a language to it
  follows that record's checklist.
- Tests, screenshots and benchmarks never touch real data. They run against an isolated data directory.

## 6. Definition of done

A change is done when:

- core tests, UI tests and lint pass
- no performance budget regressed
- screenshots of any affected screen have been looked at
- the feature doc and AGENTS.md are updated if behaviour or commands changed
- the README's feature list, release table and screenshots (`docs/images/`) are current when a release changes what
  Scratch does or looks like
- a decision record exists for any new dependency or any changed [call]
- the pull request is merged, and a release is published if the app changed (§9.6)

(Spec §9.5. "§9.6" is the spec's section on merging, releases and signing.)

### Releases

A release is published for every merge to `main` that changes the app, with no human step (spec §9.6).

1. **Bump `VERSION` in the same pull request.** It is one line, `MAJOR.MINOR.PATCH` (digits only, no leading zeros): a
   patch bump for a fix (`0.1.0` to `0.1.1`), a minor bump for a feature (`0.1.1` to `0.2.0`). The `linux` CI job runs
   `scripts/check-version-bump.sh origin/main` and fails a branch that changes anything under `App/` or `Packages/`
   while `VERSION` still equals main's or is lower than it. Changes to docs, scripts, `perf/` or workflows need no bump
   and publish nothing.
   Run the check yourself with `git fetch origin main` and `scripts/check-version-bump.sh origin/main`.
2. **Merge.** `.github/workflows/release.yml` runs on the push to `main` when `App/`, `Packages/` or `VERSION` changed.
   If the tag `v<VERSION>` exists and `App/` and `Packages/` are the same as at that tag, it stops, successfully (a
   re-run). If the tag exists but `App/` or `Packages/` changed since, it **fails** with `v<VERSION> is already released
   but App/ or Packages/ changed since; bump VERSION`: that change would ship in no release, so bump `VERSION` in a new
   pull request. Otherwise it runs `make project release-zip release-dmg` on `macos-26` (Xcode 26.6) and creates the
   GitHub Release `v<VERSION>`, titled `Scratch <VERSION>`, with `Scratch-<VERSION>.dmg` and `Scratch-<VERSION>.zip`
   attached, the notes GitHub generates (what
   changed since the last release) and the install and update steps (`scripts/release-notes.sh`, from
   `docs/release-notes-footer.md`, with the version filled in) at the top.
3. **Check it.** `git ls-remote --tags origin v<VERSION>` shows the tag once the release is published, and the release
   page lists the DMG and the zip. If the workflow fails after the merge, the run's log says where. A failure of the workflow's own
   steps (a network error, say) is re-run from the Actions tab. A broken build needs a fix to `App/` or `Packages/`,
   with its own bump: the failed version was never tagged, and skipping a number does no harm.

The app is **ad-hoc signed and not notarised** (docs/decisions/0002-ad-hoc-signing.md, which amends spec §9.6): there is
no certificate and no secret to configure. The owner approves each downloaded version once in System Settings → Privacy &
Security → Open Anyway, and the release notes say so. The workflow itself can only run on `main`, so CI exercises
everything but its last step: the `macos` job runs `make release-zip` and `make release-dmg`, which build and check the
same zip and DMG. A change of `VERSION` alone also publishes a release (`release.yml` watches the file), which is how a
new kind of release file, with no change to the app, ships.

## 7. Pitfalls

- **You cannot build or run the Mac app in a Linux session.** Only `ScratchCore` and the scripts run there. Everything
  else is verified by GitHub's Macs.
- **GitHub Actions artifacts cannot be downloaded from a cloud session.** Read results from the `ci-results` branch
  (section 4). The GitHub API serves job logs when the branch has nothing for a failed run, for example when the job
  died before publishing.
- **Foreground shell commands time out after ten minutes.** The Swift toolchain download is about 1.1 GB. Run
  `scripts/install-swift-linux.sh` in the background (`nohup`, then poll its log) when it is not already installed.
- **The cloud environment must allow `download.swift.org`** for the toolchain install. Only the owner can change that.
- **`swift test` prints `Executed 0 tests` from XCTest.** That line is normal: the tests are Swift Testing. Read the
  `Test run with N tests passed` line that follows.
- **`swift format lint --strict` rejects `let a = f(), b = g()`.** Declare one variable per line.
- **Swift treats `"\r\n"` as one `Character`.** Splitting text on `"\n"` or `Character("\n")` misses CRLF line
  endings. Scan UTF-8 bytes, as `Note.swift` does, or use `Character.isNewline`.
- **`Database.execute` and `query` take exactly one SQL statement per call**, and the number of `?` arguments must
  match. Extra statements are an error, not ignored. Run a script as one call per statement. Code inside a
  `transaction { }` body uses the same `Database` (calls from other threads wait until it ends), and a nested
  `transaction` is a savepoint.
- **Schema changes are new migration steps in `Schema.swift`.** Raise `Schema.currentVersion` and add a step. Never edit
  an old step, because it has already run on real databases. Dates are stored as REAL `timeIntervalSinceReferenceDate`.
  `Schema.migrate` refuses a database whose `user_version` is newer than `currentVersion`
  (`SchemaError.newerThanSupported`, whose message is the "cannot start" alert) and changes nothing in it.
- **A change to how a note's title or preview is derived needs a migration step that works them out again.** The sidebar
  columns `display_title`, `has_title` and `preview` are written on every save and never recomputed, so the rows of notes
  nobody edits keep the old rule. Schema v3 does it for the rule "skip fence and attachment lines": it builds a `Note` from
  each row's title and body (the same code `NoteStore.save` runs), and writes only those three columns, and only when they
  differ, so `modified_at`, the list order and the search index stay as they were. A note that holds only fences and
  attachments has an empty `display_title` and is still not `isEmpty`: a note with an attachment is never an unused note.
- **An attachment line is judged as typed, a fence line too.** `Note` looks at a line before it trims it, as the styler will:
  `AttachmentToken.id(inLine:)` accepts exactly `[[attachment:<lowercase UUID>]]` and nothing else on the line, so
  `" [[attachment:…]]"` is text and a title. `AttachmentToken.ids(in:)` counts a token inside a fenced block too, because
  counting one more reference only keeps a file. `lineRanges(in:within:)` splits lines at `\n`, `\r\n` and `\r` only, like the
  core, not at `NSString`'s paragraph separators, and says a caret touches the token line it is on, both edges included.
- **Never `VACUUM` the database.** The search index `notes_fts` is keyed on the `notes` table's implicit `rowid`, which
  `VACUUM` may renumber, and every hit would then point at the wrong note. `notes_fts` is an external-content table: it
  holds no text of its own, and three triggers keep it current, so never write to it by hand. `NoteStore.save` uses
  `INSERT ... ON CONFLICT DO UPDATE`, which keeps the `rowid` and fires the update trigger. `INSERT OR REPLACE` would
  give the note a new `rowid` and skip the delete trigger, which corrupts the index.
- **`NoteStore.save` never changes a stored note's pin, deletion or creation time.** On a conflict it writes only the
  title, the body, the derived columns and `modified_at`, because the `Note` being saved may be a copy from before the
  owner pinned or deleted it (an autosave must not undo that). A new row still gets every column. Change the pin, the
  deletion and the restore with `setPinned`, `delete` and `restore`, which touch only their own column and never
  `modified_at`. `delete` keeps the first deletion date of a note that is already deleted, and `deletePermanently`
  and `purge` only ever remove a note that is deleted. A deleted note stays in the search index and is filtered out
  of `search`, so a restore needs no reindexing.
- **Search text is never FTS5 syntax.** Pass what the owner typed through `SearchQuery.ftsExpression`, which quotes every
  word, and never build a `MATCH` string yourself. A word without a letter or a digit is dropped.
- **Sidebar days are calendar days, and time labels are the locale's.** `SidebarSections` and `NoteTimeLabel` both ask
  `SidebarSections.group(of:now:calendar:)`, which compares with the start of today and of yesterday in the given
  calendar. Never subtract 24 hours: a day is 23 or 25 hours long when the clocks change. ICU puts a narrow no-break
  space (U+202F) before AM/PM and its version differs between Linux and macOS, so tests of a label turn U+202F and
  U+00A0 into plain spaces before comparing (`spaced` in `NoteTimeLabelTests`).
- **`swift test --sanitize=thread` reports false data races on `Synchronization.Mutex` on Linux.** TSAN does not see
  the futex that `Mutex` uses, so every `Mutex`-guarded access looks unsynchronised (`Database` and `Autosaver` both
  show it). A report whose two accesses are both inside `withLock` is noise.
- **A grammar's own `Package.swift` may silently leave out its scanner.** The `tree-sitter init` template adds
  `src/scanner.c` only when `FileManager.default.fileExists(atPath: "src/scanner.c")`, and SwiftPM evaluates a dependency's
  manifest in the builder's working directory, so linking fails with undefined `*_external_scanner_*` symbols. Such a
  grammar is vendored into `Packages/ScratchCode/Sources/Grammar<Language>/`, compiled with `-w` (Xcode warns about the
  generated C, and the app builds with no warnings; docs/decisions/0007, which also lists how to add a language). Python
  and PowerShell are vendored, and so is SQL, for another reason: its tags have no generated `parser.c` at all (it is on
  the `gh-pages` branch, a build for each commit of `main`), and a dependency could only pin a commit of that branch.
  JavaScript, YAML and CSS are pinned to the older tags that list their sources outright,
  and their queries are from those tags: a query must match the node names of the grammar it runs on. Pin every package
  in `Package.swift` with `exact:`, because the generated Xcode project has no `Package.resolved` of its own: nothing is
  pinned with `revision:` (`GrammarsTests.sqlBuildsFromVendoredSources` checks it).
- **A query that names a node its grammar lacks does not compile, and the language then goes uncoloured.**
  `QueryCache` turns the error into nil, so only a test notices: `QueryInheritanceTests.everyLanguageHasAGrammarAndItsQueryFiles`
  compiles all 17. That is why `javascript-jsx` is a folder of its own (TypeScript has no JSX nodes) and why a copy of
  a query is taken from the tag of the grammar it runs on. A capture with no kind (`@property`, `@variable`) is dropped
  before overlaps are resolved, so it cannot hide a wider coloured capture: YAML's keys are `@type` for that reason.
- **ScratchCode's queries are a resource bundle, and a missing one stops the app.** `Grammar.makeQuery` reads
  `Queries/<language>/highlights.scm` through `Bundle.module`, which calls `fatalError` when it cannot find
  `ScratchCode_ScratchCode.bundle`. `scripts/check-release-zip.sh` and `HighlighterInAppTests` check that the app carries
  it. Highlight on a background queue, never on the main thread: the first use of a language compiles its query (240 to
  270 ms for Swift, Release, on Linux), and `Highlighter` is thread-safe.
- **Code detection is tuned against `Tests/ScratchCodeTests/Corpus/`, and the corpus only grows.** A paste that is
  detected wrongly becomes a sample first (the folder of its language, `unknown/` for a language Scratch lacks,
  `prose/` for text that must stay plain), then the detector changes until every sample passes. Never delete a prose
  sample to make a test pass, and write every sample fresh: no poems, lyrics, articles or real emails. The rule is the
  spec's, "when unsure, it is prose": a text is code only with a mean line evidence of 0.5 or more and two lines of
  code that are not comments (`DetectionFeatures.evidence`), so a list of `word;` lines, a note that mentions `init()`
  and a log are prose, and so is a note of short lowercase `key: value` lines (`phone: 07700 900 123`, `buy: eggs, flour`):
  YAML needs a cue of structure (a `---`, nesting under a key with no value, a `- ` list under one, or a value that is
  `|`, `>`, an anchor or a quoted string with a colon: `DetectionFeatures.isYAMLShape`). A text with no idiom of any
  language is named only when one grammar parses it better than the others (else it is code of an unknown language), and
  a language that shares its idioms with another (TypeScript with JavaScript, C++ with C) is settled by the idioms only
  it has (`CodeDetector.settleScriptFamily`).
- **Detection reads text with its inline code masked.** `DetectionLine` turns what is between a pair of backticks into
  letters before it looks at the line, so `call `init()` first` in a Markdown note is a sentence and not a call.
  `JSONShape` is the JSON check, not `JSONSerialization`: Foundation on Linux accepts a trailing comma and the one on
  macOS does not. Only the first 300 lines or 40,000 bytes of a paste are read, the first 50 lines or 4,000 bytes are
  parsed to compare grammars, and a detection is 3 to 12 ms for 500 lines in Release (the budget is 20). The timing tests
  of `CodeDetectorTests` run in Debug, where the macOS runner took 107 ms for a bound of 100 and 498 ms for 400, so
  `bound(_:)` allows 4 times the figure a test names on macOS and the figure itself on Linux. The Release budget is held
  by `paste_code_ms`, not by them.
- **Do not link Homebrew's SQLite.** `CSQLite` deliberately has no `pkgConfig`, so macOS links the system library.
- **Never commit `App/Scratch.xcodeproj`.** It is generated from `App/project.yml`.
- **App tests run inside the app.** `ScratchAppTests` are hosted: Xcode starts the real app, then loads the tests into
  it, without `-ScratchDataDir`. `AppEnvironment.bootstrap` therefore gives an app that runs under XCTest and got
  neither `-ScratchDataDir` nor `-ScratchFixture` an empty fixture in a throwaway directory. Keep that guard.
- **Test classes need `@MainActor`.** The app target's default actor isolation is MainActor, the test targets' is not,
  and AppKit views are main-actor types. The tests so far avoid `setUp` and `tearDown` and use helper functions and
  `defer`, because an override must match the SDK's isolation for them.
- **The editor is a TextKit 1 text view, and only `TextViewFactory` may make one** (docs/decisions/0001: TextKit 2
  needs 12.9 to 16.3 ms per keystroke in the middle of a 10,000-line note and 19.5 to 38.5 ms at its start, the budget
  is 8). An `NSTextView` made any other way (`NSTextView()`, `NSTextView(frame:)`, a nib) is a TextKit 2 view on
  macOS 26. Do not read `textLayoutManager` or `textContentStorage` in the editor: they exist only on a TextKit 2
  view.
- **A TextKit 1 text view does not own its text storage.** The storage owns the layout manager, which owns the
  container, and the links back are unowned. `TextViewFactory` keeps the storage in `NoteTextView.ownedTextStorage`;
  without it the stack is freed when `makeEditor()` returns.
- **Hide characters on TextKit 1 with null glyphs.** Plan 3's marker hiding is an `NSLayoutManagerDelegate` that sets
  `.null` on the marker glyphs in `shouldGenerateGlyphs` (the code and the measurements are in docs/decisions/0001). The
  caret still stops at each hidden character.
- **A text view needs `NSScrollView.contentInsets` in mind.** The window uses `fullSizeContentView`, so the toolbar
  overlaps the top of the window, and the top of a note is at `y = -contentInsets.top`, not 0
  (`EditorViewController.show`). The tab strip is constrained to the safe area of `EditorAreaViewController`'s view and
  the editor starts below the strip, so the editor's own safe area has no toolbar in it: its title field sits 10 pt
  below the editor's top, the scroll view starts below the title field, and its inset is 0. The code does not rely on
  that: every scroll position goes through `contentInsets.top`.
- **AppKit scrolls a text view to its selection whenever its frame changes, and that hid the top inset.** The text
  starts `NoteTextView.verticalInset` (12 pt) below the top of the view. `-[NSTextView setFrameSize:]` calls
  `-scrollRectToVisible:` for the selection (in the CI stack it came from `NSScrollerImpPair`'s new recommended scroller
  style, which retiles the scroll view at launch, and the same happens when the window or the sidebar is resized), and
  for a caret on the first line of a note taller than the window it moved the clip view to y = 12, so the huge-note
  screenshot had its first line 12 pt higher than the typical one. `NoteTextView.scrollToVisible(_:)` finishes the
  scroll to the top when a scroll to a rect that starts in the top inset left less than the inset above it. To find
  who scrolls a view, log `Thread.callStackSymbols` from a `boundsDidChangeNotification` observer of the clip view, and
  print it in a UI test's failure message through the `debug.state` element: that is how this was found.
  (`show` itself was right all along: `EditorViewControllerTests.testNoteWithoutAnchorShowsItsTopInset` passes without
  the override, and `TitleUITests.testHugeNoteShowsItsTopInsetAtLaunch` is the test that needs it.)
- **A scroll anchor waits for a layout, and is applied again whenever the layout settles at another width.** Text can
  only be positioned at a width, and at launch `show` runs before the window has laid out (the scroll view is 0 wide),
  so `EditorViewController` keeps the anchor and scrolls in `viewDidLayout` (`isLaidOut`, `scrollAnchorToApply`). A
  launch lays the text out at several widths (a first one, the window's, and a retile when the scrollers change style,
  which no layout of the editor's view follows), and each change of the width lays the text above the anchor out again
  and leaves its height an estimate, far from the real one when lines wrap or fences are 6 pt (measured on CI with a
  temporary trace: line 1003 of the huge note at y = 18,408 laid out and at y = 12,530 estimated, after which
  AppKit's move of the clip view left the note 1 to 3 lines off, and its bounds change was taken for the user
  scrolling, which ended the wait). So `isAnchorStale` (the text view's width is not the one the anchor was applied at)
  makes the clip view's bounds notification and the text view's frame notification apply it again, on the main queue
  (`scheduleAnchorReapply`: not inside AppKit's tiling), and such a bounds change is not the user's. The wait ends when
  the user scrolls (a change of the bounds at an unchanged width), types, moves the cursor or changes the font size,
  and `anchorSettleTime` (5 s) after the last application, so that a later resize (the sidebar's animation) does not
  lay a deep note out again at every step. Never call `ensureLayout` before `isLaidOut`: it would lay a 10,000-line
  note out at a width of 0. `currentScrollAnchor` returns the waiting anchor until then, so an early save does not move
  the note back to its top.
- **Undo is per note, and `show` never clears it.** `SessionCoordinator.undoManagers` holds one `UndoManager` per note,
  and `show` hands the editor the one of the note. `NoteTextView.noteUndoManager` is what the text view, the
  `NSTextViewDelegate.undoManager(for:)` answer and `AppDelegate.windowWillReturnUndoManager` (the Edit menu) all
  return, so they cannot disagree. Loading a note's text runs between `disableUndoRegistration()` and
  `enableUndoRegistration()` of its manager and is not an undo step, and `breakUndoCoalescing()` ends the typing run of
  the note being left. Show a note with the text it had when it was left: an undo step holds ranges of that text.
- **UI tests read the font size, the scroll anchor and the scroll offset from `debug.state`.** `DebugStateElement` is a
  1 x 1 point view in the editor's container, only in an isolated launch (`AppDelegate`), with a JSON string for its
  accessibility value that it computes when asked (`fontSize`, `scrollAnchor`, `readOnly`, `scrollY`, `topInset`, and
  `pendingHighlights` and `pendingPastes`, which are zero when a paste is done): `UITestSupport.debugState(in:)` reads
  it. It draws nothing and takes no clicks, so it is not in a screenshot.
- **⌘= is a hidden second "Bigger" item.** The View menu lists ⌘+, and the item for ⌘= is hidden with
  `allowsKeyEquivalentWhenHidden` set by name (`MainMenu.allowKeyEquivalentWhenHidden`). A shortcut that needs two key
  equivalents needs two items.
- **macOS 26 draws a one point line under the toolbar across the editor when the editor's scroll view starts below the
  titlebar** (Plan 2 moved it below the title field; Plan 1's scroll view was under the toolbar and had no line at
  rest). It is the hard `NSScrollPocket` in the split view's `NSTitlebarBackgroundView` (a `_NSLayerBasedFillColorView`
  of height 1 in `separatorColor`), not a titlebar separator: `NSSplitViewItem.titlebarSeparatorStyle = .none` and
  `NSWindow.titlebarSeparatorStyle = .none` were each tried on CI and left the line on the same pixels. There is no
  public API for the pocket, so `TitlebarPocket` hides it by class name after each layout of `MainSplitViewController`,
  and `TitlebarPocketTests` fail when it is visible or can no longer be found. When a screenshot shows a hard line at
  y = 51 below the toolbar, look there first.
- **There is no storyboard, so there is no menu bar until `MainMenu.install` runs.** ⌘Q, ⌘C, ⌘V and ⌘Z only work
  because that menu exists. A new shortcut needs a menu item.
- **The coordinator must outlive the autosaver's timers.** `Autosaver` does not keep itself alive: a dirty autosaver
  that is released skips its pending save. `SessionCoordinator` owns it and `AppDelegate` owns the coordinator, so keep
  both. The save closure holds the coordinator weakly. Never replace the autosaver while it is dirty.
- **`SessionCoordinator.persistNow()` waits for the storage queue** (`storageQueue.sync {}`), and so does every change
  that leaves the note in the editor, which calls it first: `open` of another note, `selectTab` of another tab,
  `newNoteInNewTab`, closing the active tab, closing the only tab (when its note has been used), `deleteNote` and
  `deleteNotePermanently`. Closing a tab that is not active does not (`closeOtherTab`). Call all of them and `flush()`
  on the main thread only, and never from a block that runs on the storage queue.
- **A new note that nobody has used is not in the sidebar** and is discarded when its tab closes or another note
  replaces it in the tab, while it is still empty. It is "untouched" while it was created in this session (or restored
  empty) and has no text. Test changes that look at the sidebar must type first. Switching to another tab keeps an
  untouched note and its tab: only closing or replacing discards it. A note the owner empties is kept
  (docs/decisions/0004): the first edit of its text or title (`noteWasEdited`) takes it out of `untouchedNoteIDs` for
  good, and at a restore a note is untouched only when it is empty and its `modifiedAt` is still its `createdAt`
  (`isNeverUsed`). Anything that writes a note's text must set `modifiedAt`, or that rule breaks.
- **A failed write keeps the note, and the storage queue says so itself.** `SessionCoordinator.saveNow` writes the notes
  in `unsavedNotes` (`UnsavedNotes`, ScratchCore) first, then the note of the active tab when it has edits, then the
  session, each note as a write of its own. The storage-queue block records the outcome in `unsavedNotes` (a mutex,
  not a hop to the main thread), so it is right when `persistNow()` returns: a note that was left while its write failed
  is retried by the next save and is shown again from `unsavedNotes` (`loadNote`), never from the older stored text. A
  code path that removes a note from the storage (`discard`, `didRemoveNotes`) must `forget` it there, or a retry would
  insert it again. To make writes fail in a test, run `PRAGMA query_only = 1` on `storage.database` (file permissions do
  not work on an open SQLite file), and `= 0` to repair. Under it `NoteStore.create` fails too, so `newNoteInNewTab`
  does nothing: switch with `open(_:inNewTab:)` to a note that exists.
- **A tab is the unit of `TabList`, and `SessionCoordinator.tabs` is the only copy.** The coordinator holds the note of
  the active tab (`current`) and nothing else of any note: another tab's note is read from the storage when its tab is
  shown, after the note being left was written (`leaveCurrentNote`). `saveNow` records the cursor and scroll anchor of
  the active tab in the list before it builds the session, so a code path that changes the tabs after `persistNow()`
  must read `tabs` again and not reuse a copy from before it. A tab change ends with `tabsDidChange()`, which shows the
  strip and the sidebar and writes the session at once (`writeSessionNow`).
- **A new note opens at the end of the strip, a note opened from the sidebar next to the active tab.** `TabList.open`
  inserts after the active tab, which is what ⌘-click wants. `newNoteInNewTab` selects the last tab first, so the new
  tab is at the end, as in a browser, and `testCommandTOpensNewEmptyTab` expects the new tab to be the third.
- **A sidebar header is a group row, and it is not a note.** `SidebarViewController` flattens the sections into
  `Line`s, a `.header` or a `.note`. `isGroupRow` makes a header, `shouldSelectRow` refuses it (so the arrow keys step
  over it), and `rowClicked` ignores it. Row heights differ (44 and 28), so the delegate answers `heightOfRow`. The
  header's label has the identifier `sidebar.group` and the title of a row `sidebar.row.title`, so a UI test that counts
  rows counts titles only. A header is a `NSTableCellView` made for `tableColumn == nil`.
- **`NoteListModel` owns the sidebar's reads, and the coordinator tells it what to hide.** Every `refresh()` reads on the
  storage queue and is numbered (`request`), so only the newest result is shown. The model hides `hiddenNoteID` (the
  active note while it is new and empty) and, while their saved row is empty, `hiddenWhileEmptyNoteIDs` (new notes in
  other tabs). Both are set by `SessionCoordinator.updateNoteListState()`, which `didReadLiveSummaries` calls before the
  model shows what it read: a note that gets its first text is listed by the read that follows its save. A note that
  the coordinator discards goes through `NoteListModel.forget`. The sections are built with `Date()` and
  `Calendar.current` on every `render()`, and `applicationDidBecomeActive` asks for a read.
- **Pinning writes only the pin.** `SessionCoordinator.togglePin` reads the stored pin on the storage queue and flips it
  with `setPinned`, then asks for a read, which the queue runs after the write. The pin button, ⇧⌘P and the row's menu
  all end there. The button's state comes from `onActiveNotePinChange`, which the coordinator calls after every read and
  every change of the tabs. The toolbar item has `autovalidates = false`, or AppKit would enable it again by itself,
  and `AppCommands.validateMenuItem` sets the title of the Pin Note menu item ("Pin Note" or "Unpin Note").
- **⌘⌫ deletes a note only through `SidebarTableView.keyDown`, never as a menu key equivalent.** A key equivalent in
  the menu bar is offered before the key reaches the first responder, so it would take ⌘⌫ away from the text view,
  where it deletes to the start of the line (`testCommandBackspaceInEditorKeepsNote`). The table only gets the key while
  it is the first responder, which is "the sidebar has focus". A delete from the sidebar must not move the keyboard into
  the editor either (`closeTab(at:focusingEditor: false)`), or the next ⌘⌫ would delete text.
- **Delete, restore and delete permanently write on the main thread, after `persistNow()`.** `SessionCoordinator.
  deleteNote` writes the typing first, then `NoteStore.delete`, then closes the tab (only when the write worked), and
  `NoteStore.save` never writes `deleted_at`, so a later save of the same note cannot bring it back. Do not delete a
  note through the storage queue with a stale copy of the tabs. `didRemoveNotes` closes the tab of the active note last,
  because closing it shows its neighbour, which must still exist.
- **A tab can hold a deleted note, read-only.** Clicking a row of Recently Deleted opens it (`loadNote` loads deleted notes
  too, `show` passes `isReadOnly: note.deletedAt != nil`), and a relaunch drops such a tab. A read-only editor has no
  undo manager (`NoteTextView.undoManager`, `EditorViewController.activeUndoManager`): undo would still change the text
  of a note that cannot be changed, and the change would be saved. `restoreNote` calls `setReadOnly(false)` instead of
  showing the note again, so the cursor, scroll position and undo history stay.
- **The Recently Deleted header is a group row that takes its own click.** A header cannot be highlighted, and
  the table's action is not something to rely on for a row it will not select, so `SidebarTableView.mouseDown` asks
  `takesClick` first. Its text has the identifier `sidebar.recentlyDeleted` (`UITestSupport.sidebarGroupTitles` does not
  list it) and reads "Recently Deleted (N)", the number of deleted notes, shown or not. The section starts collapsed at
  every launch.
- **The purge runs on the storage queue and tells the main thread only when it removed something.**
  `SessionCoordinator.purgeExpiredNotes(now:)` runs at launch (one main-queue turn after `restore()`) and from
  `applicationDidBecomeActive`, at most once an hour. It cannot say which notes went, so `didPurge` looks up the open
  tabs' notes. A launch on the `recently-deleted` fixture shows "(2)" for a moment and then "(1)": UI tests wait for the header text.
- **The search field sends its text twice.** A keystroke triggers both the field's action (`sendsSearchStringImmediately`)
  and `controlTextDidChange`, and Escape is handled in `control(_:textView:doCommandBy:)`. `searchTextMayHaveChanged`
  reports a text only when it differs from the last one, so the list is read once. ⌥⌘F is a menu item (Edit > Search
  Notes) that calls `SidebarViewController.focusSearch`, which also shows a collapsed sidebar.
- **The sidebar's layout is remembered, except in an isolated launch.** `MainSplitViewController` sets
  `splitView.autosaveName = "MainSplit"` in `viewDidLoad` only when `remembersLayout` (`!options.isIsolated`), so tests
  and screenshots never write the defaults and always start with the same width.
- **The sidebar opens a note from the table's click action, not from the selection.** `NSTableView.action` also fires
  for the row that is highlighted already, and `tableView.clickedRow` is valid in it. The arrow keys move the
  highlight without opening anything, so the highlight and the open note can differ until the coordinator renders the
  list again (`SidebarTableView` turns Return into `onReturn`). ⌘-click on the highlighted row deselects it, which
  `open(_:inNewTab:)` undoes by rendering the sidebar even when it has nothing to show.
- **The tab strip is an `NSGlassEffectView` that Auto Layout does not size, with a frame-based content view.**
  `TabStripView` (the strip's own view) gets its width from the tabs as its intrinsic content size, with a compression
  resistance (40) below the fitting size priority (50), and `EditorAreaViewController` caps it with a required
  `trailing <=` constraint. The glass is a subview with a fixed frame that `TabStripView` keeps equal to its bounds
  (`syncGlassFrame`), no constraints and no autoresizing mask. The glass hosts its content in a SwiftUI hosting view
  (`_NSCoreHostingView`) pinned to it, with an intrinsic width of 10 pt that it hugs at priority 250: tied to the strip
  by constraints or by an autoresizing mask, the glass passed that on and the strip came out 10 pt wide on CI, a sliver
  that a click on the second tab missed (`TabStripViewControllerTests` measure the strip, and print the constraints
  when they fail). A width constraint on the strip, at any priority above 50, would make the split view item's minimum
  width grow with the number of tabs. Do not use `NSStackView` with required widths in the strip for the same reason.
- **A tab is one accessibility element and its close button is not inside it.** `TabItemView` is a button
  (`tab.item`) with a label, a title and a selected state, and the close button (`tab.close`) is a sibling placed over
  its right end, so UI tests read `UITestSupport.tabs(in:)` and `activeTabTitle(in:)` and click a tab at its centre.
- **Tab shortcuts are menu items, and ⌃⇧Tab has three spellings.** ⌃Tab is `"\t"` with `.control`. Shift+Tab is
  the character U+0019 on the keyboard, and the Previous Tab item exists with `"\t"` and with U+0019, so one of them
  matches (`MainMenu.windowMenu`), the others hidden with `allowKeyEquivalentWhenHidden`. If ⌃⇧Tab ever stops working,
  `testControlTabCyclesAndWraps` says so.
- **`NSToolbar` holds its delegate weakly.** `AppDelegate` keeps the `ToolbarController`.
- **A toolbar item only gets a Liquid Glass capsule when it is a plain `NSToolbarItem` with an `image`.** The new note
  button was first an `NSButton` as the item's view, and the screenshot showed a small bare icon, also with
  `isBordered = true` on the item. A view-less item has no accessibility identifier of its own, so its item identifier
  is `AccessibilityID.newNoteButton` and `UITestSupport.newNoteButton` finds it by identifier, label or title.
- **Screenshots are 1024 x 674 px, not 1100 x 700.** The runner's screen is small, so AppKit shrinks the window to fit.
  A screenshot is a picture of the window only (no desktop), light or dark, and its caret may or may not be showing.
  Exporting them needs the attachment `name`: `xcresulttool export attachments` suggests `<name>_<index>_<UUID>.png`,
  which `scripts/name-screenshots.py` turns into `<name>.png`.
- **A screenshot of code waits for its colours.** They are written from the highlight queue after the window is up, so
  `ScreenshotTests.testCodeLight` and `testCodeDark` wait for `debug.state`'s `pendingHighlights` to be zero before the
  picture (the request is made in `show`, before the window is visible, so zero means done). The `code` fixture's note is
  44 lines and fits the 1024 x 674 window whole: a line added to it can push the last block, the one with no fence name
  and the italic `JavaScript` label, below the edge, so look at `code-light.png` after any change to the fixture.
- **UI tests type without clicking the editor first** (`editor.typeText`): the editor is first responder at launch, and a
  click would move the cursor that `testCursorRestoredAfterRelaunch` checks. `typeText` and `typeKey` need keyboard focus.
  Kill the app with `NSRunningApplication.forceTerminate()`, never `XCUIApplication.terminate()`, which may quit
  gracefully.
- **UI tests find elements by `AccessibilityID`.** The file is compiled into the app and into each UI test target
  (`App/project.yml`), so add an identifier once and use it on both sides. UI tests launch through
  `UITestSupport.launch(fixture:)`, which always passes a unique `-ScratchDataDir`.
- **`project.yml` can be checked on Linux.** XcodeGen builds there: clone `yonaskolb/XcodeGen` at tag `2.44.1`,
  `swift build -c release --product xcodegen`, then run `USER=root SCRATCH_VERSION=0.1.0 xcodegen generate --spec
  App/project.yml` and read the generated `project.pbxproj`. It checks structure only: it cannot compile Swift.
- **UI tests run on the hosted macOS runner with no extra permission.** The `macos` job runs the whole `Scratch` scheme,
  UI tests included (verified on `macos-26`, macOS 26.6 and the 26.5 SDK). If a runner image ever withholds
  accessibility permission, run only `ScratchAppTests` (`-only-testing:ScratchAppTests` in `make app-test`), write that
  down here, and tell the owner.
- **`NSTextView.writeSelection(to:types:)` wrote nothing for `.string` on the macOS 26.5 SDK** (it returned false, with
  a valid selection). `NoteTextView` overrides it and writes the selected text itself. Do not remove the override
  without running `testCopyWritesOnlyPlainText` on CI.
- **Markers are rendered by attributes and glyphs, never by editing text.** `MarkupStyler` (the text storage's delegate,
  kept alive by `NoteTextView.styler`) gives each paragraph the base attributes and then what the core's `MarkupSpan`s
  ask for. A marker character carries `.scratchMarker` with a `MarkerRole` (`hidden`, `revealed`, `bullet`,
  `checkboxOpen`, `checkboxChecked`): `MarkupLayoutManager` makes the `hidden` ones null glyphs (docs/decisions/0001) and
  draws a `•` over a `bullet`. A link keeps its URL in `.scratchLink`, not `.link`: AppKit opens `.link` with a plain
  click. Nothing but the styler writes these attributes, and the stored text is only changed by the owner's own actions.
- **The styler's own attribute edits are not edits.** It styles inside `textStorage(_:didProcessEditing:…)` and only for
  `.editedCharacters`; its own `setAttributes` calls come back as `.editedAttributes` and are ignored (`isApplying` as
  well). Never call `invalidateGlyphs` or `invalidateLayout` inside that callback, where the layout manager may not know
  the edit yet: the attribute edit invalidates what it touches, and `invalidate(_:)` is only for the styler's changes
  made from a run loop turn (the chunks, a change of the selection). A keystroke restyles only the paragraphs it edited
  (the storage may widen `editedRange` to whole paragraphs, which `EditMapping` accepts).
- **A shown note is styled in two steps, and `load` styles nothing.** `NoteTextView.load` gives the text the base
  attributes (`beginLoad` and `endLoad`, which also scans the fences), and `EditorViewController.show` then calls
  `styler.noteDidLoad(visibleRange:)` with the saved scroll anchor, before anything lays the text out. That styles the
  paragraphs ±200 of it at once and the rest in chunks of 1,000 paragraphs (at most 12 ms each), one per main run loop
  turn at `RunLoopIdle.afterMeasurementsOrder`, so a signpost interval has ended before a chunk begins. The chunks
  schedule themselves with a wake-up of the run loop: `RunLoopIdle.onNext` called from an idle callback would otherwise
  wait for the next event. An edit while chunks are pending carries the pending ranges over it (`EditMapping`), and an
  edit of more than 20,000 characters (a big paste) is styled in chunks too, after the fences are scanned again.
- **Never set `font` or `textColor` on the editor to resize it.** On a plain-text view that resets every run of the text,
  bold included. `NoteTextView.applyFontSize` leaves the text to `styler.fontSize`, which styles it again (and still sets
  `font` and `textColor` while the text is empty, where `NoteTextView.font` reads them).
- **Bold needs word boundaries** (docs/decisions/0006). `MarkupParser.boldRuns` accepts an opening `**` only after the
  line start or a character that is not a letter or a digit, a closing one only before the line end or such a character,
  and neither when it has punctuation on both sides (`src/**/*.ts`, `)**(`). So `x**2`, `a**b**c` and globs are plain
  text, and `InlineEditing.toggleBold` inside a word inserts stars that are not a run. A test that types or shows bold
  needs a space, the line edge or punctuation next to its stars.
- **The line prefilter must know every marker the parser knows.** `MarkupParser.mayHaveSpans` (ScratchCore) lets the
  styler skip a line without parsing it. A new kind of marker needs its first character there, and
  `MarkupPrefilterTests` holds the parser to it with a few thousand random lines.
- **Fenced blocks are carried over edits, not scanned for again.** `CodeBlockIndex` shifts its blocks with each edit
  (`apply`) and the styler scans the whole text again only when the edit touched a fence line of a block
  (`touchesFenceLine`, ends of the lines included) or the paragraphs it edited now hold a fence line, then restyles the
  paragraphs that moved in or out of a block (`changedRanges`). The scan reads the text with `getCharacters` and looks
  for "```" first: most notes have none.
- **`MarkupLayoutManager` is `nonisolated` on purpose.** AppKit does not annotate `NSLayoutManager`, and a main-actor
  subclass would have a main-actor `init()` that does not match the superclass's. Its delegate methods and
  `drawGlyphs` run on the main thread during layout and drawing, and use no main-actor API (no
  `MainActor.assumeIsolated`: capturing the manager in a main-actor closure failed to compile, "sending self"). The
  manager is its own delegate and `TextViewFactory` sets that after the text view exists, which sets the delegate
  itself when it is made.
- **A bold run's markers show while the caret touches the run, and a selection of more than 20,000 characters shows
  none.** "Touches" counts the positions at both ends of the run. Walking the caret into a run therefore shows its
  stars before it can step onto one, so Backspace never deletes a character the owner cannot see.
- **Paragraphs are `NSString.paragraphRange(for:)`'s, lines are the core's.** The styler splits the text at line feed,
  carriage return, CR LF, U+2029 and U+0085, and the core at the first three only, so a line with a paragraph
  separator in it can be styled differently by `MarkupParser.parse`. Nothing in Scratch makes one.
- **A click on a checkbox is handled in `NoteTextView.mouseDown` and never reaches `super.mouseDown`.** A plain click
  whose point is inside the rectangle of the three `[?]` glyphs (`checkboxMarker(atViewPoint:)`, which asks the layout
  manager for the character under the point, not the nearest insertion point) ticks or unticks the item through
  `apply(_:)` and leaves the caret where it was; the view takes the keyboard. Any other click, one with ⇧, ⌘, ⌥ or ⌃
  held (except a ⌘-click on a link, below), and every click in a read-only note is AppKit's. **A hosted test must not send a click that ends in
  `super.mouseDown`:** it runs a tracking loop until the mouse button is released, and the test hangs for its two
  minutes. `CheckboxTests.clickBox` checks that the point is on a box first, and the cases that are not a toggle call
  `checkboxMarker(atViewPoint:)` and `toggleCheckbox(atViewPoint:)` directly.
- **A link opens with ⌘-click only, through `NoteTextView.openURL`, and a hosted test must never open a browser.**
  `mouseDown` with ⌘ held over a character of a link (`link(atViewPoint:)`: the layout manager's character under the
  point, accepted only when the point is inside that one glyph's rectangle, so the empty space after a link that ends its
  line is not the link) calls `openURL` and returns without `super`: no caret is placed, and a read-only note opens links
  too. Every other click, a plain click on a link included, is AppKit's. `openURL` defaults to
  `NSWorkspace.shared.open`, and every `LinkTests` test replaces it. A link is `.scratchLink` and never AppKit's `.link`,
  which opens with a plain click (`MarkupAttributes`). **The hosted tests that send a click to `super.mouseDown` queue
  the matching `leftMouseUp` first** (`NSApp.postEvent(_:atStart: false)`), so that AppKit's tracking loop ends at once,
  and take what is left in the queue out afterwards (`LinkTests.click`).
- **The pointing hand follows ⌘, and only after the view set it itself.** `updateTrackingAreas` makes one
  `NSTrackingArea` (`mouseMoved`, `activeInKeyWindow`, `inVisibleRect`, `linkTrackingArea`) and `mouseMoved(with:)`
  and `flagsChanged(with:)` call `updateLinkCursor(atViewPoint:modifiers:)`, which sets `NSCursor.pointingHand` over a
  link while ⌘ is held and puts `NSCursor.iBeam` back only when it had set the hand (`showsLinkCursor`): the cursor
  over the scroll bar is not the view's. `flagsChanged` reaches the first responder only, so with the keyboard in the
  title field the hand shows with the next mouse move. Nothing reads the cursor in a test: `updateLinkCursor` returns
  what it set.
- **A rule's `TextEdit` enters the note through `NoteTextView.apply(_:)` only.** It breaks the undo coalescing, changes
  the text with `shouldChangeText`, `replaceCharacters` and `didChangeText` (one undo step, registered on the note's own
  undo manager, and the styler restyles the paragraph as for typing), then sets the selection. It never touches a
  read-only view. After undoing a checkbox click AppKit selects the character that came back, as it does for any
  programmatic replacement.
- **Undo steps cannot be tested in a hosted test across two edits.** Measured on CI (macOS 26.6): typing opens an undo
  group (`groupingLevel` 1, `isCoalescingUndo` true), `breakUndoCoalescing()` only clears `isCoalescingUndo` and leaves
  the group open, and the group is closed by the end of the run loop turn, not by a nested `RunLoop.run(until:)`.
  Ending it by hand with `endUndoGrouping()` while the view is still coalescing raises "must begin a group before
  registering undo" (`NSInternalInconsistencyException`, which ends the whole test run). So in one test method the typing
  and the edit after it are one undo group. Real key events are separate turns: `ChecklistUITests` types, presses ⇧⌘L and
  ⌘Z, and the typing stays. Test "one step" of a single action in a hosted test (`testUndoAfterCheckboxClick`), and a
  step next to typing with UI tests.
- **A command that edits whole paragraphs asks `styler.intersectsCodeBlock` for the paragraphs it will change**, not
  `isInCodeBlock` for the caret: a selection can start and end outside a block and hold it. ⇧⌘L beeps there, and in a
  read-only note.
- **Return, Tab and ⇧Tab are `NoteTextView` overrides that ask the core and fall back to `super`.** `listEdit(_:)` gives
  the rule (`ListEditing.newline`, `indent`, `outdent`) the paragraphs under the selection and answers nil, so that
  `super` runs, when the view is read-only, text is being composed, there is more than one selection, or
  `styler.intersectsCodeBlock` says a block is under the selection (the paragraphs, not the caret: see the pitfall
  above). A rule's nil is the same. `applyAndReveal` applies the edit and scrolls to the caret, which `apply(_:)` does
  not (a click on a box must not scroll). ⇧Tab on an unindented list line is a list action that changes nothing, so it
  does not reach AppKit's `insertBacktab:`; ⇧Tab on any other line does.
- **⌘B is `toggleBoldMarkers(_:)`, not `toggleBold(_:)`.** `toggleBold:` is AppKit's font-panel action, which a
  plain-text view must not answer. The Format > Bold item has no target, like Checklist, so the first responder gets it.
  The hosted `ListKeyTests` call `insertNewline(nil)`, `insertTab(nil)`, `insertBacktab(nil)` and `toggleBoldMarkers(nil)`
  directly, with one editor and one `UndoManager` for each edit that is undone (see the undo pitfall above), and
  `FormattingUITests` presses the keys, so that the menu bar and the responder chain are in the path.
- **The Format menu is not auto-enabled** (`menu.autoenablesItems = false`, `MainMenu.formatMenu`): AppKit would ask the
  first responder, and the way `NSTextView` validates an action it does not know is not documented. A Format item has
  no target, so the first responder gets it, and a command that cannot work beeps (`NSSound.beep()`).
- **The box is an SF Symbol drawn over the transparent `[?]`.** `MarkupLayoutManager.drawCheckbox` draws `square` or
  `checkmark.square.fill` with a palette configuration of `controlAccentColor`, centred in the glyph rectangle of the
  marker and 85% of the line height, on every draw (the colour and appearance of the moment). `testCheckboxSymbolIsDrawn`
  renders the view with `cacheDisplay` and counts the pixels that are not the background.
- **A fenced block is drawn from attributes, and its fence lines are null glyphs.** `MarkupStyler` gives the characters of a
  fence line (not its line break) the role `fence`, which `MarkupLayoutManager` turns into null glyphs (all but the first,
  see below), and the paragraph
  `MarkupAppearance.codeFenceStyle` (minimum and maximum line height 6 pt), so the line is padding. While the caret or
  selection touches it (`touchesSelection`, the ends included) the role is `revealed` and the paragraph has
  `codeBodyStyle`, like the lines of code (10 pt head and tail indent). Every paragraph of a block carries a
  `CodeBlockMark` (`.scratchCodeBlock`: opening, body or closing); only the opening fence line's holds the language and
  the label, so a keystroke in a line of code never has to know it, and a detected label stays while a new result is on its
  way (`openingMark`). `MarkupLayoutManager.drawBackground` fills the tint per line fragment from what is laid out (never
  from the block's end: the end of a block of thousands of lines would have to be laid out) and draws the labels, also
  when only the first line of code is redrawn, because the label reaches into it. `CodeBlockMark` is a `nonisolated`
  `NSObject` because the layout manager is not on the main actor; the nested structs of a nonisolated class are marked
  `nonisolated` too.
- **A fence line moved into or out of a block by an edit is invalidated after the edit.** The role of a fence line decides
  whether it has glyphs, and `storageDidEdit` cannot invalidate glyphs from inside the edit, so it records the range
  (`invalidationAfterEdit`) and `NoteTextView.didChangeText` calls `MarkupStyler.editDidFinish`, before the delegate hears of
  the edit. A rescan that changes a block (not only its length) styles it again whole (`rescanCodeBlocks`): a paragraph can
  stay in a block and still be another line of it.
- **Blocks above the window are styled whole at load, because a scroll position depends on their height.** `show` sets the
  scroll position from the layout of everything above it, and the chunks that style a long note run later. A hidden fence
  line is 6 pt and a line of code is indented, so a block styled by a chunk after the scroll moved the note under the
  reader (`TitleUITests.testScrollPositionSurvivesRelaunch`: three lines off on the CI). `MarkupStyler.styleBlocks` gives
  every block that starts above the end of the window its look in one pass per block (a block, not a paragraph, is the
  unit, so it is cheap for the huge note), and `styleFenceLine` and `styleCodeBody` write nothing, and invalidate nothing,
  for a line that is as it should be. Anything else that changes the height of a paragraph (a new kind of marker) has the
  same problem and the same remedy: an attachment line is 252 pt high where a line of text is 17, so
  `MarkupStyler.styleAttachmentLines` styles every token line above the paragraphs that `noteDidLoad` styles at once
  (it searches the text above them for `[[attachment:`, keeps the matches that are a whole line outside a block, reads their
  rows with one `catalog.preload`, and the chunks find that done), and
  `AttachmentRenderingTests.testTokenLineFarAboveTheAnchorIsStyledBeforeTheScroll` holds it to that. A token line below the
  window needs none of it: it moves nothing that is above it.
- **Colours are keyed by text, not by place.** `CodeBlockStyler` sends a block's code to a private serial queue, one request
  at a time, and a result is applied to every block that holds the same fence name and code (hash first, then text), where
  the block is by then. A result for text that was edited since matches no block and is dropped (`droppedResults`): the edit
  asked for the block again. There is a cache of results by hash, so a block that moved or a note shown again is coloured
  without the queue. Results are written at `RunLoopIdle.afterMeasurementsOrder` for at most 8 ms at a time (a block of
  thousands of tokens over several turns), so no signpost interval includes them, and an edit inside a block that is
  being written ends that work (`textDidEdit`). `MarkupStyler.resetAttributes` keeps the opening mark of the paragraphs of
  a block that stays a block.
- **Code colours are temporary attributes of the layout manager, never attributes of the text.** As `.foregroundColor` of
  the text storage they made the huge note (100 blocks, about 50,000 colour runs) over 10 times slower on the macOS CI (37 ms
  per scroll frame and per keystroke, from 0.3 and 3): each colour was an edit, an edit invalidates the layout of its range, and the
  layout manager then laid the whole note out again in the background on the main thread. `addTemporaryAttribute` is
  display only. The layout manager's own bookkeeping is in the edit's coordinates only once `textStorage(_:didProcessEditing:)`
  has returned, so `MarkupStyler` never calls it inside that callback: the ranges to clear are kept
  (`coloursToClearAfterEdit`) and cleared in `editDidFinish`, from `NoteTextView.didChangeText`.
- **Null glyphs take no line fragment of their own.** TextKit puts a zero-width glyph at the end of the line before it,
  so a fence line of null glyphs only was no line: the CI measured the first character of an opening fence in the fragment
  of the blank line above (16 pt, while the fence's own 6 pt fragment held only its line break), and a closing fence that
  ends the note had no padding at all and the tint ended at the last line of code. A click or the End key on the line above
  would also have landed among the hidden characters. `MarkupLayoutManager.shouldGenerateGlyphs` keeps the glyph of the
  first character of every fence line (the colour of the role `fence` is clear), and the line is a 6 pt fragment of its own.
- **An attachment line is null glyphs but the first, as high as what is drawn on it, and drawn from its mark alone.**
  `MarkupStyler.styleAttachmentLine` gives a line that is exactly a token (`AttachmentToken.id(inLine:)`, outside a fenced
  block) the role `attachment` on characters 1 to 50 (null glyphs in `MarkupLayoutManager.shouldGenerateGlyphs`), a clear
  first character with no role (its glyph is what gives the line a fragment of its own: the pitfall above), a paragraph
  style whose minimum and maximum line height are the preview or chip height plus 12 (`MarkupAppearance.attachmentStyle`)
  and an `AttachmentMark` (`.scratchAttachment`, on the whole paragraph). The layout manager is not on the main actor, so it
  cannot ask the catalog or the text view: everything it draws is in the mark (kind, size, name, icon, the file's URL),
  and the selection comes from the styler (`MarkupLayoutManager.attachmentSelection`). Marks are equal only when they are
  the same object (no `isEqual`), so two lines of one attachment are two attribute runs; `hasSameLook(as:)` is what
  tells that a line need not be written again.
- **An image's height is its row's pixel size scaled, never its decoded size, and it depends on the text width.** The line
  must have its height before the image is decoded (`AttachmentMetrics.imageSize`: as wide as the text up to the image's
  own width, at most 240 pt high). A note shown at launch is styled before the text view has a width, so the lines are
  styled for a very wide text then and styled again when the layout arrives: `EditorViewController.viewDidLayout` calls
  `MarkupStyler.refreshAttachmentLayout()` before `applyPendingScrollAnchor()` (the anchor depends on the height of what is
  above it), and `textViewFrameDidChange` asks for it a turn later for a width that no layout followed (a scroller). It
  compares the width with the one the lines were sized for (`attachmentLayoutWidth`, reset by `endLoad`) and writes only
  a line whose look changes. A note without a token line costs one Boolean test.
- **A preview that arrives changes the display and nothing else.** `AttachmentPreviews` decodes on its own serial queue,
  in the order the styler asked (the paragraphs on screen are styled first), and calls `onChange(id, decoded)` on the
  main thread: `MarkupStyler.previewDidFinish` invalidates the display of the lines of that image
  (`invalidateDisplay(forCharacterRange:)`, never glyphs or layout, which an attribute edit or `invalidate(_:)` would
  also do). A failure goes to `AttachmentCatalog.markUndecodable`, which styles the lines again as "Missing attachment"
  (the one case where a preview changes a height). The layout manager asks again for an image it finds undecoded when it
  draws (`request`), which is how a thumbnail that the `NSCache` dropped comes back. Until it is there a tint stands in.
- **A token's state is the catalog's.** A row with no file that nobody copies is "Missing attachment", and only
  `AttachmentCatalog.markCopying` (called right after `AttachmentStore.register`) makes it "Copying…": a copy that was cut
  short by a quit shows as missing after the relaunch, and the launch sweep removes the row a day later when no note names
  it. `markCopying` and `markCopied` forget the row, so that they read the new one, and tell the editor
  (`onChange`), which styles the lines of that id again.
- **Adding a fixture means three more places.** `FixtureContent.make`, the `Fixture` case, and ScratchCore's
  `LaunchOptionsTests.parsesEveryFixtureName` (which lists every raw value), and then the launch argument table above and
  `make run`. A core test that lists the cases fails the Linux job and, through `make core-test` on the Mac, the whole
  macOS job before any app test runs. A fixture is the same data every time (`fixtureContentIsTheSameEveryTime`), so
  its attachments have fixed ids (a body holds them), and it writes its files only when `seed` is given the
  `AttachmentStore` (`ScratchStorage.open` always gives it).
- **A stored attachment file goes only when no stored body names its id.** `AttachmentStore.removeUnreferenced` and
  `sweep` ask `NoteStore.referencedAttachmentIDs()`, which scans every body, live and in Recently Deleted, for the token
  text anywhere in it (`AttachmentToken.referencedIDs`, wider than the whole-line `ids(in:)` on purpose: a line the owner
  broke by hand can be fixed again, and a kept file costs nothing). The scan and the removal run in one `Database`
  transaction, so no save slips in between. The app removes notes through `ScratchStorage.deletePermanently` and
  `purge`, never through `NoteStore`'s, or their files would stay: they read the ids of the bodies first, remove the
  notes, and then ask `removeUnreferenced` for those ids only, after the removal has committed, so a failed clean-up of
  files is not a failed delete (the launch sweep finds the leftover once it is 24 hours old, `sweep(createdBefore:)`).
  The file goes before its row, because a file with no row would stay for ever. Deleting a token and pressing ⌘Z keeps
  working because nothing removes a file when a token leaves the text.
- **A copy into the attachments folder is atomic.** `copyIn` and `writeIn` write `<id>/.copying-<uuid>` and `rename(2)`
  it onto `<id>/<sanitised file name>` (`sanitisedFileName`: `/` and `:` become `-`, trimmed, empty, `.` and `..` become
  `file`; the row keeps the name as the owner knows it), and remove the temporary file when anything fails, so the file's
  name is never a half-written copy. A link is followed (`resolvingSymlinksInPath`): the copy is the file, not another
  link. `register` does no file work, and `isCopied` is false until a copy finishes. Both belong on the storage queue.
  A fixture removes the `attachments` folder with the database it replaces.
- **`Attachment` is ambiguous in a ScratchCore test file.** Swift 6.2's Testing library has an `Attachment` of its own,
  so `Tests/ScratchCoreTests/AttachmentTestSupport.swift` declares `typealias Attachment = ScratchCore.Attachment` for the
  test module, which wins over both.
- **A paste is the plain paste, and its wrap is a second edit on a later turn** (`NoteTextView.beginPaste`, `endPaste`,
  `classifyPaste`). `paste(_:)`, `pasteAsPlainText(_:)` and `readSelection(from:)` (which the hosted tests call, and which
  Paste runs, a call inside another is the same paste) start and end the paste. Before it, the view works out whether the paste
  goes into code (`isPastingIntoCode`: a fenced block, or between the backticks of inline code, which a multi-line paste would
  split and which cannot be told afterwards). After it, the range that came in is queued with `editCount`, which every
  `didChangeText` and `load` raises, and `DispatchQueue.main.async` asks `PasteClassifier.wrap`; typing in between drops the
  paste. **The wrap waits until the paste's undo group has closed** (`undoManager.groupingLevel == 0`, retried at the run loop's
  idle moments, at most 8 times: a hosted test never ends its turn and goes ahead after that), because a `DispatchQueue.main`
  block can run in the same loop iteration as the event, and then ⌘Z would undo the paste and the wrap together
  (`CodePasteUITests.testUndoAfterCodePasteRestoresPlainText`). Hosted tests wait for `pendingPasteClassifications == 0`, not
  for a time. The wrap is one `TextEdit` that replaces the pasted range with itself between the fences: the closing fence
  has no line break before it when the paste ended with one (no blank line in the block), a fence is never added below a
  fence line that has no partner (the new pair would pair with it), and a paste that cuts a CRLF is left plain.
- **The `paste-code` interval is open until the colours are written.** `Signposts.beginOpenEditorInterval` begins it and
  `OpenInterval.endWhenIdle()` ends it, after `CodeBlockStyler.whenHighlighted` says nothing is pending and `MarkupStyler`
  has styled every chunk (a paste of more than 20,000 characters is styled in chunks, which is why `runChunk` calls
  `runHighlightedHandlersIfQuiet`). A paste that is not wrapped ends it at the next idle moment, and a wrapped one that is
  never coloured at 5 s (`pasteIntervalLimit`), so no interval stays open.
- **A click on a language label opens its menu in `NoteTextView.mouseDown`, and a hosted test must never pop it up.** A plain
  click (no ⇧, ⌘, ⌥ or ⌃) whose point is in a label's rectangle (`labelHit`, 3 pt of margin) goes to
  `showCodeBlockMenu(atViewPoint:)` and never to `super.mouseDown`, in an editable note only. `NSMenu.popUp(positioning:at:in:)`
  runs a tracking loop of its own until the menu is dismissed, so `codeBlockMenuPresenter` replaces it in a test, and a click
  is sent only after `labelHit` said the point is on a label (`CodeBlockMenuTests.testClickOnLabelOpensMenuWithoutPlacingTheCaret`).
  The label's rectangle is `MarkupLayoutManager.labelRect(forBlockAt:)`, which `drawLabel` draws in as well, so what is
  clicked is what is drawn. `labelTarget` finds the block from the character nearest to the point, and looks again a few points
  lower, because the label starts on the 6 pt hidden fence line, whose nearest character is not something to rely on, and
  ends on the first line of code. A fence with no name and no detected language has no label and so no menu.
- **The label menu's choices are `TextEdit`s on the fence lines, applied with `apply(_:)`.** `CodeBlockMenu.edit` replaces the
  name after the backticks of the opening fence (a language, or `text` for Plain Text) or replaces the whole block with the
  lines between its fences (Not Code), so no character of the code changes and each choice is one undo step. The caret goes
  through the edit (`EditMapping`): a caret in the code stays in the same place of the code. Choosing the name that is there
  is an edit of nothing, which `apply` does not register as an undo step. The menu items have `NoteTextView` as their target and
  the menu has `autoenablesItems = false`, as the Format menu does.
- **A paste or a drop is read in the order of the spec, by the code and not by AppKit** (`NoteTextView.readSelection(from:)`,
  `paste(_:)`, `pasteAsPlainText(_:)`, `performDragOperation(_:)`): file URLs first (`attachmentSources(from:)`,
  `readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`, files that exist), then any text, then
  an image with no text. `readablePasteboardTypes` lists `.fileURL`, `.png` and `.tiff` only because AppKit offers Paste
  and a drop, and validates the Paste menu item, only for a pasteboard that has a type of the list. It does not choose:
  `paste(_:)` and `pasteAsPlainText(_:)` make the attachments before they call `super`, the text path reads `.string`
  explicitly (`super.readSelection(from:type:)`), and `preferredPasteboardType(from:restrictedToTypesFrom:)` answers
  `.string` whenever there is text, so that an image next to the text (Excel, Word, browsers) can never be what AppKit reads
  (Review Focus 3). A paste that made attachments sets `attachmentPasteWasInserted`, and `endPaste` then skips the code
  classification: its text is token lines. A TIFF is converted to PNG on the main thread, which is the one cost that
  depends on the size of what is pasted; a file costs a few attributes and the header of an image, and is copied on the
  storage queue.
- **An attachment that is pasted is a line of its own, and the caret goes below it.** `AttachmentEditing.insertion` adds a
  line break before the first token unless the paste starts a line, and one after the last token unless one follows already
  (so a token at the end of the note is followed by a line break, which deviates from the plan's literal rule: the caret
  would otherwise be at the end of the token's line, where typing breaks the token). The caret ends at the start of the
  line after the last token, which is where the Backspace rule selects the token. Typing at an end of a token line still
  breaks the token (it is text then, and ⌘Z takes it back); nothing guards that.
- **A token is kept whole by the selection delegate and two key overrides, and the rules are in Core.**
  `EditorViewController.textView(_:willChangeSelectionFromCharacterRange:toCharacterRange:)` is asked for every change of
  the selection, by a key, the mouse or code, and answers `AttachmentEditing.snappedSelection` (through
  `NoteTextView.snappedSelection(from:to:)`): a caret inside a token goes to its end, or its start when it came from the
  right, and a click always to the end; a range grows to hold the whole token at either end. `deleteBackward` and
  `deleteForward` ask `AttachmentEditing.deletion` first: next to a token the first press selects it, the second removes it
  with one line break (`apply`, one undo step), and where a key would join a text line and a token line the caret only moves
  over the line break. Tokens in a fenced block are text for all of it (`isLiteral` is `styler.isInCodeBlock`). `token(touching:)`
  reads at most 51 units each way, so a selection change in a note with one huge line costs nothing. Word and line deletions
  (⌥⌫, ⌘⌫) are built on selection changes and so are snapped; a hosted test must not send a click on a token until plan 5
  task 6 handles it, because it would end in `super.mouseDown`.
- **A copy runs on the storage queue, so `persistNow()` waits for it.** `AttachmentImporter` registers the row on the main
  thread, calls `AttachmentCatalog.markCopying`, and queues `copyIn` or `writeIn` on the coordinator's storage queue, then
  `markCopied` on the main queue. A copy that is under way when the app quits or the tab changes is waited for, which is
  the point: the file is there after a relaunch. A very large copy therefore delays a tab switch (`persistNow()`); the
  alternative is a queue of its own, which would not be waited for. The launch sweep (`sweepUnreferencedAttachments`) is
  queued after the purge in the same main-queue turn, and removes only attachments created more than 24 hours ago.
