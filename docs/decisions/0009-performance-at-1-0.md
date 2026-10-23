# 0009: Performance at 1.0: the launch gates on Scratch's own work, and idle is measured

Status: accepted, 2026-10-22 (Plan 6, tasks 2, 3 and 10, Scratch 1.0.0). Amends [0003](0003-ci-performance-checks.md): the launch
budget, the launch baseline and the way a result is compared. Adds two gated metrics, `launch_overhead_ms` and `idle_cpu_pct`,
and a file of tolerances. No new dependency: the reference app is an AppKit app of this repository, and the idle monitor
reads `getrusage`.

The spec's two rules stay (§7): a result more than 20% over its baseline, or more than twice its budget, fails, and a
result over its budget inside those limits warns. What changes is which number the launch is held to, and that a metric
the runner moves by an amount of milliseconds may be allowed that amount.

## Context

- **The absolute launch cannot gate on these runners.** `launch_ms` was the median of ten launches of one build, and
  the runner's own speed is most of it. Main's run of 0.5.0 (`f5ba72a`) measured 0.60 to 1.14 s across its ten launches, the
  medians of runs of one build were 331 to 776 ms (0003), and the commits `a698055` and `4faafbe`, which changed only
  documents, measured 800 and 1,027 ms. A budget of 400 ms with a failure at 800 ms failed builds that had not changed. A
  system app (Calculator) takes 0.9 to 1.6 s on the same runner (0003), so the spec's 200 ms is not reachable by any app
  there, and no baseline taken from it can be both sharp and stable.
- **Idle had no measurement.** The spec asks that a scratchpad that sits open all day costs nothing (§7: no wake-ups or CPU
  use while idle), and nothing in CI looked.

## Decisions

1. **`LaunchReference` is the floor of the launch** (`App/LaunchReference`, bundle id
   `io.github.ldellisola.Scratch.LaunchReference`). It is an AppKit app that shows one 1100 x 700 titled window with a
   TextKit 1 text view (`NSTextView(usingTextLayoutManager: false)`, in a scroll view) holding one line of SF Mono text,
   makes the window key and activates. It has no menu, no storage, no sidebar and no toolbar, on purpose. It is a target
   of `App/project.yml` that `ScratchPerfTests` depends on (built with the tests, into the same products folder, not
   linked), and neither the `Scratch` scheme, which makes the release, nor the Scratch target know it: it is never part
   of the app or of a release.
2. **`launch_overhead_ms` is what Scratch's launch costs above the reference's, at the speed of a nominal runner:**
   `(launch_ms − launch_reference_ms) × 200 / launch_reference_ms`, from the medians of 30 launches of each app.
   `testReferenceLaunch` measures `LaunchReference.app` like `testLaunch` measures Scratch (the same three warm-up launches,
   the same `LaunchPerfTests.measuredLaunches` iterations of `XCTApplicationLaunchMetric()`), launched by its URL
   (`XCUIApplication(url:)`), in the same job on the same runner. What is left of Scratch's launch after the reference's is the
   work Scratch adds to what any app with a window and a TextKit 1 text view costs: its storage, session restore, menus,
   sidebar, tab strip, styling and the rest. The budget is 150 ms: the spec's 200 ms launch (§7) less a share for what every
   app's launch costs, which is not Scratch's to save. The owner's Mac will say whether that share is right (the last section).

   **Two things differ from the plan, both found by measuring** ("Measured numbers"):
   - **The plan has the plain difference, `launch_ms − launch_reference_ms`.** It is Scratch's own work in milliseconds on the
     runner of the day, and the work is CPU-bound, so a slow runner makes it longer: 181, 224, 264, 337 and 432 ms in five
     runs of one app, 39% to 53% of `launch_ms`. A gate on it fails the app for the runner, the thing the reference app is
     there to prevent, and the run of `752a281` did (336.8 ms against a limit of 300). The ratio of the two launches does not
     follow the runner (1.65 to 1.73 in five of six runs), so the gated number is the difference scaled to the speed of a
     nominal runner, the one on which the reference launches in `REFERENCE_NOMINAL_MS` = 200 ms
     (`scripts/perf-extract.py`). The difference itself is reported as `launch_difference_ms` (INFO). 200 only scales the
     metric. It puts what Scratch costs now (a ratio of about 1.7) near the budget, and the hard limit of 300 ms at a ratio of
     2.5, which no run has come near (2.11 was the highest of six). With 250 a ratio of 2.2 would fail.
   - **The plan has ten launches of each app.** The tests measure 30 (about a minute of CI time each): the launches of one run
     differ by a factor of two, and a median of ten moved by 60 ms or so. A bootstrap over the launches of the runs gives the
     difference of two medians a standard deviation of 67 ms at ten launches and 40 ms at thirty.

   The budget, the tolerance and the limit (150, 60 and 300 ms) are the plan's.
