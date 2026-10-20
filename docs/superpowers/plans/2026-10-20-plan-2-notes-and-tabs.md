# Scratch Plan 2: Notes and Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scratch 0.2.0. It adds an optional title per note, a glass tab strip, a sidebar grouped Pinned / Today / Yesterday / Earlier with pinning and full-text search, delete to Recently Deleted (purged after 30 days), ⌘+/⌘−/⌘0 font size, and per-note undo that lasts the session. It also fixes the follow-ups from Plan 1's final review.

**Architecture:** New rules land in `ScratchCore` first, where they're tested on Linux:

- the search query, schema v2 with FTS5, pin and delete in the store
- `TabList`, the tab rules
- `SidebarSections` and `NoteTimeLabel`, the grouping and time labels
- `FontSize`

The AppKit shell gains:

- `EditorAreaViewController`, holding the tab strip above the editor
- `TabStripViewController`, a tab strip on `NSGlassEffectView`
- `NoteListModel`, the sidebar data and search
- `AppCommands`, the menu actions

`SessionCoordinator` moves from one tab to a `TabList`.

**Tech Stack:** as Plan 1: Swift 6.3.3, AppKit on the macOS 26 SDK (Xcode 26.6 on CI), system SQLite with FTS5, Swift Testing in core, XCTest/XCUITest in the app, XcodeGen, GitHub Actions with the `ci-results` branch.

**Spec:** [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](../specs/2026-10-19-scratchpad-design.md), sections §6.1–§6.4 (title and font size), §6.6 (undo) and §6.7. Read `AGENTS.md` first: it has the commands, the CI loop and the pitfalls Plan 1 found. Roadmap row 2: [`2026-10-19-roadmap.md`](2026-10-19-roadmap.md).

**Branch:** `plan-2-notes-and-tabs`, from `main` at `88d55f2` (0.1.0). When every task is green and approved, open one PR to `main` and merge it. The merge publishes 0.2.0.

## Global Constraints

Everything in Plan 1's Global Constraints still applies, and AGENTS.md section 5 restates them. In addition:

**Release and data**
- `VERSION` becomes `0.2.0` in Task 1, as a minor bump for features.
- No new dependency. Search uses SQLite's built-in FTS5, which Plan 1's `fts5IsAvailable` test already proves.
- The owner already has a schema-1 database full of real notes. Every schema change is a new migration step. It must keep every note, and must index existing notes for search.
- A database written by a newer Scratch (`user_version` greater than `Schema.currentVersion`) is refused, never modified.

**Notes**
- Nothing removes a note except the owner: Delete moves it to Recently Deleted, and only Recently Deleted is purged, 30 days after deletion (spec §6.7).
- Pinning, deleting and restoring never change a note's text or its `modifiedAt`. Saving a note's text never changes its pin or deletion.

**Tabs and editing**
- There is always at least one tab. A note is open in at most one tab.
- The font size is the same for every note: 13 pt by default, 9 to 32 pt in 1 pt steps, and it's remembered (spec §6.4).
- Undo history is per note and lasts for the session (spec §6.6). Switching tabs or notes must not clear it.

**Shortcuts** (spec §6.2–§6.4, §6.7; menu titles in parentheses):

| Shortcut | Action |
|---|---|
| ⌘N (New Note), ⌘T (New Tab) | new note in a new tab |
| ⌘W | Close Tab |
| ⇧⌘W | Close Window (quits) |
| ⌃Tab, ⌃⇧Tab | Show Next Tab, Show Previous Tab |
| ⌘1…⌘8 | select that tab |
| ⌘9 | select the last tab |
| ⇧⌘P | Pin/Unpin the note in the active tab |
| ⌘⌫ | delete the selected note, **only when the sidebar has focus** |
| ⌘+ (also ⌘=), ⌘−, ⌘0 | Bigger, Smaller, Actual Size |
| ⌥⌘F | focus the sidebar search |
| ⌘F | in-note find (unchanged) |
| ⌃⌘S | toggle sidebar (unchanged) |

## Review Focus

These are the inputs the spec implies but doesn't spell out that are most likely to hurt the owner. Each has a test in the task named.

1. **Pinning or deleting a note** from the sidebar while its text has unsaved typing. The pin or delete sticks and the typing is kept. Task 3: `saveDoesNotOverwritePinOrDeletion`. Task 8: `testPinWhileTypingSticks`.
2. **⌘⌫ typed in the editor** deletes text to the start of the line, as everywhere on macOS, and never the note. Task 9: `testCommandBackspaceInEditorKeepsNote`.
3. **Search text that is FTS5 syntax**: `"`, `*`, `-`, `(`, `NEAR`, `AND`, lone punctuation, emoji. It never errors, and matches the words literally. Task 2: `searchToleratesQuerySyntax`.
4. **Upgrading from 0.1.0.** The owner's schema-1 database migrates, and search finds the notes it already holds. A newer database is refused with the app's existing "cannot start" alert. Task 2: `migratingV1DatabaseIndexesExistingNotes` and `newerDatabaseIsRefused`.
5. **Closing the last tab, or deleting the note in the only tab**, leaves exactly one tab with a new empty note that isn't listed. Task 7: `testClosingLastTabLeavesEmptyNote`. Task 9: `testDeletingNoteInOnlyTabLeavesEmptyNote`.

---

## File Map

New files are marked `+`. Everything else is modified.

