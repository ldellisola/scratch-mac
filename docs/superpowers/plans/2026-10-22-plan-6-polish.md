# Scratch Plan 6: Polish and Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scratch 1.0.0. Scratch is fast on the owner's Mac and can prove it, works with VoiceOver, Increase Contrast and the keyboard, looks like mockup B, has a real icon, and the 0.5.0 follow-ups are fixed.

- **Launch speed:** the app records how long each of its own launches took. Help > Launch Times… shows the record and copies it, so the owner can run the cold-boot check that the spec leaves to "someone at a real Mac" (§7).
- **CI performance check:** CI stops failing on a slow runner. Launch is gated on Scratch's own work: its launch minus that of an empty AppKit app built by the same job. Idle CPU gets the measurement it never had, and the baseline is measured again.
- **Launch work:** before the first frame, the launch reads only the active tab's note (spec §7). A pasted block's colours are requested before the block exists.
- **Look:** the tab strip sits in the toolbar row as in the mockup. Lines have air between them, inline code is a pill, and code blocks have a border. Sidebar rows and tabs show text without markers. There is an app icon.
- **Accessibility:**
  - VoiceOver hears "checked", "image, dashboard.png" and "code block, Swift" where the note has markers and tokens.
  - Every mouse-only action also has a menu item.
  - Every custom colour has an Increase Contrast variant.
- **0.5.0 follow-ups:**
  - Typing next to an attachment, or dragging a selection that holds one, no longer breaks it.
  - A copied image survives Scratch quitting.
  - ⌘B with a caret bolds the word.
  - A double-click on a checkbox ticks it once.
  - Composed (IME) text keeps its underline.
  - Title undo stays with its note.

**Architecture:**
- **Core:**
  - The new rules: `LaunchLog`, the plain line for titles, ⌘B on a caret and on several lines, ⇧⌘U, and where a line break goes next to a token.
  - Schema v4 works out the titles and previews again.
- **App:**
  - Measures the launch (`LaunchClock`, `LaunchTimer`) and writes the log after the first frame.
  - Moves the tab strip into an `NSToolbarItem`.
  - Draws the pill and the border in `MarkupLayoutManager`.
  - Speaks the note through `accessibilityString(for:)`.
- **CI:** gets a `LaunchReference` app target, an idle monitor and two derived metrics, and `perf-check.py` learns about tolerances and report-only metrics.

**Tech Stack:** as Plan 5. There is no new runtime dependency. The icon is drawn by a script that uses Pillow, a development tool only, recorded in ADR 0010.

**Spec:** [`docs/superpowers/specs/2026-10-19-scratchpad-design.md`](../specs/2026-10-19-scratchpad-design.md):
- §7, every budget, the cold boot and idle
- §6.1, Reduce Transparency, Increase Contrast and mockup B
- §4, visible lag and lost text
- §6.4–§6.5, the follow-ups
- §8.2, the app icon
- §10

Read `AGENTS.md` first. Its pitfalls on the tab strip's width, null glyphs, hosted-test clicks, undo groups, `persistNow`, the derived title columns (a change needs a migration) and `AttachmentEditing` all apply here. Roadmap row 6: [`2026-10-19-roadmap.md`](2026-10-19-roadmap.md).

**Branch:** `plan-6-polish`, from `main` at 0.5.0. One PR at the end, which publishes 1.0.0 (DMG and zip).

## Global Constraints

Everything in Plans 1–5 still applies (AGENTS.md section 5). In addition:

**Release**
- `VERSION` becomes `1.0.0` in Task 1.

**Launch** (spec §7)
- Before the first frame, the launch reads the body of the active tab's note and no other.
- The launch log is read and written on a background queue after the first frame, never on the main thread before it.
- A log that is missing, corrupt or not writable changes nothing about the launch.

**Launch log** [call]
- **File:** `<data directory>/launch-times.json`, keeping the newest 50 records.
- **Record:** the date, the app version, the boot time, and the milliseconds from the process start to each phase:
  - `main`: `main.swift` begins
  - `storage`: the storage is open
  - `restore`: the session is restored
  - `window`: the window is shown
  - `firstFrame`: the main run loop is next idle after the window is shown, which is "on screen and accepting keystrokes"
- **First after start-up:** a record is this when no earlier record in the log has the same boot time.

**Performance in CI** [calls, ADR 0009]
- **`launch_overhead_ms`:** `launch_ms` minus `launch_reference_ms`, both medians of 10 launches. It has a budget of 150. Its tolerance is 60: it fails above 1.2 × baseline + 60, or above 300.
- **`launch_ms` and `launch_reference_ms`:** reported, never failing.
- **`idle_cpu_pct`:** the app's CPU over 5 s of idle (window open, caret blinking), as a percentage of one core. Budget 1.0, tolerance 0.5.
- **Everything else:** budgets stay, and the tolerance is 0.
- **Baseline:** measured again in Task 10, as the slowest of three CI runs of the final app (ADR 0003).
- No metric may `FAIL` on the PR's head.

**Look** [calls, ADR 0010]
- **Tab strip:** in the toolbar row, after the sidebar's tracking separator.
- **Toolbar:** the toolbar's buttons right-aligned in two glass groups: [pin, paperclip] and [new note].
- **Line spacing:** `round(0.3 × font size)` pt after every line, so 4 pt at 13 pt. Fence lines (6 pt) and attachment lines keep their fixed heights.
- **Inline code:** a pill, `CodeBackground`, corner radius 4, 2 pt of padding left and right. It has no `.backgroundColor` attribute.
- **Code blocks:**
  - Corner radius 8.
  - A 1 pt border in a new `CodeBorder` colour: light black 8%, dark white 12%, high contrast 35% and 45%.
- **Checkboxes:** an open box is drawn in `secondaryLabelColor`, and a ticked one stays filled with `controlAccentColor`.
- **Titles:** sidebar rows and tabs show a line as the editor shows it, outside a block:
  - a list line without its marker
  - bold and inline code without their markers
  - lines inside a fenced block kept as typed

