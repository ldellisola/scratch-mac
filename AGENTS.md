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
- Current plan: [`docs/superpowers/plans/2026-10-20-plan-2-notes-and-tabs.md`](docs/superpowers/plans/2026-10-20-plan-2-notes-and-tabs.md)
  (Plan 1, done and released as 0.1.0: [`2026-10-19-plan-1-walking-skeleton.md`](docs/superpowers/plans/2026-10-19-plan-1-walking-skeleton.md))

## 2. Module map

```
Packages/ScratchCore/             Foundation-only Swift package. Builds and tests on Linux and macOS.
  Sources/CSQLite/                module map for the system SQLite library (no pkgConfig, on purpose)
  Sources/ScratchCore/Notes/      Note and NoteID: the note model, derived title and preview. NoteSummary: a sidebar
                                  row (`deletedAt` is set for Recently Deleted rows). NoteStore: reads and writes the
                                  notes table (pinned first, newest edit first), searches it (`search`), and pins,
                                  deletes, restores and purges notes (`setPinned`, `delete`, `restore`,
                                  `deletePermanently`, `deletedSummaries`, `purge`). SearchQuery: typed text to an
                                  FTS5 MATCH expression
  Sources/ScratchCore/Session/    SessionState and TabState (what a relaunch restores: the tabs, the active one, the
                                  font size, and each tab's cursor and `scrollAnchor`), SessionStore (JSON under key
                                  "state"), TabList (the tab rules: open, close, select, with TabOpening and
                                  TabClosing as results), FontSize (13 pt, 9 to 32, steps of 1), TextOffset (clamps a
                                  saved cursor offset to a Character boundary)
  Sources/ScratchCore/Sidebar/    SidebarSections (splits the note list into Pinned, Today, Yesterday, Earlier and
                                  Recently Deleted by calendar day), NoteTimeLabel (a row's "10:42" or "Oct 14")
  Sources/ScratchCore/Autosave/   Autosaver (decides when unsaved changes are written: 300 ms after the last change,
                                  at most 1 s after the first, no repeating timers) and the AutosaveScheduler clocks it
                                  runs on: DispatchAutosaveScheduler (production), ManualAutosaveScheduler (tests)
  Sources/ScratchCore/Storage/    Database (thread-safe SQLite wrapper with transactions), Connection (the C API calls),
                                  SQLValue and Row, Schema (version 2, with the FTS5 index `notes_fts`, the migration
                                  rule, and SchemaError for a database from a newer Scratch), ScratchStorage (opens
                                  the data directory and its stores; refuses a fixture on the real directory)
  Sources/ScratchCore/Launch/     LaunchOptions: the -Scratch* launch arguments (section 3), AppearanceOverride
  Sources/ScratchCore/Fixtures/   Fixture (empty, typical, huge-note, many-notes, recently-deleted) and FixtureContent,
                                  their notes and session
  Tests/ScratchCoreTests/         Swift Testing, one test file per source file
App/project.yml                   XcodeGen spec: targets Scratch (app), ScratchAppTests (hosted unit tests),
                                  ScratchUITests, ScratchPerfTests; schemes Scratch and ScratchPerf. The generated
                                  App/Scratch.xcodeproj is never committed.
App/Sources/                      AppKit shell (default actor isolation MainActor). main.swift and AppDelegate (launch
                                  sequence: storage, session, window, menu bar), AppEnvironment (parses the launch
                                  arguments, opens storage; isolates a hosted test run)
App/Sources/Window/               MainWindowController (one window, closing it quits), MainSplitViewController (glass
                                  sidebar item + editor area item), EditorAreaViewController (the tab strip above the
                                  editor), MainMenu (menu bar, built in code: there is no storyboard), AppCommands (the
                                  target of the app's own menu items: the tabs and the font size), ToolbarController
                                  (sidebar button, new note button), TitlebarPocket (hides the line macOS 26 draws under
                                  the toolbar, section 7)
App/Sources/Tabs/                 TabStripViewController (the glass tab strip: `TabStripItem`, `TabStripView`,
                                  `TabStripLayout`, `TabStripContentView`, `TabItemView`)
App/Sources/Sidebar/              SidebarViewController (the note list: an NSTableView in the glass sidebar; a click or
                                  Return opens a note, `onOpen`)
App/Sources/Session/              SessionCoordinator (the tabs and which is active, autosave, restore, new note, close,
                                  the sidebar list and the tab titles; the one place that writes to storage)
App/Sources/Editor/               NoteTextView (plain-text NSTextView, plain paste and copy, the font size, the note's
                                  undo manager), TextViewFactory (builds the TextKit 1 stack, docs/decisions/0001),
                                  TitleField (the optional title above the text), EditorViewController (the title field
                                  and the editor: shows a note, reports edits, cursor and scroll anchor)
App/Sources/Support/              AccessibilityID (also compiled into the UI test targets), Signposts (the `keystroke` and
                                  `switch-note` intervals the performance tests read), RunLoopIdle (runs work when the
                                  main run loop is next about to wait: after the frame is drawn), FrameMonitor
                                  (`-ScratchFrameMonitor`: scrolls the note itself and measures the frames),
                                  DebugStateElement (the invisible `debug.state` element that UI tests read the font
                                  size and scroll anchor from, in isolated launches only)
App/Resources/                    Assets.xcassets (placeholder app icon)
App/Tests/ScratchAppTests/        hosted XCTest unit tests, run inside the app (NoteTextViewTests, LargeInsertTests: a
                                  50,000-line paste returns within 500 ms, FrameMonitorTests, EditorViewControllerTests:
                                  the title, font size, per-note undo, read-only and scroll anchor, TitlebarPocketTests)
App/Tests/ScratchUITests/         XCUITest: UITestSupport launches the app on an isolated data directory (and relaunches
                                  it on the same one); LaunchUITests, PersistenceUITests (force-kill, quit, cursor),
                                  SidebarUITests, TitleUITests (title, font size, scroll position), TabsUITests (the
                                  tab strip, opening, closing and switching tabs),
                                  ScreenshotTests (one test per screenshot, section 3)
App/Tests/ScratchPerfTests/       the performance tests (UI tests in the Release build, ScratchPerf scheme): LaunchPerfTests,
                                  EditorPerfTests (keystroke, scrolling, switching notes), PerfSupport. They share
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
                                  release zip and checks the app in it), tests/ (their tests)
.github/workflows/ci.yml          CI. Job `linux`: lint, core tests, script tests, version bump check. Job `macos`:
                                  XcodeGen, core tests on macOS, app build and app tests, screenshots, performance tests
                                  and their check, the release zip. Both publish to `ci-results`.
.github/workflows/release.yml     the release: a merge to main that changes App/, Packages/ or VERSION builds
                                  `make release-zip` and publishes a GitHub Release `v<VERSION>` (section 6, Releases)
docs/architecture.md              module boundaries, data flow, threading
docs/release-notes-footer.md      the install and update steps, put at the top of every release's notes
                                  (`scripts/release-notes.sh` replaces its `<version>` placeholders)
docs/features/                    one short behaviour spec per feature: paste-and-copy.md, autosave-and-restore.md,
                                  title-and-font-size.md, tabs.md (more as features land)
docs/decisions/                   numbered decision records: 0001 (the editor uses TextKit 1, with the measurements and the
                                  marker hiding prototypes), 0002 (releases are ad-hoc signed), 0003 (what the CI
                                  performance check compares)
docs/superpowers/                 design spec and plans
```