```
VERSION                                         0.2.0
App/project.yml                                 CURRENT_PROJECT_VERSION ${SCRATCH_VERSION}
scripts/check-version-bump.sh                   HEAD VERSION must be semver-greater than base
scripts/release-notes.sh                      + footer with <version> filled in
scripts/check-release-zip.sh                    also checks CFBundleVersion
scripts/tests/test-version-bump.sh  scripts/tests/test-release-notes.sh (+)
.github/workflows/release.yml                   existing tag + changed app = failure; notes via release-notes.sh
Packages/ScratchCore/Sources/ScratchCore/
  Storage/Schema.swift                          v2 (FTS5), refuse newer
  Notes/SearchQuery.swift                     + text → FTS5 MATCH expression
  Notes/NoteStore.swift  Notes/NoteSummary.swift  search, pin, delete, restore, purge; save keeps pin/deletion
  Session/SessionState.swift                    TabState.scrollAnchor, SessionState.fontSize
  Session/TabList.swift                       + tab rules
  Session/FontSize.swift                      + 9…32, default 13
  Sidebar/SidebarSections.swift               + Pinned/Today/Yesterday/Earlier/Recently Deleted
  Sidebar/NoteTimeLabel.swift                 + "10:42" / "Oct 14" / "Oct 14, 2025"
  Fixtures/Fixture.swift  Fixtures/FixtureContent.swift   + recently-deleted fixture
App/Sources/
  Window/AppCommands.swift                    + menu actions (target of MainMenu items)
  Window/MainMenu.swift  Window/ToolbarController.swift (pin item)  Window/MainSplitViewController.swift
  Window/EditorAreaViewController.swift       + tab strip above the editor
  Tabs/TabStripViewController.swift           + glass tab strip
  Editor/EditorViewController.swift  Editor/NoteTextView.swift  Editor/TitleField.swift (+)
  Session/SessionCoordinator.swift  Session/NoteListModel.swift (+)
  Sidebar/SidebarViewController.swift  Sidebar/SidebarTableView.swift (+)
  Support/AccessibilityID.swift  Support/DebugStateElement.swift (+)
App/Tests/ScratchAppTests/EditorViewControllerTests.swift (+)
App/Tests/ScratchUITests/ TitleUITests (+) TabsUITests (+) DeleteUITests (+) SidebarUITests ScreenshotTests UITestSupport
docs/features/ tabs.md (+) sidebar.md (+) recently-deleted.md (+) title-and-font-size.md (+) paste-and-copy.md autosave-and-restore.md
docs/architecture.md  AGENTS.md  docs/superpowers/plans/2026-10-19-roadmap.md
```

---

### Task 1: Release fixes and version 0.2.0

These are Plan 1 final-review follow-ups F1, F2, F3, F8 and F9.

**Files:**
- Modify: `scripts/check-version-bump.sh`, `scripts/tests/test-version-bump.sh`, `scripts/check-release-zip.sh`, `.github/workflows/release.yml`, `App/project.yml`, `VERSION`, `Makefile` (add `test-release-notes.sh` to `script-test`)
- Create: `scripts/release-notes.sh`, `scripts/tests/test-release-notes.sh`
- Modify: `docs/features/paste-and-copy.md` (fix the stale `makeEditor(mode:)`), `AGENTS.md` (current plan link, Releases section)

**Interfaces:**
- Produces:
  - `scripts/check-version-bump.sh <base-ref>`. Same exit codes as before, plus: exit 1 when HEAD's `VERSION` is not semver-greater than `<base-ref>:VERSION`, with the message `VERSION <head> must be greater than <base> on <base-ref>`.
  - `scripts/release-notes.sh <version>`: prints `docs/release-notes-footer.md` with every `<version>` replaced by the version. Exit 64 on usage error.
  - `release.yml`, when tag `v<VERSION>` exists: if `git diff --quiet v<VERSION> HEAD -- App Packages` succeeds, stop successfully as before. Otherwise **fail** with `::error::v<VERSION> is already released but App/ or Packages/ changed since; bump VERSION`.
  - `release.yml` passes `--notes-file` a file written by `scripts/release-notes.sh`.

- [ ] **Step 1: Write the failing script tests.**
  - Add to `test-version-bump.sh`:
    - a change under `App/` with base `0.1.1` and head `0.1.0` exits 1 (a lower version)
    - head `0.10.0` with base `0.9.0` exits 0 (numeric, not lexical)
    - head `1.0.0` with base `0.9.9` exits 0
  - In `test-release-notes.sh`:
    - `release-notes.sh 0.2.0` output contains `Scratch-0.2.0.zip` and no `<version>`
    - no argument exits 64

- [ ] **Step 2: Run them to verify they fail.** Run: `make script-test`. Expected: FAIL in the two suites.

- [ ] **Step 3: Implement.**
  - Do the semver compare in bash, field by field, as integers.
  - Write `release-notes.sh`.
  - Change the `release.yml` tag-exists branch and its notes file.
  - Set `CURRENT_PROJECT_VERSION: ${SCRATCH_VERSION}`.
  - `check-release-zip.sh` also requires `CFBundleVersion == <version>`.
  - Set `VERSION` to `0.2.0`.
  - Fix the doc drift. Point AGENTS.md "Current plan" at this file.

- [ ] **Step 4: Verify.** Run: `make script-test && make lint && make core-test`, then push. Wait with `CI_WAIT_TIMEOUT=540 scripts/ci-wait.sh <sha> linux macos`. Expected: green, and the macos job's `release-zip.log` reports version 0.2.0.

- [ ] **Step 5: Commit.** `git commit -m "Tighten version and release checks; start 0.2.0"`

---

### Task 2: Schema v2, search, and refusing newer databases

These are Plan 1 follow-up F6 and Review Focus 3 and 4.

**Files:**
- Modify: `Storage/Schema.swift`, `Notes/NoteStore.swift`
- Create: `Notes/SearchQuery.swift`
- Test: `Tests/ScratchCoreTests/SchemaTests.swift`, `SearchQueryTests.swift` (+), `NoteStoreSearchTests.swift` (+)

**Interfaces:**
- Consumes: `Database` and `NoteStore` from Plan 1.
- Produces:

```swift
public enum SchemaError: Error, Equatable { case newerThanSupported(found: Int, supported: Int) }
public enum Schema { public static let currentVersion = 2; public static func migrate(_ db: Database) throws }
public enum SearchQuery { public static func ftsExpression(_ text: String) -> String? }
extension NoteStore { public func search(_ text: String) throws -> [NoteSummary] }
```

**Schema v2.** `migrateToV2` runs when `user_version == 1` (after `migrateToV1` on a new file). Each statement is its own `execute`:

```sql
CREATE VIRTUAL TABLE notes_fts USING fts5(title, body, content='notes', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2');
CREATE TRIGGER notes_fts_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body); END;
CREATE TRIGGER notes_fts_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body); END;
CREATE TRIGGER notes_fts_au AFTER UPDATE OF title, body ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body); END;
INSERT INTO notes_fts(notes_fts) VALUES ('rebuild');
PRAGMA user_version = 2;
```

- `migrate` throws `SchemaError.newerThanSupported` **before** writing anything when `user_version > currentVersion`.
- `AppDelegate`'s existing `quit(after:)` alert shows the error. Give `SchemaError` a `LocalizedError` description: "This data was saved by a newer version of Scratch. Install the latest version from the Releases page."
- Add AGENTS.md pitfall: **never `VACUUM`**. The FTS index is keyed on the implicit `rowid`, which `VACUUM` may renumber.