3. **`launch_ms` and `launch_reference_ms` are reported and never fail.** They have no budget, so `perf-check.py` prints
   them as `INFO`: a result whose metric has no budget used to be dropped, and is now a row of the report with the verdict
   `INFO`, so that every number a run measured is in `perf/report.md`. The spec's 200 ms stays the target on the owner's Mac,
   where Help > Launch Times… (Plan 6, task 1) shows whether each launch met it and the cold-boot check can be done.
4. **Where the time goes is measured too.** After its measurement `testLaunch` launches once more and reads the launch
   log's newest records from `debug.state` (`launchTimes`), attached as `launch_phases`. `perf-extract.py` takes the median
   of each phase (`launch_phase_main_ms`, `…_storage_…`, `…_restore_…`, `…_window_…` and `…_firstFrame_…`: milliseconds from
   the process start). They are `INFO` rows: they say which phase a slow launch spent its time in.
5. **Idle is a percentage of one core, measured by the app itself.** `-ScratchIdleMonitor <path>` (`IdleMonitor`) reads
   `getrusage(RUSAGE_SELF)` 3.5 seconds after launch (the launch's own work is over), counts the passes of the main run loop
   that follow a wait, reads `getrusage` again 5 seconds later and writes `{"cpu_ms", "wall_ms", "cpu_pct", "wakeups"}`.
   `IdlePerfTests.testIdle` launches the `typical` fixture, asks the app nothing while it measures (a query through the
   accessibility API is CPU time too), waits for the file and attaches it as `idle_cpu`. A percentage, because an idle app's
   cost is a rate, and because the caret's blink is a timer that the app does not own: AppKit runs it whatever Scratch does,
   so a number of milliseconds would mean different things at 3 and at 10 seconds. `idle_cpu_pct` has a budget of 1.0 (one
   percent of a core) and `idle_wakeups` is reported only.
6. **A tolerance widens the regression limit of one metric** (`perf/tolerances.json`, read by `perf-check.py`
   `--tolerances`, default that file; a metric not in it, or no file, has a tolerance of 0). A result fails when it is above
   1.2 x its baseline + its tolerance, or above 2 x its budget. The rule is for a metric with a small baseline that the runner
   moves by an amount and not by a fraction: 20% of a 120 ms overhead is 24 ms, which one slow run of the runner exceeds on its
   own, and 20% of an idle of 0.4% is 0.08 points.

   | Metric | Budget | Tolerance | Fails above (baseline S) |
   |---|---|---|---|
   | `launch_overhead_ms` | 150 | 60 | 1.2 x S + 60, or 300 |
   | `idle_cpu_pct` | 1.0 | 0.5 | 1.2 x S + 0.5, or 2.0 |
   | every other budgeted metric | as in 0003 | 0 | 1.2 x S, or 2 x its budget |

7. **The baseline is measured again** in Plan 6, task 10, as the slowest of three CI runs of the final app (0003, decision
   7; the numbers are in "Task 10: the baseline" below). Until then `launch_overhead_ms` and `idle_cpu_pct` have no baseline, so they can warn ("no baseline") and fail only
   above twice their budget. The baseline of the overhead is a number at the nominal runner's speed, about 150 to 180, so the
   regression limit (1.2 x S + 60, about 240 to 280) is under the hard limit of 300 and decides, as it should.

## Measured numbers (task 2)

The macOS job's runs of six commits of the same app code, in the order they ran. `f9ede5d` is the last commit before the
reference app and the idle monitor, so it has `launch_ms` only. `a5d9ef8` is the first with the new metrics (Scratch 1.0.0
before task 3 reduces its launch work), and the rest changed documents (and, for the last, the number of launches). The first
five measured ten launches of each app and the last measured thirty. The overhead column is the plan's difference, and the
next one the gated number.

| Commit | `launch_ms` | `launch_reference_ms` | Difference | Ratio | `launch_overhead_ms` (at 200 ms) | Verdict then |
|---|---|---|---|---|---|---|
| `f9ede5d` | 634.5 | not measured | | | | |
| `a5d9ef8` | 442.8 | 261.4 | 181.4 | 1.69 | 138.8 | difference: WARN |
| `4d3d8f7` | 552.1 | 328.5 | 223.6 | 1.68 | 136.1 | difference: WARN |
| `6156b17` | 671.2 | 406.9 | 264.3 | 1.65 | 129.9 | difference: WARN |
| `752a281` | 639.3 | 302.5 | 336.8 | 2.11 | 222.6 | difference: **FAIL** (over 300) |
| `c7107d8` (30 launches) | 1,021.5 | 589.5 | 432.0 | 1.73 | 146.6 | difference: **FAIL** (over 300) |

- **The same app code launched between 443 and 1,021 ms** (medians, in six runs), which is the runner and not the app, and why
  `launch_ms` cannot gate. The reference app moves with the runner too (261, 329, 407, 303 and 589 ms), and Scratch's launch
  moves with it: the ten launches of a run differ by a factor of two (the reference's, 264 to 597 ms in one run; Scratch's,
  680 to 1,464 ms in the last), and the two tests run one after the other, so each sees its own stretch of the runner.
- **The overhead as the plan defines it follows the runner.** 181, 224, 264, 337 and 432 ms: the last two failed the
  limit of 300 with no change to the app, one of them on the slowest runner seen (a launch of 1.02 s) and one on a runner
  like the others (launch 639 ms). The ratio is steadier: 1.69, 1.68, 1.65, 1.73 and one 2.11. Scaled to a runner on which the
  reference launches in 200 ms, the same runs read 139, 136, 130, 147 and 223 ms, and the highest is 77 ms under the limit.
  A bootstrap over the launches of the runs (resampling 30 at a time, per run) puts the mean at 156 ms with a standard
  deviation of 47 ms, and the probability of a result above 300 at under 1%.
- **Idle is nearly nothing.** The app used 1.5 ms of CPU in the 5.001 s of the first run (0.031% of a core), and 0.067%,
  0.075%, 0.247% and 0.386% in the next four, with 3 wake-ups of the main run loop each time, and 5 in the last, at least one
  of them the monitor's own timer that ends the measurement. The budget of 1.0 leaves a wide margin, and the tolerance of 0.5
  is for a runner that is busy elsewhere (the last run was the slowest).
- **Where Scratch's launch goes** (`launch_phase_<name>_ms`, medians over the launches in the log, in milliseconds from the
  process start; 16 launches in each of the first four runs, 20 in the last):

  | Phase | `a5d9ef8` | `4d3d8f7` | `6156b17` | `752a281` | `c7107d8` |
  |---|---|---|---|---|---|
  | `main` (`main.swift` begins) | 60.1 | 83.5 | 97.1 | 90.6 | 130.4 |
  | `storage` (the storage is open) | 101.7 | 143.1 | 157.8 | 167.2 | 214.8 |
  | `restore` (the session is restored) | 272.0 | 357.6 | 430.4 | 427.1 | 546.9 |
  | `window` (the window is shown) | 321.5 | 422.1 | 490.9 | 503.8 | 648.0 |
  | `firstFrame` (on screen, takes keystrokes) | 470.9 | 595.4 | 698.7 | 703.6 | 918.2 |

  In the first run the process is in `main.swift` 60 ms in, opening the storage takes 42 ms more, restoring the session 170
  ms, showing the window 50 ms and the first frame another 150 ms, and in the slower runs every phase is 1.3 to 2.2 times as
  far from the process start as in the fastest one. These are the numbers that task 3 of Plan 6 (less work before the first
  frame) is measured against, and it records its own beside them.