This map lists what exists. Add new directories and files to it as they land. The target layout is the File Map in
the current plan.

## 3. Commands

Run them from the repository root. `[linux]` means it also runs in the Linux cloud sessions. Everything else needs
macOS and runs on GitHub's Macs.

- `make core-test` `[linux]`: build and run the ScratchCore tests.
- `swift test --package-path Packages/ScratchCore --filter <name>` `[linux]`: run matching tests only.
- `make lint` `[linux]`: `swift format lint --strict` over `Packages` and `App`. Must exit 0.
- `make format` `[linux]`: rewrite files to the house format (`.swift-format`).
- `make script-test` `[linux]`: test the scripts in `scripts/` (the ci-results loop, `perf-check.py`,
  `perf-extract.py`, `check-version-bump.sh` and `release-notes.sh`). Each test file ends with an `all ... passed` line.
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
  `typical-dark`, `empty-light` and `huge-note-light` (the names in the Makefile's `SCREENSHOT_NAMES`). The result
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
  version, bundle identifier, arm64 only, valid ad-hoc signature). CI runs it on every push, and the release workflow runs it to make
  the file it publishes.

### Launch arguments

The app reads these flags (`LaunchOptions`) and ignores every other argument. UI tests, screenshots and benchmarks
always pass `-ScratchDataDir`, so they never touch real data.