**`SearchQuery.ftsExpression`:**
- Split the text on whitespace.
- Keep tokens that contain at least one letter or digit (`Character.isLetter || isNumber`).
- Quote each token: wrap it in `"`, with inner `"` doubled, then append `*` for prefix matching.
- Join the tokens with a space, which FTS5 treats as AND.
- Return nil when no token is left.

**`search`:**
- When the expression is nil, return `summaries()`.
- Otherwise run:

  ```sql
  SELECT … FROM notes
  WHERE deleted_at IS NULL
    AND rowid IN (SELECT rowid FROM notes_fts WHERE notes_fts MATCH ?)
  ```

  with the same `ORDER BY` as `summaries()`.

- [ ] **Step 1: Write the failing tests.**

```swift
// SearchQueryTests
@Test func quotesEachTokenAsPrefix() { #expect(SearchQuery.ftsExpression("kube roll") == #""kube"* "roll"*"#) }
@Test func doublesInnerQuotes() { #expect(SearchQuery.ftsExpression(#"say"hi"#) == #""say""hi"*"#) }
@Test func dropsTokensWithoutLettersOrDigits() { #expect(SearchQuery.ftsExpression("-- * ( ) \"") == nil) }
@Test func blankIsNil() { #expect(SearchQuery.ftsExpression("   ") == nil) }
```

`NoteStoreSearchTests`. Each uses a temp-file database:
- `findsWordsInTitle`, `findsWordsInBody`
- `matchesPrefixes`: "kube" finds "kubectl".
- `requiresEveryWord`
- `isCaseAndDiacriticInsensitive`: "cafe" finds "Café".
- `excludesDeletedNotes`: set `deleted_at` with SQL.
- `followsEdits`: save a new body, and the old word no longer matches while the new one does.
- `blankSearchReturnsAllSummaries`
- `searchToleratesQuerySyntax`: for each of `"`, `*`, `-x`, `(a`, `NEAR(a b)`, `a AND`, `OR`, `😀`, `"unbalanced`, `search` doesn't throw. "AND" matches a note containing the word "and".

`SchemaTests`:
- `freshDatabaseIsVersion2`
- `migratingV1DatabaseIndexesExistingNotes`: build a v1 file by running the v1 SQL by hand plus one insert, then open `NoteStore`. `userVersion() == 2`, and search finds the old note.
- `newerDatabaseIsRefused`: `PRAGMA user_version = 3`. `migrate` throws `.newerThanSupported(found: 3, supported: 2)`, and the note count is unchanged.

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure, because `SearchQuery` is undefined.

- [ ] **Step 3: Implement** `Schema` v2 and the guard, `SearchQuery`, and `NoteStore.search`.

- [ ] **Step 4: Run them to verify they pass.** Run: `make core-test && make lint`. Expected: all pass.

- [ ] **Step 5: Commit and push.** `git commit -m "Add schema v2 with full-text search; refuse newer databases"`

---

### Task 3: Pin, delete, restore, purge, and the recently-deleted fixture

This task covers Review Focus 1.

**Files:**
- Modify: `Notes/NoteStore.swift`, `Notes/NoteSummary.swift`, `Fixtures/Fixture.swift`, `Fixtures/FixtureContent.swift`
- Test: `NoteStoreTests.swift`, `NoteStoreDeletionTests.swift` (+), `FixtureTests.swift`
- Modify: `AGENTS.md` (fixture list)

**Interfaces:**
- Consumes: `NoteStore` and `Note`.
- Produces:

```swift
public struct NoteSummary { …; public let deletedAt: Date? }   // init parameter `deletedAt: Date? = nil`
extension NoteStore {
    public static let recentlyDeletedRetention: TimeInterval   // 30 * 24 * 60 * 60
    public func setPinned(_ id: NoteID, _ pinned: Bool, now: Date) throws  // pinned_at = now / NULL
    public func delete(_ id: NoteID, now: Date) throws                     // deleted_at = now
    public func restore(_ id: NoteID) throws                               // deleted_at = NULL
    public func deletePermanently(_ id: NoteID) throws                     // only WHERE deleted_at IS NOT NULL
    public func deletedSummaries() throws -> [NoteSummary]                 // deleted_at DESC, then id
    public func purge(deletedBefore cutoff: Date) throws -> Int            // rows removed
}
public enum Fixture { …; case recentlyDeleted = "recently-deleted" }
```

- `save(_:)` changes: its `ON CONFLICT(id) DO UPDATE` sets only `title`, `body`, `display_title`, `has_title`, `preview` and `modified_at`. A new row still inserts every column.
- The `recently-deleted` fixture holds:
  - "Groceries", live, edited −1 h
  - "Old meeting notes", deleted −2 days, edited −3 days
  - "Ancient", deleted −31 days, edited −40 days
  - one tab, on Groceries

- [ ] **Step 1: Write the failing tests.**
  - `saveDoesNotOverwritePinOrDeletion`: load a note, `setPinned(true)`, then `save` the stale copy with a new body. The note is still pinned and has the new body. Repeat with `delete`, where the note stays deleted.
  - `pinningDoesNotChangeModifiedAt`
  - `deleteMovesNoteOutOfSummaries`: absent from `summaries()`, present in `deletedSummaries()` with `deletedAt`.
  - `restoreBringsItBackWithPinKept`
  - `deletePermanentlyIgnoresLiveNotes`: a live note survives `deletePermanently`.
  - `purgeRemovesOnlyExpiredDeletedNotes`: deleted −31 days goes, deleted −29 days and live −400 days stay, and the result is 1.
  - `deletedSummariesNewestDeletionFirst`
  - `recentlyDeletedFixture`: 1 summary and 2 deleted summaries.

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement** the store methods, the `save` conflict clause, `NoteSummary.deletedAt` and the fixture.

- [ ] **Step 4: Run them to verify they pass.** Run: `make core-test && make lint`. Expected: all pass, and Plan 1's store tests still pass.

- [ ] **Step 5: Commit and push.** `git commit -m "Add pin, delete, restore and purge to the note store"`

---

### Task 4: Tab rules, scroll anchor, font size (core)