## Task 3: less work before the first frame, and colours sooner after a paste

Plan 6, task 3. Two changes of the app, neither of which needs a new budget or a new dependency.

8. **A launch reads one body** (spec §7: "before the first frame, the launch reads the body of the active tab's note and no
   other"). `SessionCoordinator.restoredTabs` used to read the note of every saved tab in full. It now asks
   `NoteStore.tabInfo(_:)` for all of them, one query over the derived columns (`display_title`, `has_title`, `deleted_at`, and
   `modified_at = created_at`) that names no `body`, and reads the active note in full. The tabs keep every rule they had: a
   tab of a missing or deleted note is dropped, so is a second tab for one note, the saved active tab stays active (else the first
   that is left), and a note that nobody ever typed in stays untouched. The other tabs' bodies are read once the first frame is
   out, on the storage queue, for the query warm-up (`warmUpHighlighting`).
   - **`TabNoteInfo.isNeverUsed` is worked out from the columns:** no title, no line with words, and an edit time equal to the
     creation time. It differs from the old rule (`Note.isEmpty` and equal times) only for a body of fence lines and attachment
     lines alone with two equal dates, which only a fixture writes, and the active note's answer is still the exact one (it is
     read in full). `discardIfUnused` and `isUntouched` still ask `Note.isEmpty` of the note itself before anything is discarded.
   - **What it saves.** One read of a body costs less than a millisecond: on Linux (Release, SQLite, a file database), with 12
     tabs of which one holds a 936 KB note of 10,000 lines, the reads of the old restore took 0.88 ms in all (0.74 ms for the
     big note alone), and the new ones take 0.07 ms with the big note in a tab that is not active (`tabInfo` of the 12 notes is
     0.05 ms), 0.75 ms with it active. The `typical` fixture, which the launch tests use, has two tabs and no big note, so the
     CI cannot see a difference: the saving is real for an owner with several large notes open, and it is milliseconds. It is the
     spec's rule and it makes the launch independent of how many notes are open.
