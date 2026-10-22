# 0009: Performance at 1.0: the launch gates on Scratch's own work, and idle is measured

Status: accepted, 2026-10-22 (Plan 6, task 2, Scratch 1.0.0). Amends [0003](0003-ci-performance-checks.md): the launch
budget, the launch baseline and the way a result is compared. Adds two metrics, `launch_overhead_ms` and `idle_cpu_pct`,
and a file of tolerances. No new dependency: the reference app is an AppKit app of this repository, and the idle monitor
reads `getrusage`.

The spec's two rules stay (§7): a result more than 20% over its baseline, or more than twice its budget, fails, and a
result over its budget inside those limits warns. What changes is which number the launch is held to, and that a metric
the runner moves by an amount of milliseconds may be allowed that amount.

## Context

- **The absolute launch cannot gate on these runners.** `launch_ms` is the median of ten launches of one build, and the
  runner's own speed is most of it. Main's run of 0.5.0 (`f5ba72a`) measured 0.60 to 1.14 s across its ten launches, the
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
2. **`launch_overhead_ms` = `launch_ms` − `launch_reference_ms`, both medians of 10 launches.** `testReferenceLaunch`
   measures `LaunchReference.app` like `testLaunch` measures Scratch (the same three warm-up launches, the same ten
   iterations of `XCTApplicationLaunchMetric()`), launched by its URL (`XCUIApplication(url:)`), in the same job on the same
   runner. The runner's speed is in both numbers, and what is left is the work Scratch adds to what any app with a window and a
   TextKit 1 text view costs: its storage, session restore, menus, sidebar, tab strip, styling and the rest. The budget is
   150 ms: the spec's 200 ms launch (§7) less a share for what every app's launch costs, which is not Scratch's to save.
   The owner's Mac will say whether that share is right (the last section), and the tolerance below applies.
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

## Measured numbers

To be filled in from the first CI runs of this task.

## The owner's Mac

The numbers of the owner's M4 come from Help > Launch Times… and are filled in after the release (a table of the first launch
after start-up and the median of the others, against the spec's 500 ms and 200 ms).

| | First after start-up | Other launches | Idle CPU |
|---|---|---|---|
| Spec §7 | 500 ms | 200 ms | 0 (no wake-ups) |
| Owner's M4, 1.0.0 | to be measured | to be measured | to be measured |