**Files:**
- Create: `Session/TabList.swift`, `Session/FontSize.swift`
- Modify: `Session/SessionState.swift`
- Test: `TabListTests.swift` (+), `FontSizeTests.swift` (+), `SessionStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public struct TabState { …; public var scrollAnchor: Int? }   // UTF-16 offset of the first visible character; decodeIfPresent; init param default nil
public struct SessionState { …; public var fontSize: Double }  // decodeIfPresent, default FontSize.standard; init param default FontSize.standard
public enum FontSize {
    public static let standard: Double = 13, minimum: Double = 9, maximum: Double = 32
    public static func larger(_ size: Double) -> Double   // +1, clamped
    public static func smaller(_ size: Double) -> Double  // -1, clamped
    public static func clamped(_ size: Double) -> Double
}
public enum TabOpening: Equatable, Sendable { case focused(index: Int), replaced(index: Int, previous: NoteID), inserted(index: Int) }
public enum TabClosing: Equatable, Sendable { case closed(noteID: NoteID), lastTab(noteID: NoteID) }
public struct TabList: Equatable, Sendable {
    public private(set) var tabs: [TabState]           // never empty
    public private(set) var activeIndex: Int
    public init(tabs: [TabState], activeIndex: Int)     // precondition(!tabs.isEmpty); activeIndex clamped into range
    public var active: TabState { get }
    public func index(of id: NoteID) -> Int?
    public mutating func select(_ index: Int)           // ignores out-of-range
    public mutating func selectNext()                   // wraps
    public mutating func selectPrevious()               // wraps
    public mutating func select(number: Int)            // 1…8 → that tab if it exists; 9 → last
    public mutating func open(_ id: NoteID, inNewTab: Bool) -> TabOpening
    public mutating func close(at index: Int) -> TabClosing
    public mutating func replaceNote(at index: Int, with id: NoteID)   // selection 0, scroll reset
    public mutating func updateViewState(at index: Int, selection: Int, scrollAnchor: Int)
    public func session(fontSize: Double) -> SessionState
}
```

**`open` rules:**
- If the note is already in some tab, select that tab and return `.focused`.
- Otherwise, with `inNewTab`, insert a tab right after the active one, select it, and return `.inserted`.
- Otherwise, replace the active tab's note and return `.replaced`.

**`close` rules:**
- With one tab, it returns `.lastTab` and changes nothing. The caller then calls `replaceNote`.
- Otherwise it removes the tab.
  - If the closed tab was active, the tab that now has its index becomes active, or the new last tab when it was the last one.
  - If the closed tab was before the active one, `activeIndex -= 1`.

- [ ] **Step 1: Write the failing tests.**

  `TabListTests`:
  - `openFocusesExistingTab`
  - `openInNewTabInsertsAfterActive`: tabs A,B,C with B active. Opening D gives A,B,D,C with D active.
  - `openReplacesActiveNote`: returns `.replaced(index: 1, previous: B)`.
  - `closeActiveSelectsRightNeighbour`
  - `closeLastPositionSelectsNewLast`
  - `closeBeforeActiveKeepsActiveNote`
  - `closeOnlyTabReportsLastTab`
  - `nextAndPreviousWrap`
  - `numberNineSelectsLast`
  - `numberBeyondCountIsIgnored`
  - `replaceNoteResetsViewState`
  - `initClampsActiveIndex`

  `FontSizeTests`:
  - `largerStopsAt32`
  - `smallerStopsAt9`
  - `clampedHandlesNaN`: NaN → 13.

  `SessionStoreTests`:
  - `decodesPlan1SessionWithDefaults`: JSON without `fontSize` or `scrollAnchor` gives 13 and nil.
  - `roundTripsFontSizeAndAnchor`

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement** the three files.

- [ ] **Step 4: Run them to verify they pass.** Run: `make core-test && make lint`. Expected: all pass.

- [ ] **Step 5: Commit and push.** `git commit -m "Add tab rules, font size and scroll anchor to the session model"`

---

### Task 5: Sidebar grouping and time labels (core)

**Files:**
- Create: `Sidebar/SidebarSections.swift`, `Sidebar/NoteTimeLabel.swift`
- Test: `SidebarSectionsTests.swift` (+), `NoteTimeLabelTests.swift` (+)

**Interfaces:**
- Consumes: `NoteSummary`, including `deletedAt` (Task 3).
- Produces:

```swift
public enum SidebarGroup: Equatable, Sendable { case pinned, today, yesterday, earlier, recentlyDeleted }
public struct SidebarSection: Equatable, Sendable { public let group: SidebarGroup; public let notes: [NoteSummary] }
public enum SidebarSections {
    public static func make(live: [NoteSummary], deleted: [NoteSummary], now: Date, calendar: Calendar) -> [SidebarSection]
}
public enum NoteTimeLabel {
    public static func text(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String
}
```

**Grouping rules:**
- Pinned notes, in the order given, form `.pinned`.
- Unpinned notes are grouped by the **calendar day** of `modifiedAt` in `calendar`:
  - the same day as `now`, or later (clock skew), is `.today`
  - the previous calendar day is `.yesterday`
  - anything older is `.earlier`
- Empty sections are omitted.
- `.recentlyDeleted` comes last, and only when `deleted` isn't empty.

**Time labels:**
- Today and yesterday use the time of day: the `DateFormatter` template `"jmm"` in `locale`.
- The same year uses the template `"MMMd"`.
- Older dates use `"yMMMd"`.

- [ ] **Step 1: Write the failing tests.** The calendar's time zone is `Europe/Oslo`.
  - `groupsByCalendarDayNotTwentyFourHours`: now is 2026-10-19 09:00. A note at 00:30 the same day is today. 23:30 the day before is yesterday. 2026-10-17 is earlier.
  - `dstChangeStillUsesCalendarDays`: now is 2026-10-26 00:30, after the 2026-10-25 change. A note at 2026-10-25 01:00 is yesterday.
  - `pinnedSectionFirstInGivenOrder`
  - `emptyGroupsOmitted`
  - `recentlyDeletedLastOnlyWhenNonEmpty`
  - `futureDateCountsAsToday`

  `NoteTimeLabelTests`:
  - `timeOfDayForToday`: `en_GB` gives `"10:42"`.
  - `timeOfDayForYesterdayInUSLocale`: `en_US` contains `"10:42"` and `"AM"`.
  - `monthAndDayThisYear`: `en_US` gives `"Oct 14"`.
  - `includesYearForOlderDates`: `en_US` gives `"Oct 14, 2025"`.

- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure.

- [ ] **Step 3: Implement** both files.

- [ ] **Step 4: Run them to verify they pass.** Run: `make core-test && make lint`. Expected: all pass on Linux. Expect them to pass on macOS CI too, because ICU formats the same on both.

- [ ] **Step 5: Commit and push.** `git commit -m "Add sidebar grouping and time labels"`

---

### Task 6: Editor: title field, font size, per-note undo, scroll anchor

These are Plan 1 follow-ups F4 and F5.

**Files:**
- Create: `App/Sources/Editor/TitleField.swift`, `App/Sources/Window/AppCommands.swift`, `App/Sources/Support/DebugStateElement.swift`
- Modify: `App/Sources/Editor/EditorViewController.swift`, `App/Sources/Editor/NoteTextView.swift`, `App/Sources/Window/MainMenu.swift`, `App/Sources/Session/SessionCoordinator.swift`, `App/Sources/AppDelegate.swift`, `App/Sources/Support/AccessibilityID.swift`
- Test: `App/Tests/ScratchAppTests/EditorViewControllerTests.swift` (+), `App/Tests/ScratchUITests/TitleUITests.swift` (+), `App/Tests/ScratchUITests/UITestSupport.swift`
- Create: `docs/features/title-and-font-size.md`. Modify: `docs/features/autosave-and-restore.md` (scroll and undo), `AGENTS.md`

**Interfaces:**
- Consumes: `TabState.scrollAnchor`, `SessionState.fontSize` and `FontSize` (Task 4).
- Produces:

```swift
// EditorViewController
var onTitleChange: ((String) -> Void)?
func show(_ note: Note, tab: TabState, undoManager: UndoManager, isReadOnly: Bool)
var currentScrollAnchor: Int { get }   // UTF-16 offset of the first character at the top of the visible text
func setFontSize(_ size: Double)       // body = NoteTextView.noteFont(size:), title = bold SF Mono size + 3
func focusTitle()
// NoteTextView
static func noteFont(size: Double) -> NSFont   // monospacedSystemFont(ofSize:weight: .regular); noteFont stays the 13 pt one
// AppCommands: NSObject — the target of app-level menu items. Closures are set by AppDelegate.
var onBigger: (() -> Void)?; var onSmaller: (() -> Void)?; var onActualSize: (() -> Void)?
@objc func bigger(_:) / smaller(_:) / actualSize(_:)
// MainMenu
static func install(in application: NSApplication, commands: AppCommands)
// SessionCoordinator (additions)
func changeFontSize(_ transform: (Double) -> Double)   // applies to editor, saves session
// AccessibilityID
static let titleField = "editor.titleField"; static let debugState = "debug.state"
```

**Behaviour:**
- **Title field.** `TitleField` is a borderless, single-line `NSTextField` above the editor's scroll view in the editor's own view. It doesn't scroll with the text [call].
  - Font: bold SF Mono at the note size + 3. The placeholder is "Untitled" in the placeholder colour.
  - Return or Tab moves focus to the body (`focusBody`).
  - Each edit calls `onTitleChange`. The coordinator sets `note.title`, sets `modifiedAt`, and marks the autosaver dirty.
- **Per-note undo.**
  - The coordinator keeps `[NoteID: UndoManager]` for the session.
  - `show` calls `textView.breakUndoCoalescing()` before replacing the text, and stores the given manager. The editor returns it from `NSTextViewDelegate.undoManager(for:)`.
  - `show` no longer calls `removeAllActions()`.
  - Loading a note's text never registers undo, as in Plan 1.
- **Scroll anchor.**
  - `show` scrolls so the line containing `tab.scrollAnchor` is at the top, below `contentInsets.top`. Without an anchor it uses the old `scrollY` path.
  - It does so at once when the view is in a laid-out window. Otherwise it keeps the anchor and applies it in the next `viewDidLayout`. It lays out the text up to the anchor with `layoutManager.ensureLayout(forCharacterRange:)`.
  - `currentScrollAnchor` asks the layout manager for the character at the top-left of the visible text.
  - The coordinator saves `scrollAnchor` in the tab.
- **Read-only.** `isReadOnly` makes both the text view and the title field non-editable (Task 9 uses it).
- **Font size.** It's stored in the session. Bigger is ⌘+ and ⌘=, Smaller is ⌘−, Actual Size is ⌘0, all in the View menu, targeting `AppCommands`. Typing attributes follow the size, so pasted text takes it.
- **`DebugStateElement`.** Only when `options.isIsolated`, the window's content view gets a 1×1 point, alpha-0 view with the accessibility identifier `debug.state`. Its accessibility value is JSON `{"fontSize": 13, "scrollAnchor": 0, "readOnly": false}`, refreshed on every editor or session change.
  - If XCUITest can't see an alpha-0 view, use a 1×1 transparent view instead. Never show it in screenshots.
  - UI tests read it with `UITestSupport.debugState(in:) -> [String: Any]`.

- [ ] **Step 1: Write the failing hosted tests** (`EditorViewControllerTests`, `@MainActor`, editor hosted in an 800×600 window):
  - `testScrollAnchorRoundTrips`:
    1. Show a 10,000-line text with an anchor at the start of line 5,000.
    2. Run `layoutSubtreeIfNeeded()`.
    3. The line of `currentScrollAnchor` is 5,000.
  - `testFontSizeAppliesToTextTypingAndTitle`: after `setFontSize(16)`, every run is SF Mono at 16, typing attributes are at 16, and the title font is 19 and bold.
  - `testPasteAfterFontSizeChangeUsesNewSize`
  - `testUndoHistoryIsPerNote`:
    1. Show A with manager `UA` and insert "x" through `insertText`.
    2. Show B with `UB`.
    3. Show A with `UA` again.
    4. `UA.canUndo` is true, and `UA.undo()` restores A's original text.
  - `testShowDoesNotClearUndo`
  - `testReadOnlyRejectsTyping`: `insertText` leaves the text unchanged.
  - `testReturnInTitleFocusesBody`

  `TitleUITests`:
  - `testTitleBecomesSidebarTitle`: new note, type the title "Groceries 2", Return, type "milk". A sidebar row is titled "Groceries 2", and the editor value is "milk".
  - `testTitleSurvivesRelaunch`
  - `testFontSizeIsRemembered`: ⌘= twice, ⌘Q, relaunch. `debugState["fontSize"] == 15`.
  - `testScrollPositionSurvivesRelaunch`:
    1. Use the `huge-note` fixture and scroll the editor by −20,000 points (`scroll(byDeltaX:deltaY:)`).
    2. Wait 1.5 s and read the anchor A1, which must be > 0.
    3. ⌘Q, relaunch, and wait for the editor.
    4. The anchor equals A1 to within one line, and is > 0.

