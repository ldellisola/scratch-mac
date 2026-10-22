# 0009: Performance at 1.0: the launch gates on Scratch's own work, and idle is measured

Status: accepted, 2026-10-22 (Plan 6, task 2, Scratch 1.0.0). Amends [0003](0003-ci-performance-checks.md): the launch
budget, the launch baseline and the way a result is compared. Adds two metrics, `launch_overhead_ms` and `idle_cpu_pct`,
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
2. **`launch_overhead_ms` = `launch_ms` − `launch_reference_ms`, both medians of 30 launches** (the plan says 10: see "Measured
   numbers"). `testReferenceLaunch` measures `LaunchReference.app` like `testLaunch` measures Scratch (the same three
   warm-up launches, the same `LaunchPerfTests.measuredLaunches` iterations of `XCTApplicationLaunchMetric()`), launched by
   its URL (`XCUIApplication(url:)`), in the same job on the same runner. The runner's speed is in both numbers, and what is
   left is the work Scratch adds to what any app with a window and a TextKit 1 text view costs: its storage, session restore,
   menus, sidebar, tab strip, styling and the rest. The budget is 150 ms: the spec's 200 ms launch (§7) less a share for what
   every app's launch costs, which is not Scratch's to save. The owner's Mac will say whether that share is right (the last
   section), and the tolerance below applies.
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
   7). Until then `launch_overhead_ms` and `idle_cpu_pct` have no baseline, so they can warn ("no baseline") and fail only
   above twice their budget.

## Measured numbers (task 2)

The macOS job's runs of five commits of the same app code, in the order they ran. `f9ede5d` is the last commit before the
reference app and the idle monitor, so it has `launch_ms` only. `a5d9ef8` is the first with the new metrics (Scratch 1.0.0
before task 3 reduces its launch work), and `4d3d8f7`, `6156b17` and `752a281` changed documents only: more samples of what
the runner does to one build. All of them measured ten launches of each app.

| Metric | `f9ede5d` | `a5d9ef8` | `4d3d8f7` | `6156b17` | `752a281` | Budget |
|---|---|---|---|---|---|---|
| `launch_ms` (median of 10) | 634.5 | 442.8 | 552.1 | 671.2 | 639.3 | none (INFO) |
| the ten launches, fastest to slowest | 573 to 677 | 426 to 470 | 414 to 730 | 554 to 888 | 498 to 800 | |
| `launch_reference_ms` (median of 10) | not measured | 261.4 | 328.5 | 406.9 | 302.5 | none (INFO) |
| the ten reference launches | | 227 to 289 | 284 to 492 | 264 to 597 | 244 to 490 | |
| `launch_overhead_ms` | not measured | 181.4 | 223.6 | 264.3 | **336.8** | 150 |
| verdict of `launch_overhead_ms` | | WARN | WARN | WARN | **FAIL** (over 300) | |
| `idle_cpu_pct` | not measured | 0.031 | 0.067 | 0.075 | 0.247 | 1.0 (WARN: no baseline) |
| `idle_wakeups` | not measured | 3 | 3 | 3 | 3 | none (INFO) |

- **The same app code launched up to 230 ms apart in five runs** (medians of 634, 443, 552, 671 and 639 ms), which is the
  runner and not the app, and why `launch_ms` cannot gate. The reference app is the other half of the comparison, and it
  moves with the runner too (261, 329, 407 and 303 ms), but not together with Scratch: the launches of one run differ by a
  factor of two (the reference's, 264 to 597 ms in one run) and the two tests run one after the other, so what the difference
  keeps of the runner's speed is noise.
- **The overhead is a noisy number with a mean of 250 to 270 ms.** It was 181, 224, 264 and 337 ms: 41%, 40%, 39% and 53% of
  `launch_ms`. A bootstrap over the 80 launches of the four runs that have both (resampling them 10 at a time, medians,
  difference) has a mean of 265 ms and a standard deviation of 67 ms, and a probability of about 31% of a result above 300.
  With 30 launches of each app the standard deviation is 40 ms and the probability 26%: more launches take away the noise of
  the median and leave the mean, which is the app's own cost on this runner. So the tests measure 30 launches of each (the
  plan says ten: the one deviation of this task from its numbers, about a minute of CI time for each test), and the budget
  and the tolerance stay as the plan has them (150 ms, 60 ms).
- **What that means for the gate.** The hard limit is twice the budget, 300 ms, and the app's overhead is near it: the run of
  `752a281` failed with no change to the app (336.8 ms), and the same code passed in the three runs before it. Until
  the overhead itself is lower (task 3 of Plan 6 works on it, and the tasks after it change the launch too), a `FAIL` above
  300 ms in `launch_overhead_ms` with no change to the launch is the runner's: push a new commit for another one (AGENTS.md,
  "Performance"). It has a second consequence for task 10: a baseline of the slowest of three runs would be near 300, where
  the regression limit (1.2 x S + 60) is above the hard limit, so the hard limit decides. If the final app's overhead is still
  near 250, the budget needs what `launch_ms` got in 0003 (a CI budget looser than the spec's, with its reason written here).
- **Idle is nearly nothing.** The app used 1.5 ms of CPU in the 5.001 s of the first run (0.031% of a core), and 0.067%,
  0.075% and 0.247% in the next three, with 3 wake-ups of the main run loop each time, at least one of them the monitor's own
  timer that ends the measurement. The budget of 1.0 leaves a wide margin, and the tolerance of 0.5 is for a runner that is
  busy elsewhere.
- **Where Scratch's launch goes** (`launch_phase_<name>_ms`, medians over the launches in the log, in milliseconds from the
  process start; 16 launches in each run):

  | Phase | `a5d9ef8` | `4d3d8f7` | `6156b17` | `752a281` |
  |---|---|---|---|---|
  | `main` (`main.swift` begins) | 60.1 | 83.5 | 97.1 | 90.6 |
  | `storage` (the storage is open) | 101.7 | 143.1 | 157.8 | 167.2 |
  | `restore` (the session is restored) | 272.0 | 357.6 | 430.4 | 427.1 |
  | `window` (the window is shown) | 321.5 | 422.1 | 490.9 | 503.8 |
  | `firstFrame` (on screen, takes keystrokes) | 470.9 | 595.4 | 698.7 | 703.6 |

  In the first run the process is in `main.swift` 60 ms in, opening the storage takes 42 ms more, restoring the session 170
  ms, showing the window 50 ms and the first frame another 150 ms, and in the slower runs every phase is 1.3 to 1.6 times as
  far from the process start as in the faster one. These are the numbers that task 3 of Plan 6 (less work before the first
  frame) is measured against, and it records its own beside them.

## The owner's Mac

The numbers of the owner's M4 come from Help > Launch Times… and are filled in after the release (a table of the first launch
after start-up and the median of the others, against the spec's 500 ms and 200 ms).

| | First after start-up | Other launches | Idle CPU |
|---|---|---|---|
| Spec §7 | 500 ms | 200 ms | 0 (no wake-ups) |
| Owner's M4, 1.0.0 | to be measured | to be measured | to be measured |