9. **A paste is looked at when it is read** (`NoteTextView.endPaste`), and the colours of the block it will become are asked
   for at once (`CodeBlockStyler.prefetch(block:)`). `PasteClassifier.wrap` reads only the text, so it runs in `endPaste`
   instead of on the next turn of the run loop, and for a wrap the highlighter starts on the code of the block on its queue
   while the main thread waits for that turn (which has to wait for the paste's undo group to close, and then applies the
   same edit: no second detection). The request is the one the block will make (same fence name and code, same hash), so the
   block finds its colours in the cache or in the request that is running (`request` looks there first), and a prefetched
   result that arrives before its block is only cached: it is not counted as a dropped result, and `pump` keeps such a
   request though no block holds its code yet.
   - **A deviation from the plan, found by thinking about the 50,000-line test:** a paste of more than `Highlighter.maximumLength`
     (300,000 UTF-16 units, `PasteClassifier.earlyWrapLimit`) is not looked at in `endPaste`. Such a block is never coloured,
     so there is nothing to get ahead with, and `LargeInsertTests` holds the paste and the wrap of 50,000 lines of JSON (760 KB,
     which `CodeDetector` reads whole) to 500 ms each, in a Debug build: moving a detection of that size into the paste's own turn
     would take from the paste what it gives the wrap. Pastes up to the cap behave as the plan says.

### Measured numbers (task 3)

The macOS job's runs of the app before and after (the red commit `3e93378` ran the app of `e5b09c1` unchanged, so it is a second
sample of the old code). Single runs on runners that differ by a factor of two, as above, so the differences between the rows
are mostly the runner: the reference app launched in 302, 319 and 354 ms.

| Commit | App | `launch_overhead_ms` | `launch_ms` | `launch_reference_ms` | `paste_code_ms` | restore phase (`restore` less `storage`) |
|---|---|---|---|---|---|---|
| `e5b09c1` | before | 174.1 | 564.7 | 301.9 | 73.0 | 214.0 |
| `3e93378` | before | 151.0 | 559.0 | 318.5 | 53.4 | 222.4 |
| `81b0a64` | after | 111.4 | 551.5 | 354.1 | 50.2 | 193.5 |

Phases of `81b0a64` (milliseconds from the process start, medians): `main` 70.0, `storage` 119.9, `restore` 313.4, `window` 368.3,
`firstFrame` 528.8. The two runs of the old app had `main` 76.8 and 83.3, `storage` 133.5 and 140.6, `restore` 347.5 and 363.0,
`window` 402.1 and 420.4, `firstFrame` 600.7 and 617.6.