- [ ] **Step 2: Push, then wait.** Expected: the macos job fails, because the new API doesn't compile or the new tests fail.

- [ ] **Step 3: Implement** the files above. Rename the existing `show(_:selection:scrollY:)` callers in the coordinator and in `FrameMonitor`, if it uses it.

- [ ] **Step 4: Push, then wait.** Expected: all app tests pass, and Plan 1's still pass.

- [ ] **Step 5: Docs and commit.** Write `title-and-font-size.md`, update the autosave doc and AGENTS.md, then `git commit -m "Add the title field, font size, per-note undo and scroll anchors"`.

---

### Task 7: Tabs

This covers Plan 1 follow-up F7 and Review Focus 5.

**Files:**
- Create: `App/Sources/Tabs/TabStripViewController.swift`, `App/Sources/Window/EditorAreaViewController.swift`
- Modify: `SessionCoordinator.swift`, `MainSplitViewController.swift` (the content item becomes `EditorAreaViewController`), `SidebarViewController.swift` (`onSelect` becomes `onOpen` with ⌘-click), `AppCommands.swift`, `MainMenu.swift`, `ToolbarController.swift` (new note opens a tab), `AppDelegate.swift`, `AccessibilityID.swift`, `UITestSupport.swift`
- Test: `App/Tests/ScratchUITests/TabsUITests.swift` (+). Modify `SidebarUITests.swift` only where a test assumed one tab.
- Create: `docs/features/tabs.md`

**Interfaces:**
- Consumes: `TabList`, `TabOpening` and `TabClosing` (Task 4), and the editor `show(_:tab:undoManager:isReadOnly:)` (Task 6).
- Produces:

```swift
struct TabStripItem: Equatable { let title: String; let hasTitle: Bool; let isDeleted: Bool }
final class TabStripViewController: NSViewController {
    var onSelect: ((Int) -> Void)?; var onClose: ((Int) -> Void)?; var onNewTab: (() -> Void)?
    func show(_ items: [TabStripItem], activeIndex: Int)
}
final class EditorAreaViewController: NSViewController {   // tab strip on top (below the safe area), editor below
    init(tabStrip: TabStripViewController, editor: EditorViewController)
}
// SessionCoordinator (replaces newNote/open)
func newNoteInNewTab()
func open(_ id: NoteID, inNewTab: Bool)
func closeTab(at index: Int); func closeActiveTab()
func selectTab(at index: Int); func selectNextTab(); func selectPreviousTab(); func selectTab(number: Int)
// AppCommands (additions): onNewNote, onCloseTab, onNextTab, onPreviousTab, onSelectTabNumber: ((Int) -> Void)?
// SidebarViewController: `onSelect` is replaced by
var onOpen: ((NoteID, Bool) -> Void)?        // (id, inNewTab)
// AccessibilityID: tabItem = "tab.item", tabClose = "tab.close", tabNew = "tab.new"
// UITestSupport: tabs(in:) -> [XCUIElement] (sorted by minX), tabTitles(in:) -> [String], activeTabTitle(in:) -> String?
```

**Behaviour:**
- **Tab strip.**
  - It's an `NSGlassEffectView` whose `contentView` is a horizontal stack of tab buttons plus a trailing "+" button (`tab.new`). The corner radius is 14 and the height 32.
  - It sits at the top of `EditorAreaViewController`, below the toolbar safe area, with 12 pt side margins. The editor goes below it.
- **Each tab** is a button (`tab.item`):
  - Its label is the note's `displayTitle`, or "Untitled". Bold system font when titled, `NoteTextView.noteFont` otherwise. Deleted notes are dimmed.
  - Its width is 120 to 200 pt, truncating the title.
  - It has a close button (`tab.close`).
  - The active tab has `setAccessibilitySelected(true)` and a raised look.
- **Coordinator.**
  - Before leaving a tab it records `updateViewState` for that tab: the current selection and `currentScrollAnchor`.
  - It shows the target tab's note with that tab's `TabState` and the note's undo manager.
  - A leaving note that is untouched is discarded when its tab closes, or when another note replaces it in the tab (Plan 1 rule).
- **Last tab.** `.lastTab` creates a new empty note, untouched, and calls `replaceNote`.
- **Restore.** It builds a `TabList` from the saved tabs whose notes exist and aren't deleted, keeping their order. The active tab is the saved one if it survived, else the first. If no tab survived, it creates a new note.
- **Session saves (F7).** After every open, close or select, the coordinator enqueues a session write on the storage queue at once instead of waiting for the autosaver. The current note's dirty text is still written by the autosaver or by `persistNow`.
- **Menus.**
  - File: New Note ⌘N, New Tab ⌘T, Close Tab ⌘W, Close Window ⇧⌘W (`performClose`).
  - Window: Show Next Tab ⌃Tab (key `"\t"` with `.control`), Show Previous Tab ⌃⇧Tab, and Select Tab 1–9 with ⌘1…⌘9 (`tag` = number).
  - The toolbar's new-note button calls `newNoteInNewTab`.
- **Signposts.** Selecting a tab begins `switch-note`, the same interval as opening a note.
- **Opening from the sidebar.**
  - The sidebar opens notes from the table's click `action`, not the selection change.
  - With ⌘ held (`NSApp.currentEvent?.modifierFlags.contains(.command)`), it calls `onOpen(id, true)`. Otherwise `onOpen(id, false)`.
  - Keyboard selection with the arrow keys plus Return opens in the current tab.