**Accessibility** [calls]
- **Increase Contrast:** every colour asset has a high contrast variant. `-ScratchAppearance` also takes `light-contrast` and `dark-contrast` (`NSAppearance.Name.accessibilityHighContrastAqua` and `…DarkAqua`), for screenshots.
- **Reduce Transparency:** stays the system's. Only system materials are translucent.
- **VoiceOver:** `NoteTextView.accessibilityString(for:)` and `accessibilityAttributedString(for:)` speak the rendered note:

  | In the note | Spoken |
  |---|---|
  | hidden and revealed markers | nothing |
  | a bullet marker | "bullet" |
  | `[ ]` | "unchecked" |
  | `[x]` | "checked" |
  | an image token | "image, <name>" |
  | a file token | "file, <name>" |
  | a missing token | "missing attachment" |
  | an opening fence | "code block, <label>", or "code block" with no label |
  | a closing fence | "end of code block" |

  `accessibilityValue` stays the stored text, so ranges and the caret agree with the text.
- **Keyboard paths:** every mouse-only action has one.
  - Format > Mark as Checked (⇧⌘U).
  - The editor's context menu holds Mark as Checked, Open Link, Open Attachment and a Code Block Language submenu, each where it applies.

**Editing** [calls, ADR 0010]
- **⌘B with a caret:**
  - in or at the edge of a word outside a run: wraps the word, and the caret stays at its place in the word
  - in a run (its content, or touching it): unwraps the run
  - between an empty `****`: removes it
  - elsewhere: inserts `****`
- **⌘B with a selection:**
  - of several lines: wraps each line's content separately (after its list marker, white space at its ends excluded, blank lines skipped), or unwraps them all when every one is a run
  - of only white space: does nothing and beeps
- **⇧⌘U:** ticks every checklist line under the selection when any is open, else unticks them all. A selection with none beeps, and so does one in a code block.
- **Double-click on a box:** ticks it once. The second click of a double-click on a box is taken and does nothing.
- **Composed text:** marked (IME) text keeps `markedTextAttributes` while the styler restyles its paragraph.
- **Title undo:** leaving a note ends the title's editing and drops the title's undo steps. Undo never changes another note's title and never crashes.

**Attachments** [calls, ADR 0010]
- **Typing or pasting next to a token:** no token line ever shares its line with other characters.
  - Typing, composing or pasting text at the end of a token line puts a line break before the text.
  - At its start, a line break goes after the text.
  - A token line inside the inserted text gets the line breaks that keep it whole.
- **Copy, Cut and drag of a selection that holds a token:**
  - They also write the private type `io.github.ldellisola.Scratch.note-text`, the selection exactly as stored.
  - Paste and drop into Scratch prefer it, first, before file URLs. So a drag that moves text within a note, or a copy into another note, keeps the attachment, and both notes then name the same file.
  - Into a code block they use the plain text with names, as before.
  - Other apps still see plain text only.
- **Quitting:** when Scratch quits while the general pasteboard still holds its copy of one image, it writes that copy again with the PNG and TIFF data in place, so the image can still be pasted after Scratch has gone.

## Review Focus

These are the inputs the spec implies that are most likely to hurt the owner. Each has a test in the task named.

1. **Upgrading from 0.5.0** with notes whose first line is `[ ] …`, `- …` or `**…**`.
   - The rows show the text without markers.
   - The order, `modified_at` and the search results are unchanged, and nothing is lost.
   - Task 4: `migratingV3StripsMarkersFromTitles`.
2. **Typing, composing or pasting at either edge of an attachment line** never turns the token into text.
   - Task 6: `testTypingAtTheEndOfATokenLineGoesBelowIt`, `testComposingAtATokenEdgeKeepsTheToken`, and the core test `lineBreakGoesBetweenTypingAndAToken`.
3. **A launch with several tabs, one holding the 10,000-line note,** reads only the active note before the first frame.
   - Task 3: `testRestoreReadsTheBodyOfTheActiveNoteOnly`.
4. **Twelve open tabs, with the strip in the toolbar,** never push the pin, paperclip or new note button out of reach, also with the sidebar hidden.
   - Task 7: `testTwelveTabsKeepTheToolbarButtons`.
5. **A corrupt, unreadable or unwritable launch log** never delays or breaks a launch.
   - Task 1: `launchLogIgnoresACorruptFile` and `testLaunchSurvivesAnUnwritableLaunchLog`.

---

## File Map

New files are marked `+`.