- **`launch_overhead_ms` is under its budget of 150 in this run** (111.4), against 174.1 and 151.0 before, and every phase is
  12% to 14% earlier than in the two old runs (`firstFrame` 528.8 against 600.7 and 617.6 ms), while `launch_ms` itself is the same
  (551.5 against 564.7 and 559.0) and the reference app was the slowest of the three (354.1 against 301.9 and 318.5 ms). I do
  not claim that this is the change: the reads that it removes are under a millisecond for the fixture (above), so it cannot
  account for 70 ms of `firstFrame`, and the phases moved by that much between the runs of task 2 with the same code (`restore`
  alone was 170 to 332 ms from the `storage` mark in five runs, and `main`, which no code of Scratch has run before, was 60 to
  130 ms). The two sets of launches that the numbers come from are different launches too: `launch_ms` is the median of the 30
  that `XCTApplicationLaunchMetric` measures, the phases the median of the 20 newest records of the log. What this run does say is
  that the change costs nothing, and the overhead budget is met when the runner is kind and warns when it is not, as it did
  before; the baseline of task 10 is the slowest of three runs for that reason.
- **`paste_code_ms` is 50.2**, the lowest of the runs of this plan (53.2 to 83.7 in task 2's five runs with the metric and 53.4 in `3e93378`,
  and 73.0 in `e5b09c1`, the same code). That is what the prefetch is for, and it is within the noise of the runner: a
  single sample cannot separate a gain of 10 to 20 ms (the turn that waits for the undo group, the apply of the edit and the
  restyle, which the highlighting now overlaps) from a fast runner. The hosted test `testPastedCodeIsPrefetched` is what shows
  that the colours are asked for before the wrap and that the block asks for nothing of its own.
- **Where the launch goes now.** The phase from `storage` to `restore` is still about 190 ms of the 530 ms to the first frame, and
  the first frame after the window another 160 ms. Neither is in the reads of the notes. The first phase is everything
  `AppDelegate.launch()` builds before the window shows: the editor, sidebar, tab strip and split view controllers (their glass
  views and the text view's TextKit 1 stack), the window and its toolbar, the coordinator, and then `restore()` (the session
  read, the active note's `show`: the base attributes of its text, the styling of the paragraphs around the scroll anchor and
  the layout the anchor needs, the first render of the tabs and the sidebar). The second is the first layout and draw. The phases
  do not split the first one further: a launch mark inside `launch()` would, and so would Instruments on a Mac. What was tried is
  what the plan names, and no further change is required by it: a later change would start from those two phases.

## Task 10: the baseline