- [ ] **Step 1: Write the failing UI tests** (`TabsUITests`, fixture `typical` with 2 tabs unless noted):
  - `testRestoresBothTabsWithFirstActive`: titles `["Deploy checklist", "curl -X POST https://api.local/v1/notes \"]`, and the active title is "Deploy checklist". The second title is the untitled curl note's first line, exactly as the sidebar shows it.
  - `testCommandTOpensNewEmptyTab`: there are 3 tabs, the third is active, and the editor is empty.
  - `testClosingTabKeepsNote`: activate tab 2, ⌘W. One tab, and the sidebar still lists the curl note.
  - `testClosingLastTabLeavesEmptyNote`: ⌘W twice. One tab titled "Untitled", the editor is empty, and there are 6 sidebar rows.
  - `testCommandClickOpensNoteInNewTab`: ⌘-click "Groceries". Three tabs, and the active one is "Groceries".
  - `testClickingNoteOpenInOtherTabFocusesIt`: with tab 1 active, click the curl row. Still 2 tabs, and tab 2 is active.
  - `testControlTabCyclesAndWraps`
  - `testCommandNineSelectsLastTab`
  - `testTabsAndActiveTabSurviveRelaunch`: ⌘T, type "third", ⌘Q, relaunch. Three tabs, with the third active.
  - `testUndoSurvivesTabSwitch`:
    1. In tab 1, type `zzz`.
    2. ⌃Tab, then ⌃⇧Tab.
    3. ⌘Z. The editor value doesn't contain `zzz`.
  - `testUntypedNewTabIsDiscardedOnClose`: ⌘T, then ⌘W. Still 6 sidebar rows.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement** the files above.

- [ ] **Step 4: Push, then wait.** Expected: all app tests pass. Check the screenshots' tab strip against mockup B (`docs/superpowers/specs/2026-10-19-scratchpad-mockup.html`, variant B) with the Read tool.

- [ ] **Step 5: Docs and commit.** Write `docs/features/tabs.md`, update AGENTS.md (module map, pitfalls), then `git commit -m "Add tabs"`.

---

### Task 8: Sidebar groups, time labels, search and pinning

This covers Review Focus 1 on the app side.

**Files:**
- Create: `App/Sources/Session/NoteListModel.swift`, `App/Sources/Sidebar/SidebarTableView.swift`
- Modify: `SidebarViewController.swift`, `SessionCoordinator.swift`, `ToolbarController.swift` (pin item), `AppCommands.swift`, `MainMenu.swift`, `MainSplitViewController.swift` (`splitView.autosaveName = "MainSplit"` only when not isolated: spec §6.1 remembers the sidebar width), `AppDelegate.swift`, `AccessibilityID.swift`
- Test: `SidebarUITests.swift`
- Create: `docs/features/sidebar.md`

**Interfaces:**
- Consumes:
  - `SidebarSections` and `NoteTimeLabel` (Task 5).
  - `NoteStore.search` (Task 2).
  - `setPinned` and `deletedSummaries` (Task 3).
  - Coordinator `open(_:inNewTab:)` and the sidebar's `onOpen` (Task 7).
- Produces:

```swift
// SidebarViewController
func reload(_ sections: [SidebarSection], selecting: NoteID?, recentlyDeletedExpanded: Bool, now: Date)
var onSearch: ((String) -> Void)?
var onTogglePin: ((NoteID) -> Void)?
func focusSearch()
// NoteListModel (@MainActor; reads on the coordinator's storage queue, stale results dropped by request number)
init(storage: ScratchStorage, storageQueue: DispatchQueue, sidebar: SidebarViewController)
func refresh()                      // re-reads live (or search results) and deleted summaries
func setSearchText(_ text: String)
var hiddenNoteID: NoteID?           // the untouched note, never listed
var selectedNoteID: NoteID?
// SessionCoordinator
func togglePin(_ id: NoteID); func togglePinOfActiveNote()
// ToolbarController: pin item `toolbar.pin`, image "pin" / "pin.fill"; func setPinned(_ pinned: Bool, enabled: Bool)
// AppCommands: onTogglePin, onFocusSearch
// AccessibilityID: sidebarSearch = "sidebar.search", sidebarGroup = "sidebar.group", sidebarRowTime = "sidebar.row.time", pinButton = "toolbar.pin"
```

**Behaviour:**
- **Sidebar layout.** An `NSSearchField` (`sidebar.search`, placeholder "Search") sits above the table.
- **Group rows** (`isGroupRow`, identifier `sidebar.group`) are titled "Pinned", "Today", "Yesterday", "Earlier" or "Recently Deleted". Clicking a group row does nothing, except Recently Deleted (Task 9).
- **Note rows** keep Plan 1's look and add the time label (`sidebar.row.time`) on the right.
- **Search.**
  - Each keystroke in the search field calls `onSearch`, which runs `search` on the storage queue and drops stale results.
  - While searching, the sections are built from the results, without Recently Deleted.
  - Clearing the field, or Escape, restores the full list.
- **Pinning.**
  - The row context menu has "Pin" or "Unpin". The toolbar pin item and ⇧⌘P act on the active tab's note.
  - Pinning calls `setPinned` on the storage queue, then `refresh`. The note's text and `modifiedAt` are untouched.
  - The toolbar pin image follows the active note, and is disabled for a deleted note.
- **Refreshing.** The groups are recomputed with `Date()` and `.current` on every refresh, and `applicationDidBecomeActive` triggers a refresh, so "Today" rolls over at midnight.

- [ ] **Step 1: Write the failing UI tests.**
  - `testGroupHeadersInOrder`: typical gives Pinned, Today, Yesterday, Earlier.
  - `testPinButtonMovesNoteToPinned`: open "Groceries", click `toolbar.pin`. The first two rows are "Groceries" and "Snippets I keep reusing" (pinned, newest edit first).
  - `testShiftCommandPTogglesPin`
  - `testContextMenuUnpins`: right-click "Snippets…", Unpin. The "Pinned" header is gone.
  - `testPinWhileTypingSticks`: type "x" in Deploy checklist and immediately click pin. After 2 s, ⌘Q and relaunch. It's still pinned, and its text has the "x".
  - `testSearchFiltersByBodyText`: "kubectl" leaves only "Deploy checklist".
  - `testSearchMatchesTitlesCaseInsensitively`: "GROCER".
  - `testClearingSearchRestoresList`
  - `testRowShowsTimeLabel`: the "Groceries" row has a non-empty `sidebar.row.time`.
  - Update the existing `testSidebarListsFixtureNotesPinnedFirst` so it ignores group rows.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement** the files above. `NoteListModel` takes over Plan 1's summaries logic from `SessionCoordinator` (`latestSummaries`, `summariesRequest`, `renderSidebar`).

- [ ] **Step 4: Push, then wait.** Expected: all green.