```
VERSION                                                          1.0.0
Packages/ScratchCore/Sources/ScratchCore/
  Launch/LaunchRecord.swift  Launch/LaunchLog.swift (+)          the record, the file, the owner's report
  Launch/LaunchOptions.swift                                     light-contrast, dark-contrast, -ScratchIdleMonitor
  Notes/Note.swift  Notes/PlainLine.swift (+)                    titles and previews without markers
  Storage/Schema.swift                                           v4: titles and previews worked out again
  Notes/NoteStore.swift  Notes/TabNoteInfo.swift (+)             tabInfo(_:): what a tab needs without the body
  Markup/InlineEditing.swift  Markup/ListEditing.swift           ⌘B on a caret and on lines; toggleCheckmarks
  Attachments/AttachmentEditing.swift                            lineBreaks(inserting:…)
App/LaunchReference/main.swift (+)                               an empty AppKit app, the launch floor
App/project.yml                                                  LaunchReference target, in the ScratchPerf scheme
App/Sources/Support/LaunchClock.swift  LaunchTimer.swift  IdleMonitor.swift (+)
App/Sources/main.swift  AppDelegate.swift                        the launch marks, the log, the quit hook
App/Sources/Window/MainMenu.swift  AppCommands.swift             Help > Launch Times…, Format > Mark as Checked ⇧⌘U
App/Sources/Window/LaunchTimesPanel.swift (+)                    the alert with Copy
App/Sources/Window/ToolbarController.swift  EditorAreaViewController.swift   the strip in the toolbar
App/Sources/Session/SessionCoordinator.swift                     restore reads the active note only
App/Sources/Editor/ NoteTextView MarkupStyler MarkupLayoutManager MarkupAppearance MarkupAttributes
                    CodeBlockStyler PasteClassifier AttachmentPasteboard EditorViewController
App/Sources/Editor/SpokenText.swift  EditorContextMenu.swift (+)
App/Sources/Sidebar/SidebarRowViews.swift  Tabs/TabStripViewController.swift   accessibility labels
App/Resources/Assets.xcassets/                                   high contrast variants, CodeBorder (+), the icon
App/Tests/ScratchAppTests/  LaunchTimerTests SessionRestoreTests SpokenTextTests ContextMenuTests
                            AppearanceTests (+), and the existing files named in the tasks
App/Tests/ScratchUITests/   AccessibilityUITests (+), TabsUITests, TitleUITests, ScreenshotTests
App/Tests/ScratchPerfTests/ LaunchPerfTests IdlePerfTests (+)
scripts/perf-extract.py  perf-check.py  make-app-icon.py (+)  check-release-zip.sh  and their tests
perf/budgets.json  perf/tolerances.json (+)  perf/baseline.json
docs/decisions/0009-performance-at-1-0.md (+)  0010-one-point-oh-calls.md (+)
docs/features/launch-times.md  accessibility.md (+), and formatting, attachments, sidebar, tabs
README.md  docs/images/  AGENTS.md  docs/architecture.md  roadmap row 6
```

---

### Task 1: The launch log and Help > Launch Times…

This covers Review Focus 5.

**Files:**
- Create: `Launch/LaunchRecord.swift`, `Launch/LaunchLog.swift`, `App/Sources/Support/LaunchClock.swift`, `LaunchTimer.swift`, `App/Sources/Window/LaunchTimesPanel.swift`, `docs/features/launch-times.md`
- Modify: `main.swift`, `AppDelegate.swift`, `MainMenu.swift` (a Help menu, `NSApp.helpMenu`), `AppCommands.swift`, `DebugStateElement.swift` (`launchTimes`), `VERSION` (1.0.0), `AGENTS.md` (latest plan, the file, the menu)
- Test: `LaunchLogTests.swift` (+), `App/Tests/ScratchAppTests/LaunchTimerTests.swift` (+), `LaunchUITests.swift`

**Interfaces:**

```swift
public struct LaunchRecord: Codable, Equatable, Sendable {
    public var date: Date; public var version: String; public var bootTime: Date
    public var phases: [String: Double]          // "main", "storage", "restore", "window", "firstFrame": ms from process start
    public var isFirstAfterStartUp: Bool
    public var totalMilliseconds: Double { get } // phases["firstFrame"]
}
public struct LaunchLog: Equatable, Sendable {
    public static let fileName = "launch-times.json"; public static let limit = 50
    public private(set) var records: [LaunchRecord]       // oldest first
    public static func load(from directory: URL) -> LaunchLog       // missing or corrupt file: empty
    public mutating func append(_ record: LaunchRecord)   // sets isFirstAfterStartUp, keeps the newest `limit`
    public func save(to directory: URL) throws            // atomic write
    public func report(version: String, timeZone: TimeZone) -> String
}
// App
enum LaunchClock { static func processStart() -> Date?; static func bootTime() -> Date? }   // sysctl KERN_PROC_PID p_starttime, kern.boottime
@MainActor enum LaunchTimer {
    static func mark(_ phase: String)                     // records Date() for the phase, once
    static func finish(dataDirectory: URL, version: String)   // after "firstFrame": load, append, save on a utility queue
    static var current: LaunchRecord? { get }
}
```

**Behaviour:**
- **The phase marks:**
  - `main.swift` marks `main` first.
  - `AppDelegate.launch()` marks `storage` after `AppEnvironment.bootstrap`, `restore` after `coordinator.restore()`, and `window` after `showWindow`.
  - `RunLoopIdle.onNext` marks `firstFrame` and calls `finish`.
- **The report**, newest first, local time:

  ```
  Scratch 1.0.0, launch times on this Mac, newest first:
  2026-10-23 09:14   412 ms   first after start-up
  2026-10-23 09:20   118 ms
  Other launches, median of the last 1: 118 ms (budget 200 ms). First after start-up, median of 1: 412 ms (budget 500 ms).
  ```

  - The first median is over the newest 10 records that are not first after start-up, and the second over the newest 10 that are.
  - A summary with no records says `none yet` in place of its number.
  - With no record at all, the report is `No launches recorded yet.`
- **Help > Launch Times…** shows `LaunchTimesPanel`: an `NSAlert` whose accessory is a selectable monospaced text view holding the report, with the buttons **Copy** (plain text to the general pasteboard) and **OK**.

- [ ] **Step 1: Write the failing tests.**
  - Core:
    - `appendMarksFirstAfterStartUp`: two records with one boot time give `true` then `false`, and a new boot time gives `true`.
    - `logKeepsNewestFifty`
    - `launchLogIgnoresACorruptFile`: garbage bytes load as an empty log.
    - `saveAndLoadRoundTrip`
    - `reportFormat`: the exact text above, in UTC.
    - `reportWithNoRecords`
  - Hosted:
    - `testPhasesAreInOrder`: after the app's own launch, `LaunchTimer.current` has the five phases in increasing order.
    - `testLaunchLogIsWrittenAfterTheFirstFrame`: `finish` writes nothing synchronously, and the file exists after the utility queue drains.
    - `testLaunchSurvivesAnUnwritableLaunchLog`: a data directory where `launch-times.json` is a directory. `finish` completes and nothing throws on the main thread.
  - UI: `testHelpMenuShowsLaunchTimes`: Help > Launch Times… shows a sheet or alert with "launch times on this Mac" and a Copy button.
- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`. Expected: compile failure. Push, then wait (`make ci-wait`). Expected: the hosted and UI tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Run `make core-test && make lint`, push, and wait. Expected: both jobs green, no perf `FAIL` beyond the `launch_ms` one that `main` already has (Task 2 removes it).
- [ ] **Step 5: Commit.** `git commit -m "Launch log and Help > Launch Times"`

---

### Task 2: CI measures Scratch's own launch work, and idle

**Files:**
- Create: `App/LaunchReference/main.swift`, `App/Sources/Support/IdleMonitor.swift`, `App/Tests/ScratchPerfTests/IdlePerfTests.swift`, `perf/tolerances.json`, `docs/decisions/0009-performance-at-1-0.md`
- Modify: `App/project.yml`, `LaunchOptions.swift` (`-ScratchIdleMonitor <path>`), `AppDelegate.swift`, `LaunchPerfTests.swift`, `scripts/perf-extract.py`, `scripts/perf-check.py` and their tests, `perf/budgets.json`, `.github/workflows/ci.yml` (only if the perf step needs the new file), `AGENTS.md` (Performance, launch arguments)
- Test: `scripts/tests/test_perf_extract.py`, `test_perf_check.py` (the existing ones), `LaunchOptionsTests.swift`

**Interfaces:**
- **`LaunchReference`:** an application target, bundle id `io.github.ldellisola.Scratch.LaunchReference`, never in a release.
  - Its `main.swift` makes `NSApplication`, a delegate that shows one 1100 × 700 titled window holding a TextKit 1 `NSTextView` (`NSTextView(usingTextLayoutManager: false)`) with one line of SF Mono text, makes it key, and activates.
  - A build dependency of `ScratchPerfTests`, so the `ScratchPerf` scheme builds it in Release.
- **`IdleMonitor(file: URL)`:** with `-ScratchIdleMonitor <path>`, 3.5 s after launch it reads `getrusage(RUSAGE_SELF)` and starts counting the main run loop's `afterWaiting` passes. After 5 s it reads `getrusage` again and writes `{"cpu_ms": …, "cpu_pct": …, "wakeups": …}`. It hands the file over the way `FrameMonitor` does.
- **`perf-extract.py` metrics:**
  - `launch_reference_ms`: `LaunchPerfTests/testReferenceLaunch`.
  - `launch_overhead_ms`: `launch_ms − launch_reference_ms`, when both exist.
  - `idle_cpu_pct` and `idle_wakeups`: the `idle_cpu` attachment.
  - `launch_phase_<name>_ms`: the median of each phase over the `launch_phases` attachment's records.
- **`perf-check.py`:**
  - It reads `--tolerances` (optional, default `perf/tolerances.json`): FAIL when R > 1.2 × S + T(metric), with T = 0 when absent.
  - A result whose metric has no budget is printed with the verdict `INFO` instead of being ignored.
- **`perf/budgets.json`:** `{"launch_overhead_ms": 150, "keystroke_ms": 8, "scroll_frame_ms": 8, "switch_small_ms": 12, "switch_huge_ms": 50, "paste_code_ms": 50, "idle_cpu_pct": 1.0}`. `launch_ms` leaves it.
- **`perf/tolerances.json`:** `{"launch_overhead_ms": 60, "idle_cpu_pct": 0.5}`.

**Behaviour:**
- **`testReferenceLaunch`:** measures `LaunchReference.app` like `testLaunch`, with the same warm-up and 10 iterations, launched by its URL in the built products directory (`XCUIApplication(url:)`), or by bundle id if the URL initialiser is not available.
- **After `testLaunch`'s measure:** one more launch reads `debug.state`'s `launchTimes` (the log's records, newest 20) and attaches them as `launch_phases` (JSON).
- **`IdlePerfTests.testIdle`:** launches the `typical` fixture with `-ScratchIdleMonitor`, waits for the file, attaches it as `idle_cpu`, and fails when it never comes.
- **ADR 0009** records:
  - why the absolute launch cannot gate on these runners: main's own run of 0.5.0 measured 0.60 to 1.14 s across its 10 launches
  - the reference app and the overhead budget
  - idle measured as a percentage, because the caret's blink is a timer the app does not own
  - the tolerances
  - the owner's M4 numbers, from Help > Launch Times… (a table filled in after the release)

- [ ] **Step 1: Write the failing script tests.**
  - `perf-check`:
    - `tolerance_widens_regression_limit`: R = 200, S = 120, T = 60 is OK, and T = 0 fails.
    - `metric_without_budget_is_info`
    - `missing_tolerances_file_means_zero`
  - `perf-extract`:
    - `overhead_is_launch_minus_reference`
    - `phases_are_medians`
    - `idle_from_attachment`
  - Core: `parsesIdleMonitor`.
- [ ] **Step 2: Run them to verify they fail.** Run: `make script-test` and `make core-test`. Expected: the new tests fail.
- [ ] **Step 3: Implement**, then XcodeGen on Linux (AGENTS.md pitfall): the generated project has the `LaunchReference` target and the perf scheme builds it.
- [ ] **Step 4: Verify.** Push, then wait.
  - Expected: `perf/report.md` lists `launch_ms`, `launch_reference_ms` and the phases as `INFO`, and `launch_overhead_ms` and `idle_cpu_pct` with verdicts.
  - Write the measured numbers into ADR 0009.
  - Not one `FAIL`. An overhead `WARN` is Task 3's.
- [ ] **Step 5: Commit.** `git commit -m "Gate launch on Scratch's own work; measure idle CPU"`

---

### Task 3: Less work before the first frame, and colours sooner after a paste

This covers Review Focus 3.

**Files:**
- Create: `Notes/TabNoteInfo.swift`
- Modify: `NoteStore.swift` (`tabInfo`), `SessionCoordinator.swift` (`restoredTabs`, `warmUpHighlighting`), `NoteTextView.swift` (the wrap decided in `endPaste`), `CodeBlockStyler.swift` (`prefetch`), `docs/decisions/0009-performance-at-1-0.md`, `AGENTS.md` (the warm-up and paste pitfalls)
- Test: `NoteStoreTests.swift`, `App/Tests/ScratchAppTests/SessionRestoreTests.swift` (+), `CodePasteTests.swift`, `SessionWarmUpTests.swift`

**Interfaces:**

```swift
public struct TabNoteInfo: Equatable, Sendable {
    public let id: NoteID; public let displayTitle: String; public let hasTitle: Bool
    public let deletedAt: Date?; public let isNeverUsed: Bool    // empty title and body, modified_at == created_at
}
extension NoteStore { public func tabInfo(_ ids: [NoteID]) throws -> [NoteID: TabNoteInfo] }   // one query, no body read
extension SessionCoordinator { var notesReadAtRestore: Int { get } }   // full notes `restore()` read: a test seam
/// Queues the request that a block holding `block` (a whole fenced block, as `PasteClassifier.wrap` writes it) would
/// make, so that its colours are in the cache by hash when the block appears. A block with no language is not queued.
extension CodeBlockStyler { func prefetch(block: String) }
```

**Behaviour:**
- **`restore`:**
  - Reads `tabInfo` for every saved tab and drops the tabs that `tabInfo` does not return or returns deleted. That is the rule it has now.
  - Reads only the active note in full.
  - Tab items and the untouched set come from `TabNoteInfo`.
- **`warmUpHighlighting`:** reads the open tabs' bodies on the storage queue, after the first frame, then warms up as now.
- **A paste:**
  - `endPaste` calls `PasteClassifier.wrap` at once (it reads only the text) and, for a wrap, sends `prefetch(block: edit.replacement)`.
  - The wrap on the later turn applies that same edit when `editCount` has not moved, without detecting again.
  - The block finds its colours in the cache.
- **Launch work:** when Task 2's `launch_overhead_ms` is still over 150 after this, the phases in `perf/report.md` say which part is left. ADR 0009 records them, and what was tried. No further change is required by this plan.

- [ ] **Step 1: Write the failing tests.**
  - `tabInfoReadsNoBody`: the query's SQL names no `body`. Assert with a store over a database that logs statements, or check the derived columns only.
  - `tabInfoMarksNeverUsed`
  - `tabInfoOmitsMissing`
  - `testRestoreReadsTheBodyOfTheActiveNoteOnly`: three tabs, one holding the `huge-note` body. `notesReadAtRestore == 1`, and every tab has its title.
  - `testRestoreDropsTabsOfDeletedNotes`
  - `testPastedCodeIsPrefetched`: after a 40-line Swift paste, `pendingHighlights` is 1 before the wrap, and the wrapped block is coloured from the cache, with `droppedResults` unchanged.
  - The existing `SessionWarmUpTests` still pass.
- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Push, then wait. Expected: green, and `paste_code_ms` and `launch_overhead_ms` no worse than Task 2's run. Write both into ADR 0009.
- [ ] **Step 5: Commit.** `git commit -m "Restore reads only the active note; prefetch the colours of pasted code"`

---

### Task 4: Titles and previews without markers; schema v4

This covers Review Focus 1.

**Files:**
- Create: `Notes/PlainLine.swift`
- Modify: `Note.swift`, `Schema.swift` (v4), `docs/features/sidebar.md`, `tabs.md`
- Test: `NoteTests.swift`, `PlainLineTests.swift` (+), `SchemaTests.swift`

**Interfaces:**

```swift
enum PlainLine { static func text(of line: Substring) -> Substring }   // internal: the line without its markers (MarkupParser.parseLine)
public enum Schema { public static let currentVersion = 4 }
```

**Behaviour:**
- **`PlainLine.text`:**
  - Removes, for a bullet or checkbox, everything before the span's `content`.
  - Removes, for bold and inline code, the characters of `markers`.
  - Leaves links and everything else as typed.
- **`displayTitle` and `preview`:** apply it to every line outside a fenced block, toggling at each fence line as `FenceScanner` pairs them. A line that is only markers (`- `, `****`) has no words and is skipped.
- **Migration v4:** does what v3 did: for each row, it builds a `Note` and writes `display_title`, `has_title` and `preview` only when they differ, never `modified_at`.

- [ ] **Step 1: Write the failing tests.**
  - `checkboxTitleHasNoMarker`: the body `"[ ] bump version to `2.4.1`\n[x] run migrations"` gives the title `bump version to 2.4.1` and the preview `run migrations`.
  - `bulletAndBoldTitle`: `"- **don't** deploy"` gives `don't deploy`.
  - `codeBlockLinesKeepMarkers`: ```` "```\n- x\n```" ```` gives `- x`.
  - `markerOnlyLineIsSkipped`
  - `globIsKept`: `src/**/*.ts` is unchanged (ADR 0006).
  - `migratingV3StripsMarkersFromTitles`: a v3 file. After the migration the title is plain, `modified_at` and the list order are the same, the version is 4, and `search` still finds the note.
  - `freshDatabaseIsVersion4`
- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Run `make core-test && make lint`, push, and wait. Expected: green. The `typical` screenshot's "Deploy checklist" row preview reads `bump version to 2.4.1 run migrations…`.
- [ ] **Step 5: Commit.** `git commit -m "Titles and previews show text without markers; schema v4"`

---

### Task 5: Editing follow-ups (⌘B, ⇧⌘U, double-click, composed text, title undo)

**Files:**
- Modify: `InlineEditing.swift` (`toggleBold` returns `TextEdit?`), `ListEditing.swift` (`toggleCheckmarks`), `NoteTextView.swift` (`toggleBoldMarkers`, `toggleCheckmarks(_:)`, `mouseDown`), `MainMenu.swift` (Format > Mark as Checked ⇧⌘U), `MarkupStyler.swift` (marked text), `EditorViewController.swift` (title undo), `docs/features/formatting.md`, `title-and-font-size.md`
- Test: `InlineEditingTests.swift`, `ListEditingTests.swift`, `CheckboxTests.swift`, `ListKeyTests.swift`, `MarkupStylerTests.swift`, `TitleUITests.swift`, `FormattingUITests.swift`

**Interfaces:**

```swift
extension InlineEditing { public static func toggleBold(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? }   // nil: beep
extension ListEditing { public static func toggleCheckmarks(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? }   // nil: no checklist line
extension NoteTextView { @objc func toggleCheckmarks(_ sender: Any?) }   // Format > Mark as Checked, ⇧⌘U, no target
```

