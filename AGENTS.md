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
- Current plan: [`docs/superpowers/plans/2026-10-19-plan-1-walking-skeleton.md`](docs/superpowers/plans/2026-10-19-plan-1-walking-skeleton.md)

## 2. Module map

```
Packages/ScratchCore/             Foundation-only Swift package. Builds and tests on Linux and macOS.
  Sources/CSQLite/                module map for the system SQLite library (no pkgConfig, on purpose)
  Sources/ScratchCore/Notes/      Note and NoteID: the note model, derived title and preview. NoteSummary: a sidebar
                                  row. NoteStore: reads and writes the notes table (pinned first, newest edit first)
  Sources/ScratchCore/Session/    SessionState and TabState (what a relaunch restores), SessionStore (JSON under key
                                  "state"), TextOffset (clamps a saved cursor offset to a Character boundary)
  Sources/ScratchCore/Autosave/   Autosaver (decides when unsaved changes are written: 300 ms after the last change,
                                  at most 1 s after the first, no repeating timers) and the AutosaveScheduler clocks it
                                  runs on: DispatchAutosaveScheduler (production), ManualAutosaveScheduler (tests)
  Sources/ScratchCore/Storage/    Database (thread-safe SQLite wrapper with transactions), Connection (the C API calls),
                                  SQLValue and Row, Schema (version 1 and the migration rule), ScratchStorage (opens
                                  the data directory and its stores; refuses a fixture on the real directory)
  Sources/ScratchCore/Launch/     LaunchOptions: the -Scratch* launch arguments (section 3), TextKitMode and
                                  AppearanceOverride
  Sources/ScratchCore/Fixtures/   Fixture (empty, typical, huge-note, many-notes) and FixtureContent, their notes and
                                  session
  Tests/ScratchCoreTests/         Swift Testing, one test file per source file
App/project.yml                   XcodeGen spec: targets Scratch (app), ScratchAppTests (hosted unit tests),
                                  ScratchUITests, ScratchPerfTests; schemes Scratch and ScratchPerf. The generated
                                  App/Scratch.xcodeproj is never committed.
App/Sources/                      AppKit shell (default actor isolation MainActor). main.swift and AppDelegate (launch
                                  sequence: storage, session, window, menu bar), AppEnvironment (parses the launch
                                  arguments, opens storage; isolates a hosted test run)
App/Sources/Window/               MainWindowController (one window, closing it quits), MainSplitViewController (glass
                                  sidebar item + editor item), MainMenu (menu bar, built in code: there is no storyboard),
                                  ToolbarController (sidebar button, new note button)
App/Sources/Sidebar/              SidebarViewController (the note list: an NSTableView in the glass sidebar)
App/Sources/Session/              SessionCoordinator (which note is open, autosave, restore, new note, the sidebar list;
                                  the one place that writes to storage)
App/Sources/Editor/               NoteTextView (plain-text NSTextView, plain paste and copy), TextViewFactory (TextKit 1
                                  or 2 stack), EditorViewController (shows a note, reports edits, cursor and scroll)
App/Sources/Support/              AccessibilityID (also compiled into the UI test targets), Signposts
App/Resources/                    Assets.xcassets (placeholder app icon)
App/Tests/ScratchAppTests/        hosted XCTest unit tests, run inside the app
App/Tests/ScratchUITests/         XCUITest: UITestSupport launches the app on an isolated data directory (and relaunches
                                  it on the same one); LaunchUITests, PersistenceUITests (force-kill, quit, cursor),
                                  SidebarUITests
App/Tests/ScratchPerfTests/       placeholder until plan 1, Task 10
scripts/                          install-swift-linux.sh (toolchain), session-setup.sh (SessionStart hook),
                                  ci-summary.py, publish-ci-results.sh, ci-wait.sh, ci-fetch.sh (the ci-results loop,
                                  section 4), lib-ci-results.sh (shared by those), tests/ (their tests)
.github/workflows/ci.yml          CI. Job `linux`: lint, core tests, script tests. Job `macos`: XcodeGen, core tests on
                                  macOS, app build and app tests. Both publish to `ci-results`.
docs/architecture.md              module boundaries, data flow, threading
docs/features/                    one short behaviour spec per feature: paste-and-copy.md, autosave-and-restore.md (more as
                                  features land)
docs/decisions/                   numbered decision records
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
- `make script-test` `[linux]`: test the scripts in `scripts/` (the ci-results loop). Prints `all ci script tests
  passed`.
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
- `make run FIXTURE=<name>` `[macOS]`: build the app and open it on a fixture in a throwaway data directory.

Commands for performance, screenshots and releases are added by the tasks that create them.

### Launch arguments

The app reads these flags (`LaunchOptions`) and ignores every other argument. UI tests, screenshots and benchmarks
always pass `-ScratchDataDir`, so they never touch real data.

| Flag | Value | Effect |
|---|---|---|
| `-ScratchDataDir <path>` | any path | use `<path>` instead of `~/Library/Application Support/Scratch` |
| `-ScratchFixture <name>` | `empty`, `typical`, `huge-note`, `many-notes` | delete the database in the data directory and seed that fixture |
| `-ScratchTextKit <1\|2>` | `1` or `2` | choose the TextKit version (removed when the TextKit decision is made) |
| `-ScratchAppearance <light\|dark>` | `light` or `dark` | force the appearance |

A fixture without `-ScratchDataDir` runs in a new `Scratch-<uuid>` directory under the temporary directory. A fixture
is refused on the real data directory (`StorageError.fixtureRequiresIsolatedDirectory`), also when
`-ScratchDataDir` spells that directory differently, for example with `..` or through a symbolic link.

## 4. How to verify a change

1. Write or update the test first and watch it fail for the right reason.
2. `make core-test` and `make lint`, both green.
3. If the change touches behaviour, update the matching `docs/features/*.md` and make sure a test references it.

### The CI loop

Everything that needs macOS runs on GitHub's Macs, and cloud sessions cannot download Actions artifacts. So every CI
job pushes its results to the orphan `ci-results` branch, in a folder `<sha>/<job>/`. The folder holds `summary.json`
(`sha`, `job`, `status`, `steps`, `run_url`, `finished_at`), the last 300 lines of each step's log, and for macOS the
screenshots. The branch keeps the newest 30 shas.

The `macos` job adds to its folder: `test-summary.json` (from `xcresulttool`: passed and failed counts, and each
failure's test name and message in `testFailures`), `app-test-diagnostics.txt` (every compiler warning and error of the
whole build log, which the 300-line tail would cut), and `failure-attachments/` (screenshots that failed UI tests
attached). A hosted test's failure message is also in `app-test.log`: search it for `error:`.

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
- **Never touch `NSTextView.layoutManager` on a TextKit 2 view.** It silently converts the view to TextKit 1. Use
  `textLayoutManager` and `textContentStorage` there. `TextViewFactory` builds both stacks.
- **A TextKit 1 text view does not own its text storage.** The storage owns the layout manager, which owns the
  container, and the links back are unowned. `TextViewFactory` keeps the storage in `NoteTextView.ownedTextStorage`;
  without it the stack is freed when `makeEditor(mode: .one)` returns.
- **A text view needs `NSScrollView.contentInsets` in mind.** The window uses `fullSizeContentView`, so the toolbar
  overlaps the scroll view, and the top of a note is at `y = -contentInsets.top`, not 0 (`EditorViewController.show`).
- **There is no storyboard, so there is no menu bar until `MainMenu.install` runs.** ⌘Q, ⌘C, ⌘V and ⌘Z only work
  because that menu exists. A new shortcut needs a menu item.
- **The coordinator must outlive the autosaver's timers.** `Autosaver` does not keep itself alive: a dirty autosaver
  that is released skips its pending save. `SessionCoordinator` owns it and `AppDelegate` owns the coordinator, so keep
  both. The save closure holds the coordinator weakly. Never replace the autosaver while it is dirty.
- **`SessionCoordinator.persistNow()` waits for the storage queue** (`storageQueue.sync {}`). Call it, `flush()` and
  `open(_:)` on the main thread only, and never from a block that runs on the storage queue.
- **A new note that nobody has used is not in the sidebar** and is discarded when left empty. It is "untouched" while it
  was created in this session (or restored empty) and has no text. Test changes that look at the sidebar must type first.
- **`NSToolbar` holds its delegate weakly.** `AppDelegate` keeps the `ToolbarController`. The new note button is an
  `NSButton` as the item's view, because that is how UI tests get an accessibility identifier on it.
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