| Flag | Value | Effect |
|---|---|---|
| `-ScratchDataDir <path>` | any path | use `<path>` instead of `~/Library/Application Support/Scratch` |
| `-ScratchFixture <name>` | `empty`, `typical`, `huge-note`, `many-notes`, `recently-deleted` | delete the database in the data directory and seed that fixture |
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
  with this in-app monitor, not with XCTest's scroll metrics. All in milliseconds and all medians.
- **The CI runner is slow and noisy.** Runs of the same build differ by up to a factor of two (the first run of a job is
  the slowest), and a launch takes about 400 ms there (Calculator takes 1 s). The baseline is therefore the slowest of
  many runs, and `launch_ms` and `switch_small_ms` are budgeted at 400 and 12 instead of the spec's 200 and 8
  (docs/decisions/0003). A failure that no
  change explains: look at `perf/report.md`, then at `perf/metrics.json`, before touching the baseline.
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
- `ScratchCore` never imports AppKit or SwiftUI. App depends on Core, never the other way round. The Linux build
  enforces it, because AppKit does not exist there. Rule-based logic belongs in Core, not in the shell.
- Swift Testing (`import Testing`, `@Test`, `#expect`) in Core. XCTest/XCUITest only in the app's test targets.
- Files are small and single-purpose, and their names say what they do. One test file per source file.
- Tests reference the `docs/features/*` section they cover. A behaviour change updates its feature doc in the same
  change.
- A decision record in `docs/decisions/NNNN-title.md` for every new dependency, every changed `[call]` in the spec and
  every budget change. Plan 1 adds no runtime dependency.
- Tests, screenshots and benchmarks never touch real data. They run against an isolated data directory.

## 6. Definition of done

A change is done when:

- core tests, UI tests and lint pass
- no performance budget regressed
- screenshots of any affected screen have been looked at
- the feature doc and AGENTS.md are updated if behaviour or commands changed
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
   pull request. Otherwise it runs `make project release-zip` on `macos-26` (Xcode 26.6) and creates the GitHub Release
   `v<VERSION>`, titled `Scratch <VERSION>`, with `Scratch-<VERSION>.zip` attached, the notes GitHub generates (what
   changed since the last release) and the install and update steps (`scripts/release-notes.sh`, from
   `docs/release-notes-footer.md`, with the version filled in) at the top.
3. **Check it.** `git ls-remote --tags origin v<VERSION>` shows the tag once the release is published, and the release
   page lists the zip. If the workflow fails after the merge, the run's log says where. A failure of the workflow's own
   steps (a network error, say) is re-run from the Actions tab. A broken build needs a fix to `App/` or `Packages/`,
   with its own bump: the failed version was never tagged, and skipping a number does no harm.

The app is **ad-hoc signed and not notarised** (docs/decisions/0002-ad-hoc-signing.md, which amends spec §9.6): there is
no certificate and no secret to configure. The owner approves each downloaded version once in System Settings → Privacy &
Security → Open Anyway, and the release notes say so. The workflow itself can only run on `main`, so CI exercises
everything but its last step: the `macos` job runs `make release-zip`, which builds and checks the same zip.

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
- **A scroll anchor waits for a layout.** Text can only be positioned at a width, and at launch `show` runs before the
  window has laid out (the scroll view is 0 wide), so `EditorViewController` keeps the anchor and scrolls in
  `viewDidLayout` (`isLaidOut`, `scrollAnchorToApply`). It keeps applying it in the layouts before the window is
  visible, and stops when the window is visible or the user scrolls, types or moves the cursor. Never call
  `ensureLayout` before `isLaidOut`: it would lay a 10,000-line note out at a width of 0. `currentScrollAnchor` returns
  the waiting anchor until then, so an early save does not move the note back to its top.