- [ ] **Step 1: Write the failing tests.**
  - Core, ⌘B:
    - `boldCaretInWordWrapsWord`: `"say hello now"` with the caret at 6 gives `"say **hello** now"` with the caret at 8.
    - `boldCaretInRunUnwraps`
    - `boldCaretInEmptyPairRemovesIt`
    - `boldTwiceInWordRestoresText`
    - `boldWhitespaceSelectionIsNil`
    - `boldLinesWrapEachLine`: `"- one\n- two\n"`, all selected, gives `"- **one**\n- **two**\n"`.
    - `boldLinesUnwrapWhenAllBold`
    - `boldLinesSkipBlankLines`
  - Core, ⇧⌘U:
    - `checkmarksTickAllWhenAnyOpen`
    - `checkmarksUntickWhenAllTicked`
    - `checkmarksNilWithoutChecklist`
    - `checkmarksKeepIndentAndText`
  - Hosted:
    - `testDoubleClickOnABoxTicksItOnce`: `mouseDown` with click count 1, then 2, sent to the view at the box.
    - `testMarkAsCheckedMenuItem`: Format has it with ⇧⌘U, and it ticks the selected lines in one undo step.
    - `testMarkAsCheckedBeepsInCodeBlock`
    - `testMarkedTextKeepsItsUnderline`: `setMarkedText` in a bold line, a restyle, then the marked range still has the `markedTextAttributes` underline.
    - `testBoldOnCaretInWord`
  - UI:
    - `testTitleUndoStaysWithItsNote`: type a title in A, ⌘T, type a title in B, switch back to A, then ⌘Z twice. B's title and A's title are unchanged, and the app is running.
    - `testCommandBTwiceOnAWordRestoresIt` in `FormattingUITests`.
- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`, then push and wait.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Push, then wait. Green.
- [ ] **Step 5: Commit.** `git commit -m "⌘B on a caret and on lines, ⇧⌘U, one tick per double-click, IME underline, title undo per note"`

---

### Task 6: Attachment follow-ups

This covers Review Focus 2.

**Files:**
- Modify: `AttachmentEditing.swift` (`lineBreaks`), `NoteTextView.swift` (`insertText`, `setMarkedText`, the paste text path, `writeSelection`, `readSelection(from:)`, `performDrop`, `readablePasteboardTypes`), `AttachmentPasteboard.swift` (`noteTextType`, `materialize`), `AppDelegate.swift` (`applicationWillTerminate`), `docs/features/attachments.md`, `paste-and-copy.md`, `AGENTS.md` (the copy pitfall: `writablePasteboardTypes` and what is written)
- Test: core `AttachmentEditingTests.swift`; hosted `AttachmentEditingTests.swift`, `AttachmentCopyTests.swift`, `AttachmentPasteTests.swift`

**Interfaces:**

```swift
extension AttachmentEditing {
    /// Whether a line break must go before and after `inserted`, put at `range` of `text`, so that no token line
    /// (in `text` or in `inserted`) shares its line with other characters. A literal position (a code block) needs none.
    public static func lineBreaks(inserting inserted: String, at range: NSRange, in text: NSString,
                                  isLiteral: (Int) -> Bool) -> (before: Bool, after: Bool)
}
enum AttachmentPasteboard {
    static let noteTextType = NSPasteboard.PasteboardType("io.github.ldellisola.Scratch.note-text")
    /// When `pasteboard` still holds the item of the last copy of one image (its change count), writes it again with the
    /// PNG and TIFF data in place of the promise. Returns whether it did.
    static func materialize(on pasteboard: NSPasteboard) -> Bool
}
```

**Behaviour:**
- **Typing and composing:** at a token edge where `lineBreaks` says so, the view first applies the line break with `apply(_:)`, then lets `super` insert.
  - For `before`, the caret follows the break.
  - For `after`, it stays in front of it.
  - Two undo steps: the text, then the break.
- **A paste of text:** puts the breaks into its one edit.
- **`writeSelection`:** adds `noteTextType` when the selection holds a token.
- **`readSelection` and `performDrop`:** read `noteTextType` first when the target is not code.

- [ ] **Step 1: Write the failing tests.**
  - Core:
    - `lineBreakGoesBetweenTypingAndAToken`: at the end of the token line, `before`, and at its start, `after`.
    - `lineBreakFirstNeedsNoMore`
    - `insertedTokenMidLineGetsBoth`
    - `literalNeedsNone`
    - `selectionReplacingAWholeTokenNeedsNone`
  - Hosted:
    - `testTypingAtTheEndOfATokenLineGoesBelowIt`
    - `testTypingAtTheStartOfATokenLineGoesAboveIt`
    - `testComposingAtATokenEdgeKeepsTheToken`: `setMarkedText`, then `insertText`.
    - `testPastingTextAtATokenEdgeKeepsTheToken`
    - `testCopyWithATokenWritesNoteText`
    - `testCopyWithoutATokenWritesOnlyPlainText`: the existing plain-copy test still holds, with no `noteTextType`.
    - `testPastingCopiedTextWithATokenKeepsTheAttachment`: into another note. The token is the same id and draws its image.
    - `testDroppingDraggedTextWithATokenKeepsTheToken`: `writeSelection` to a named pasteboard, then `performDrop(of:atViewPoint:)` elsewhere in the note.
    - `testNoteTextIntoCodeInsertsNames`
    - `testMaterializeWritesTheImageData`: a copy of one image to a named pasteboard, then `materialize`. `data(forType: .png)` is non-nil without the provider being asked: replace the provider with one that fails the test.
- [ ] **Step 2: Run them to verify they fail.** Run: `make core-test`, then push and wait.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Push, then wait. Green, and `AttachmentUITests` still pass.
- [ ] **Step 5: Commit.** `git commit -m "Tokens survive typing at their edges, drags and copies between notes; a copied image outlives Scratch"`

---

### Task 7: Visual polish against mockup B

This covers Review Focus 4.

**Files:**
- Modify:
  - `ToolbarController.swift`: the items are `[.toggleSidebar, .sidebarTrackingSeparator, tabStripItem, .flexibleSpace, pinItem, attachItem, .space, newNoteItem]`.
  - `EditorAreaViewController.swift`: the strip leaves the editor area, and the title field sits 10 pt below the safe area.
  - `TabStripViewController.swift`, `AppDelegate.swift`.
  - `MarkupAppearance.swift` (`lineSpacing(forFontSize:)` in the base, list and code styles), `MarkupStyler.swift`, `MarkupAttributes.swift` (`scratchInlineCode`), `MarkupLayoutManager.swift` (the pill, the border, the radius, the box colour), `Assets.xcassets/CodeBorder.colorset` (+).
  - `AGENTS.md`: the tab strip pitfall, now as a toolbar item, and the titlebar pocket.
  - `docs/features/tabs.md`, `formatting.md`.
- Test: `TabStripViewControllerTests.swift`, `TitlebarPocketTests.swift`, `MarkupStylerTests.swift`, `CodeBlockStylerTests.swift`, `CheckboxTests.swift`, `TabsUITests.swift`

**Behaviour:**
- **The toolbar item:**
  - Its view is the strip's `TabStripView`, `isBordered = false`, `visibilityPriority = .high`.
  - It is as wide as its tabs, and never wider than the room the toolbar leaves before the buttons. Tabs get narrower as they do today.
  - The buttons never go into the overflow menu.
  - One glass capsule around the tabs: the strip's own `NSGlassEffectView`, no second one from the toolbar.
- **Height of the checkbox symbol:** 85% of the font's line height, not of the fragment's, which now includes the spacing.

- [ ] **Step 1: Write the failing tests.**
  - `testTabStripIsAToolbarItem`: the window's toolbar has the item, and its view is the strip.
  - `testTabStripIsInTheToolbarRow` (UI): the active tab's mid-y is within 4 pt of the new note button's.
  - `testTwelveTabsKeepTheToolbarButtons` (UI): twelve tabs, then the pin, paperclip and new note buttons are hittable and the last tab is inside the window. The same after ⌃⌘S hides the sidebar.
  - `testLinesHaveSpacing`: `lineSpacing` 4 at 13 pt for a plain, a list and a code line, and 0 for a fence and an attachment line.
  - `testInlineCodeIsAPill`: `scratchInlineCode` is set and `.backgroundColor` is absent. A pixel 1 pt left of the first character of the code is tinted.
  - `testCodeBlockHasABorder`: a pixel on the block's edge differs from its fill.
  - `testOpenBoxIsGrey`: the drawn open box's pixels have r ≈ g ≈ b.
  - `testCheckboxSizeIgnoresSpacing`
  - The existing tab, sidebar, scroll and titlebar pocket tests still pass.
- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Push, then wait. Open every screenshot. Expected in `typical-light` and `-dark`:
  - the tab strip in the toolbar row, left of the buttons
  - the title within about 16 pt under the toolbar, with no empty band
  - [pin, paperclip] and [new note] as two capsules
  - lines with air between them
  - `2.4.1` in a pill
  - the code block with rounded corners and a hairline border
  - open boxes in grey

  Compare with `docs/superpowers/specs/2026-10-19-scratchpad-mockup.html` variant B, rendered with Chromium (`/opt/pw-browsers/chromium`). Fix any mismatch here. No perf `FAIL`.
- [ ] **Step 5: Commit.** `git commit -m "Tab strip in the toolbar, line spacing, inline code pills, bordered code blocks"`

---

### Task 8: Accessibility pass

**Files:**
- Create: `App/Sources/Editor/SpokenText.swift`, `EditorContextMenu.swift`, `docs/features/accessibility.md`, `App/Tests/ScratchUITests/AccessibilityUITests.swift`
- Modify:
  - `NoteTextView.swift`: `accessibilityString(for:)`, `accessibilityAttributedString(for:)`, `menu(for:)`.
  - `SidebarRowViews.swift`: the cell is one element labelled `<title>, <time>, <preview>` plus `, pinned`. Its children keep their identifiers, which UI tests read.
  - `TabStripViewController.swift`: the close button is labelled `Close <title>`.
  - `EditorViewController.swift` and `TitleField.swift`: the editor is labelled "Note", the title "Title".
  - The Recently Deleted header: a button, its label "Recently Deleted, <n> notes", expanded or collapsed.
  - The key view loop: search field, then note list, title, editor.
  - `DebugStateElement.swift` (`firstResponder`: `editor`, `title`, `search`, `sidebar` or `other`), `LaunchOptions.swift` (`light-contrast`, `dark-contrast`), `AppDelegate.swift`.
  - Every `Assets.xcassets/*.colorset`: `"appearances": [{"appearance": "contrast", "value": "high"}]` variants, light and dark.
  - `Makefile` `SCREENSHOT_NAMES` and `ScreenshotTests.swift` (`typical-contrast-light`, `code-contrast-dark`), `AGENTS.md`.
- Test: `SpokenTextTests.swift` (+), `ContextMenuTests.swift` (+), `AppearanceTests.swift` (+), `AccessibilityUITests.swift` (+), `LaunchOptionsTests.swift`

**Interfaces:**

```swift
enum SpokenText {
    /// The words for `range` of a styled note: the storage's marker roles, code block marks and attachment marks read as
    /// in the Global Constraints table; text without them as it is.
    static func spoken(_ storage: NSAttributedString, range: NSRange) -> String
}
enum EditorContextMenu { static func items(for textView: NoteTextView, atViewPoint point: NSPoint) -> [NSMenuItem] }
```

- [ ] **Step 1: Write the failing tests.**
  - `testSpokenChecklist`: `[ ] buy milk` reads `unchecked buy milk`, and `[x]` reads `checked`.
  - `testSpokenBoldHasNoStars`
  - `testSpokenToken`: an image token reads `image, dashboard.png`, a file token `file, rollback-plan.txt`, and an unknown id `missing attachment`.
  - `testSpokenCodeBlock`: `code block, Swift`, the code, then `end of code block`.
  - `testAccessibilityValueIsTheStoredText`
  - `testContextMenuOnABox`: Mark as Checked.
  - `testContextMenuOnALink`: Open Link, and choosing it calls `openURL`.
  - `testContextMenuOnAToken`: Open Attachment.
  - `testContextMenuInABlock`: a Code Block Language submenu with the label menu's items.
  - `testEveryColourHasAHighContrastVariant`: each named colour resolves differently under `.accessibilityHighContrastAqua` than under `.aqua`, and under `…DarkAqua` than `.darkAqua`.
  - `parsesContrastAppearances`
  - UI:
    - `testToolbarButtonsHaveLabels`
    - `testSidebarRowReadsAsOneElement`
    - `testCloseButtonNamesItsTab`
    - `testEditorAndTitleHaveLabels`
    - `testTabFromSearchReachesTheNoteList`: through `debug.state`'s `firstResponder`.
- [ ] **Step 2: Push, then wait.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Push, then wait. Open `typical-contrast-light` and `code-contrast-dark`. Expected: stronger code tints and borders, readable labels, glass that is still the system's.
- [ ] **Step 5: Commit.** `git commit -m "Accessibility: spoken markers and attachments, labels, context menu, Increase Contrast"`

---

### Task 9: The app icon

**Files:**
- Create: `scripts/make-app-icon.py` (Pillow), `scripts/tests/test_make_app_icon.py`
- Modify:
  - `App/Resources/Assets.xcassets/AppIcon.appiconset/*.png`: generated, checked in.
  - `scripts/check-release-zip.sh` and its test: `Contents/Resources/AppIcon.icns` exists, and `CFBundleIconName` is `AppIcon`.
  - `ScreenshotTests.swift` and the Makefile (`about-light`: the About panel).
  - `docs/decisions/0010-one-point-oh-calls.md`: the icon, and Pillow as a development tool.
  - `AGENTS.md`: commands and the scripts list.

**The design** (on a 1024 px canvas) [call]:
- **Base:** the macOS squircle in the Big Sur grid, 824 × 824 at (100, 100), a superellipse with exponent 5.
  - Fill: a vertical gradient from `#FFE07A` to `#FFB938`.
  - Shadow: 28 px blur, 12 px down, 30% black.
- **On it:**
  - A ticked checkbox: an 120 px square with radius 28, filled `#0A84FF`, with a white check of 22 px stroke, at (230, 300).
  - A bar from x 400 to 790, centred at y 360, 56 px high, `#1C1C1E` at 85%.
  - A 64 px dot, `#0A84FF`, at (290, 540), with a bar from 400 to 720 at y 540.
  - A bar from 260 to 620 at y 720, at 45%.
- **Sizes:** the ten sizes of the existing `Contents.json` (16 to 1024 px), each drawn at 4× and scaled down with LANCZOS.

- [ ] **Step 1: Write the failing tests.**
  - `test_make_app_icon`: running the script into a temporary set gives ten PNGs whose pixel sizes match `Contents.json`, and corner pixel (0, 0) of the 1024 is fully transparent.
  - The release-zip check fails for an app without `AppIcon.icns`.
- [ ] **Step 2: Run them to verify they fail.** Run: `make script-test`.
- [ ] **Step 3: Implement**, run the script, and look at `icon_512x512@2x.png` and `icon_16x16@2x.png` with the Read tool. The checkbox and the bars must read at 32 px.
- [ ] **Step 4: Verify.** Push, then wait. Open `about-light.png`. Expected: the new icon, the version 1.0.0 and the credits.
- [ ] **Step 5: Commit.** `git commit -m "App icon"`

---

### Task 10: Screenshots, baseline, docs, release 1.0.0 (Steps 1–4; the merge comes after review)

**Files:**
- Modify: `perf/baseline.json`, `docs/decisions/0009-performance-at-1-0.md` (the table), `0010-one-point-oh-calls.md`, `README.md` and `docs/images/` (all seven from the new screenshots), `docs/features/*.md` (anything still stale), `docs/architecture.md` (the launch log, the toolbar strip, the spoken text), `AGENTS.md` (Plan 6 done, released as 1.0.0), roadmap row 6 done

- [ ] **Step 1: Screenshots.** Push, then wait, and open every PNG. Each must match what Tasks 4, 7, 8 and 9 expect.
- [ ] **Step 2: Baseline.** Run the `macos` job three times on the same commit: re-run the job with the GitHub tools, or push docs-only commits. Write the slowest result of each metric into `perf/baseline.json` (ADR 0003), and the three runs into ADR 0009. The commit that carries the baseline must itself have no `FAIL`.
- [ ] **Step 3: README.**
  - The feature list at 1.0.
  - The release table.
  - The shortcuts: ⇧⌘U, and the context menu.
  - The images.
  - A section, **Checking launch speed**, with the owner's steps:
    1. Restart the Mac and log in.
    2. Open Scratch from Raycast.
    3. Choose Help > Launch Times…, press Copy, and send it.
    4. Then quit and open Scratch five times and send it again.
- [ ] **Step 4: Verify.** Push, then wait. Green, with no `FAIL`.
- [ ] **Step 5 (after the whole-branch review): PR and merge.**
  1. Open the PR `plan-6-polish` → `main`, titled "Scratch 1.0.0: polish and hardening".
  2. Merge once CI is green.
  3. Check that `v1.0.0` is released with the DMG and the zip.