Plan 6, task 10. `perf/baseline.json` holds, for every metric, the slowest result of three runs of the macOS job on one commit
(0003, decision 7). The commit is `533c237`, the app that 1.0.0 ships: task 10 changes documents, the README's pictures and
`perf/baseline.json` and nothing under `App/` or `Packages/`. The job was run three times on it (the first push, and two
re-runs of the workflow run through the GitHub API, each on a runner of its own: a re-run replaces the folder of the commit in
`ci-results`, so each run's `perf/results.json` was copied out before the next began). Milliseconds, except `idle_cpu_pct`
(a percentage of one core) and `idle_wakeups` (a count).

| Metric | Run 1 | Run 2 | Run 3 | Baseline (the slowest) | Fails above |
|---|---|---|---|---|---|
| `launch_overhead_ms` | 163.4 | 287.3 | 176.4 | 287.3 | 300 (the 2 x budget limit: 1.2 x 287.3 + 60 is 404.7) |
| `keystroke_ms` | 5.43 | 6.31 | 5.03 | 6.31 | 7.58 |
| `scroll_frame_ms` | 0.68 | 6.54 | 0.72 | 6.54 | 7.85 |
| `switch_small_ms` | 10.4 | 16.6 | 13.0 | 16.6 | 20.0 |
| `switch_huge_ms` | 31.8 | 34.4 | 27.2 | 34.4 | 41.3 |
| `paste_code_ms` | 74.1 | 94.8 | 90.2 | 94.8 | 100 (the 2 x budget limit: 1.2 x 94.8 is 113.8) |
| `idle_cpu_pct` | 0.062 | 0.137 | 0.081 | 0.137 | 0.66 (1.2 x 0.137 + 0.5) |
| `idle_wakeups` | 3 | 3 | 3 | 3 | reported only |
| `launch_ms` | 526.0 | 816.7 | 555.2 | 816.7 | reported only |
| `launch_reference_ms` | 289.4 | 335.2 | 295.0 | 335.2 | reported only |
| `launch_difference_ms` | 236.5 | 481.5 | 260.2 | 481.5 | reported only |

The phases of the launch log (`launch_phase_<name>_ms`, medians of the launches of the run, from the process start; reported only)
and the other frame statistics are in the baseline file too, as the slowest of the three.

| Phase | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| `main` | 68.5 | 122.5 | 75.7 |
| `storage` | 115.8 | 221.1 | 130.3 |
| `restore` | 316.1 | 562.3 | 358.4 |
| `window` | 378.2 | 674.6 | 424.8 |
| `firstFrame` | 529.0 | 1,002.3 | 563.0 |

- **No run fails the baseline**, and none of the three would have: `perf-check.py` says OK or WARN for every metric of every
  run against the file that they made (the WARNs are the budgets that a CI runner cannot meet: `launch_overhead_ms` over 150 in
  all three, `paste_code_ms` over 50 in all three and `switch_small_ms` over 12 in two, ADR 0003).
- **Run 2 is the slow runner, in every number at once.** The reference app launched in 335 ms (289 and 295), Scratch in 817 ms
  (526 and 555), every phase of the launch was 1.6 to 1.9 times as far from the process start as in the other two, and the
  ratio of the two launches was 2.44 (1.82 and 1.88), where the five runs of task 2 that had a reference had 1.65 to 1.73 in four and 2.11 in one. This is the
  noise that ADR 0003 describes, and it is why the baseline is the slowest run: a baseline taken from runs 1 and 3 would fail
  run 2.
- **The baseline of `launch_overhead_ms` is therefore 287, not the 150 to 180 that decision 7 expected**, and the regression limit
  (1.2 x 287 + 60 = 405) is over the hard limit of 300, so the hard limit decides: the check fails an overhead above 300 and
  nothing under it. That is a coarser gate than the one that decision 7 had in mind (a limit of 240 to 280), and the price of
  taking the slowest of three runs when one runner is slow. A regression of Scratch's own launch work from about 170 ms to under
  300 passes the check. What would see it is what task 2 added to look at: the phases (`launch_phase_<name>_ms`) and
  `launch_difference_ms`, which are in every report, and the owner's own numbers from Help > Launch Times… (the next section).
  The budget, the tolerance and the nominal speed are not changed for it (AGENTS.md, "Performance").
- **`scroll_frame_ms` is bimodal again** (0.68, 6.54 and 0.72 here, 0.27 to 0.86 and 3.4 to 6.8 in the 26 runs of this branch that
  `ci-results` still holds), and one of the three runs was in the slow mode, so the baseline is the slow mode, 6.54, as decision 3
  of 0003 wants it (the old baseline was 5.8). A baseline of the fast mode would fail every run in the slow mode.
- **`paste_code_ms` is limited by the 2 x budget and not by the baseline** (74, 95 and 90 here, 50 to 113 over the 26 runs: 101,
  104 and 113 in three of them). A run above 100 ms with no change to the paste is the runner's, and the job is run again with
  a new commit (AGENTS.md, section 4).
- **`switch_small_ms` and `switch_huge_ms` can still fail on the slowest runner.** The limits are 20.0 and 41.3 ms, and a run in
  the 26 had 22.8 and another 50.7 (with no change of the code). The rule of 0003 is unchanged: look at `perf/report.md` and
  `perf/metrics.json`, then run the job again with a new commit, and touch the baseline only for a change that is meant.
- **The idle numbers are the same size as in task 2** (0.04% to 0.39%, 3 to 5 wake-ups), under the budget of 1.0 by a factor of
  seven.

## The owner's Mac

The numbers of the owner's M4 come from Help > Launch Times… and are filled in after the release (a table of the first launch
after start-up and the median of the others, against the spec's 500 ms and 200 ms).

| | First after start-up | Other launches | Idle CPU |
|---|---|---|---|
| Spec §7 | 500 ms | 200 ms | 0 (no wake-ups) |
| Owner's M4, 1.0.0 | to be measured | to be measured | to be measured |