- **Undo is per note, and `show` never clears it.** `SessionCoordinator.undoManagers` holds one `UndoManager` per note,
  and `show` hands the editor the one of the note. `NoteTextView.noteUndoManager` is what the text view, the
  `NSTextViewDelegate.undoManager(for:)` answer and `AppDelegate.windowWillReturnUndoManager` (the Edit menu) all
  return, so they cannot disagree. Loading a note's text runs between `disableUndoRegistration()` and
  `enableUndoRegistration()` of its manager and is not an undo step, and `breakUndoCoalescing()` ends the typing run of
  the note being left. Show a note with the text it had when it was left: an undo step holds ranges of that text.
- **UI tests read the font size and the scroll anchor from `debug.state`.** `DebugStateElement` is a 1 x 1 point view
  in the editor's container, only in an isolated launch (`AppDelegate`), with a JSON string for its accessibility value
  that it computes when asked: `UITestSupport.debugState(in:)` reads it. It draws nothing and takes no clicks, so it is
  not in a screenshot.
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
  of the active tab (`open`, `selectTab`, `closeTab`, `newNoteInNewTab`), which calls it first. Call all of them and
  `flush()` on the main thread only, and never from a block that runs on the storage queue.
- **A new note that nobody has used is not in the sidebar** and is discarded when its tab closes or another note
  replaces it in the tab, while it is still empty. It is "untouched" while it was created in this session (or restored
  empty) and has no text. Test changes that look at the sidebar must type first. Switching to another tab keeps an
  untouched note and its tab: only closing or replacing discards it.
- **A tab is the unit of `TabList`, and `SessionCoordinator.tabs` is the only copy.** The coordinator holds the note of
  the active tab (`current`) and nothing else of any note: another tab's note is read from the storage when its tab is
  shown, after the note being left was written (`leaveCurrentNote`). `saveNow` records the cursor and scroll anchor of
  the active tab in the list before it builds the session, so a code path that changes the tabs after `persistNow()`
  must read `tabs` again and not reuse a copy from before it. A tab change ends with `tabsDidChange()`, which shows the
  strip and the sidebar and writes the session at once (`writeSessionNow`).
- **A new note opens at the end of the strip, a note opened from the sidebar next to the active tab.** `TabList.open`
  inserts after the active tab, which is what ⌘-click wants. `newNoteInNewTab` selects the last tab first, so the new
  tab is at the end, as in a browser, and `testCommandTOpensNewEmptyTab` expects the new tab to be the third.
- **The sidebar opens a note from the table's click action, not from the selection.** `NSTableView.action` also fires
  for the row that is highlighted already, and `tableView.clickedRow` is valid in it. The arrow keys move the
  highlight without opening anything, so the highlight and the open note can differ until the coordinator renders the
  list again (`SidebarList` turns Return into `onReturn`). ⌘-click on the highlighted row deselects it, which
  `open(_:inNewTab:)` undoes by rendering the sidebar even when it has nothing to show.
- **The tab strip is an `NSGlassEffectView` pinned inside a plain view, with a frame-based content view.**
  `TabStripView` (the strip's own view) gets its width from the tabs as its intrinsic content size, with a compression
  resistance (40) below the fitting size priority (50), and `EditorAreaViewController` caps it with a required
  `trailing <=` constraint. The glass is pinned to the edges of `TabStripView`, and its own content hugging and
  compression resistance are set to 1: left at the default, the glass hugged an intrinsic width of its own and the strip
  came out 10 pt wide on CI, a sliver that a click on the second tab missed (`TabStripViewControllerTests` measure the
  strip). A width constraint on the strip, at any priority above 50, would make the split view item's minimum width grow
  with the number of tabs. Do not use `NSStackView` with required widths in the strip for the same reason.
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