- [ ] **Step 5: Docs and commit.** Write `docs/features/sidebar.md`, update AGENTS.md, then `git commit -m "Group the sidebar, add search and pinning"`.

---

### Task 9: Delete and Recently Deleted

This covers Review Focus 2 and 5.

**Files:**
- Modify: `SidebarViewController.swift`, `SidebarTableView.swift`, `NoteListModel.swift`, `SessionCoordinator.swift`, `AppDelegate.swift`, `AppCommands.swift`, `MainMenu.swift`
- Test: `App/Tests/ScratchUITests/DeleteUITests.swift` (+)
- Create: `docs/features/recently-deleted.md`

**Interfaces:**
- Consumes:
  - `delete`, `restore`, `deletePermanently`, `purge`, `deletedSummaries` and `recentlyDeletedRetention` (Task 3).
  - `TabList.index(of:)`, `close(at:)` and `replaceNote(at:with:)` (Task 4).
  - The editor's `isReadOnly` (Task 6).
- Produces:

```swift
// SidebarViewController
var onDelete: ((NoteID) -> Void)?; var onRestore: ((NoteID) -> Void)?; var onDeletePermanently: ((NoteID) -> Void)?
var onToggleRecentlyDeleted: (() -> Void)?
// SidebarTableView: NSTableView — keyDown: ⌘⌫ on a selected live note → onDelete; on a deleted note does nothing
// SessionCoordinator
func deleteNote(_ id: NoteID); func restoreNote(_ id: NoteID); func deleteNotePermanently(_ id: NoteID)
func purgeExpiredNotes(now: Date)   // storage queue; at launch after the first frame, and on becoming active ≥ 1 h after the last purge
// AccessibilityID: recentlyDeletedHeader = "sidebar.recentlyDeleted"
```

**Behaviour:**
- **Deleting.** "Delete" is in a live row's context menu. ⌘⌫ deletes too, but only through `SidebarTableView.keyDown`, never as a menu key equivalent, because menu key equivalents would steal ⌘⌫ from the text view.
  - Deleting closes the tab showing the note. If that was the only tab, it gets a new empty note.
  - Then it refreshes the lists.
- **The Recently Deleted header** (`sidebar.recentlyDeleted`) reads "Recently Deleted (N)". It starts collapsed, and clicking it toggles the rows below it. The expanded state isn't saved [call].
- **Deleted rows** have a context menu with "Restore" and "Delete Permanently…".
- **Delete Permanently** shows a sheet: "Delete “<title>” permanently? This can't be undone." with the buttons "Delete" (destructive) and "Cancel" [call].
- **Viewing a deleted note.** Clicking a deleted row opens it read-only in the current tab: the editor and title can't be edited, the tab is dimmed, and the pin is disabled. Restoring makes it editable in place.
- **Relaunch.** A tab showing a deleted note is dropped at relaunch (Plan 1 rule).
- **Purge.** It runs at launch, one main-queue turn after `restore()`, and on `applicationDidBecomeActive` when the last purge was ≥ 1 h ago. A purged note open in a tab closes that tab.

- [ ] **Step 1: Write the failing UI tests.**
  - `testContextMenuDeleteMovesNoteToRecentlyDeleted`: typical, delete "Groceries". It's not among the live rows, and the header reads "Recently Deleted (1)".
  - `testCommandBackspaceInSidebarDeletes`: click the "Groceries" row, then ⌘⌫.
  - `testCommandBackspaceInEditorKeepsNote`:
    1. In the editor of Deploy checklist, type `abc` at the end of the first line.
    2. Press ⌘⌫.
    3. Still 6 live rows, and the editor's first line no longer ends with `abc`.
  - `testDeletingOpenNoteClosesItsTab`: delete the curl note. One tab.
  - `testDeletingNoteInOnlyTabLeavesEmptyNote`: ⌘W, so one tab on Deploy, then delete Deploy. One tab "Untitled", the editor is empty, and there are 5 live rows.
  - `testRestoreBringsNoteBack`
  - `testDeletePermanentlyAsksThenRemoves`: expand, Delete Permanently…, click "Delete". The header is gone (0 deleted).
  - `testDeletedNoteIsReadOnly`: open a deleted note and type "q". The value is unchanged.
  - `testExpiredNotesArePurgedAtLaunch`: fixture `recently-deleted`, expand. Only "Old meeting notes" is listed, and "Ancient" is absent.

- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.

- [ ] **Step 3: Implement** the files above.

- [ ] **Step 4: Push, then wait.** Expected: all green.

- [ ] **Step 5: Docs and commit.** Write `docs/features/recently-deleted.md`, update AGENTS.md, then `git commit -m "Add delete and Recently Deleted"`.

---

### Task 10: Screenshots, performance, release 0.2.0

**Files:**
- Modify: `App/Tests/ScratchUITests/ScreenshotTests.swift`, `Makefile` (`SCREENSHOT_NAMES`), `docs/architecture.md` (tabs, the note list model, the data flow), `AGENTS.md`, `docs/superpowers/plans/2026-10-19-roadmap.md` (Plan 2 done)

**Interfaces:**
- Consumes: everything above.
- Produces:
  - The screenshots `typical-light`, `typical-dark`, `empty-light`, `huge-note-light`, `search-light` (typical, search "kube") and `recently-deleted-light` (fixture `recently-deleted`, section expanded).
  - Release `v0.2.0`.

- [ ] **Step 1: Add the two screenshot tests and their names.** Push and wait. Fetch the results, and open every PNG with the Read tool.

  Expected:
  - Glass tab strip with two tabs.
  - Sidebar with a search field, group headers, time labels and a pinned row.
  - Bold title field above the body.
  - Dark mode correct.

  List any mismatch with mockup B, ignoring the formatting, which is Plan 3, as a fix in this task.

- [ ] **Step 2: Check performance.** Read `macos/perf/report.md` for the final head.
  - Expected: no `FAIL`.
  - If `switch_*` or `launch_ms` regressed more than 20% against the baseline, find the cause in this plan's changes, such as session writes or list refreshes on the main thread, and fix it. Don't raise the baseline.

- [ ] **Step 3: Whole-branch review, PR, merge.** Open the PR `plan-2-notes-and-tabs` → `main`, titled "Scratch 0.2.0: notes and tabs". Merge once CI is green, then check that `v0.2.0` is released with `Scratch-0.2.0.zip`.
