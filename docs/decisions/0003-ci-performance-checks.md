# 0003: What the CI performance check compares

Status: accepted, 2026-10-19 (plan 1, task 10). Records the numbers CI enforces for the spec §7 budgets: two changed
budgets (`launch_ms` and `switch_small_ms`) and the choices that make CI's measurements comparable from one run to the
next. The spec's two rules stay: CI fails a result that is more than 20% slower than the stored baseline or more than
twice its budget, and warns when a result is over its budget but inside those limits.

Amended by [0009](0009-performance-at-1-0.md) (plan 6, task 2): `launch_ms` has no budget and cannot fail any more, the launch
is gated on `launch_overhead_ms` (its launch minus that of an empty AppKit app), and a metric may have a tolerance. The
`launch_ms` budget of decision 1 and the `launch_ms` baseline of decision 7 are history, and the rest stands.

## Context

CI measures on GitHub's virtual Macs (`macos-26`, macOS 26.6.2), and the budgets are the owner's M4's. Two things stood
out in the many runs of the performance suite made for ADR 0001 and for this record:

- **Runs of the same build differ by a factor of two, and now and then by five.** Medians of the same code, in
  milliseconds, over fifteen runs of TextKit 1 with the final tests: `launch_ms` 331 to 776, `switch_small_ms` 6.8 to
  17.6, `switch_huge_ms` 39 to 66, and, in the ten of them that typed in the middle of the note, the keystroke 3.5 to 6.3. A run is sometimes slow
  in several metrics at once (the first run of a job most often), so it is not the code. A single keystroke now and
  then takes 20 to 60 times the median (228 ms in one run).
- **A launch takes much longer than 200 ms on this runner whatever the app is.** The same launch measurement on
  Calculator, in the same jobs (medians of 10 launches, after 3 unmeasured ones):

  | Run | Scratch | Calculator |
  |---|---|---|
  | TextKit 1, run 1 | 581.5 ms | 1,293 ms |
  | TextKit 1, run 2 | 441.7 ms | 929 ms |
  | TextKit 1, run 3 | 372.4 ms | 953 ms |
  | TextKit 2, run 1 | 491.2 ms | 1,575 ms |
  | TextKit 2, run 2 | 620.1 ms | 1,484 ms |

  Scratch starts in about a third to a half of the time of a system app. The 200 ms budget cannot be met on this
  runner by any app.

## Decisions

1. **Two budgets are looser on CI than in the spec** (`perf/budgets.json`). The spec's figures are the owner's M4's, and
   they stay the targets there, checked by hand like the cold-boot number (§7). The other three budgets are the spec's.
   - `launch_ms`: **400 ms** instead of 200. A warning above 400 ms, a failure above 800 ms. The calibration against
     Calculator above is the reason.
   - `switch_small_ms`: **12 ms** instead of 8. A warning above 12 ms, a failure above 24 ms. The median of fifteen
     runs is 9.8 ms and the slowest is 17.6 ms, so with the spec's budget the 2x rule (16 ms) fails an ordinary slow
     run. The switch includes a synchronous wait for the storage queue (`persistNow`), which on a virtual disk costs
     several milliseconds that an M4's SSD does not.
2. **A metric is the median of its measurements**, not the mean: one slow iteration in a hundred moves the mean by
   several milliseconds and cannot be compared with a baseline. The median is `keystroke_ms`, `switch_small_ms`,
   `switch_huge_ms` and `launch_ms` (`scripts/perf-extract.py`).
3. **`scroll_frame_ms` is the median CPU time of the main thread per frame**, over 300 scripted frames, not the longest
   frame the spec asks about ("no frame over 8 ms"). On this runner the longest of 300 frames of the same build was
   5.5 to 56 ms and the 95th percentile 2.3 to 29 ms (by the clock), so neither can be compared with a baseline. The
   clock time of the median frame varied from 0.7 to 11.6 ms in six runs, because a frame's clock time includes the
   main thread's waiting. By CPU time the median was 0.7, 1.1, 3.5, 4.0 and 5.8 ms in five runs of the final tests: two modes, a fast
   one and a slow one, and nothing in between to compare with a 20% rule, so the baseline is the slow mode. The
   median frame, the 95th percentile and the longest frame are all in `results.json` for a person
   (`scroll_frame_wall_ms`, `scroll_frame_p95_ms`, `scroll_frame_max_ms`), and the report of the frame monitor (the
   attachment `scroll_frame_ms`) keeps every frame.
4. **The app scrolls itself** (`FrameMonitor`, `-ScratchFrameMonitor <path>`): 20 points every 1/60 s for 5 seconds,
   starting 3.5 seconds after launch, measuring the main thread's work per frame as the time from the run loop waking
   up to its going idle again. Not `XCTOSSignpostMetric.scrollingAndDecelerationMetric`, which I could not check for
   macOS from a Linux session, where a wrong guess does not compile, and not the interval between display link ticks,
   which includes the idle time the budget excludes. Not UI events either: a test sends a few key presses or scroll
   events a second, and the first runs scrolled 11 frames out of 250 key presses (an arrow key scrolls a third of a
   window). The plan names the in-app monitor as the fallback, which is this.
5. **The launch test uses `XCTApplicationLaunchMetric()`**, not `waitUntilResponsive: true`, which reported a launch for
   the first iteration only ("Received unexpected number of metrics: 0 in iteration with index N") in eight of the nine
   runs of the first two rounds, and nothing in the ninth. The test launches three times before it measures, because the first launches
   were the slowest (0.53 s, then 0.37 s).
6. **Signposts end when the main run loop is idle** (`RunLoopIdle`), not when the code returns, so that TextKit's lazy
   layout and drawing are inside the `keystroke` and `switch-note` intervals (ADR 0001 has the evidence: TextKit 2
   never calls `draw(_:)`).
7. **The baseline is the slowest run, not an average** (`perf/baseline.json`): per metric, the largest median of all
   the runs of the final tests on TextKit 1 (fifteen runs of the suite in the spike's fresh jobs and in the `macos` job).
   Each of the slowest came from a different run:

   | | `launch_ms` | `keystroke_ms` | `scroll_frame_ms` | `switch_small_ms` | `switch_huge_ms` |
   |---|---|---|---|---|---|
   | baseline | 776.1 | 6.3 | 5.8 | 17.6 | 65.9 |
   | fails above 1.2 x baseline | 931.3 | 7.6 | 7.0 | 21.1 | 79.1 |
   | fails above 2 x budget | 800 | 16 | 16 | 24 | 100 |

   A baseline taken from a fast run fails good builds: the first version of this check, with the baseline of the
   spike's later runs, failed the `macos` job's first run (the job's performance tests run after the app tests and the
   screenshots, and are slower than in a fresh job). This baseline still fails a TextKit 2 build (keystroke 12.9 to 16.3
   ms in the middle of the note), which is the kind of regression the check is for. It does not catch a regression of
   50% in a metric that is usually far below its baseline: the check is only as sharp as the runner is repeatable.

## How to change them

A budget changes only with a record like this one. A baseline is recorded after an intended change, from at least three
runs of the macOS job: take the largest median of each metric from `ci-results/<sha>/macos/perf/results.json` (`make
perf-baseline` writes one run's numbers, which on a laptop are not CI's). If CI fails a metric that no change of the
code explains, look at the run's `perf/report.md` and `perf/metrics.json` before touching the baseline, and run the job
again: a slow run is a fact about the runner.

## Addendum: `paste_code_ms` (plan 4, task 6)

A sixth metric, for the spec §7 row "Highlight colours appearing after a 500-line code paste: 50 ms". It adds a budget and
changes no other: the budget is the spec's 50 ms, the owner's M4's. On CI the metric is over it, 55 to 85 ms depending on
the runner, so the report says WARN (over budget, inside the 2 x limit) on every run, for the reason that `launch_ms` is a
WARN: the runner is slower than the owner's machine, and by a factor that changes from run to run (this record, above). It
is not made a looser budget, because the fast runners are within a fifth of the real one and the WARN is the right amount
of noise. The CI number is not a measurement of the owner's Mac, where the budget stays the target and is checked by
hand, like the cold-boot number (spec §7).

- **What it measures.** The `paste-code` signpost interval (`Signposts.beginOpenEditorInterval`), from `NoteTextView.paste`
  until the colours of the block that the paste made are on screen: the plain paste and its styling, the detection of the
  language (`PasteClassifier`, `CodeDetector`), the wrap in a fence on the next turn, the highlighting on its queue and the
  colours written back (at most 8 ms at a time), and then the next idle moment of the run loop
  (`CodeBlockStyler.whenHighlighted`). Unlike `keystroke` and `switch-note` it does not end at the first idle moment: the
  colours are written in later turns on purpose (docs/features/code.md).
- **The test.** `CodePastePerfTests.testPasteFiveHundredLinesOfCode` pastes 500 lines of Swift (125 functions of four lines,
  about 11,500 characters) into an empty note with ⌘V, ten times, with different names in each so that the app has not
  coloured any of them before (it keeps the results of the blocks it has seen). The metric is the median of the ten
  (`scripts/perf-extract.py`), like the others, and the test waits for `debug.state` to say nothing is pending before it
  empties the note for the next paste.
- **The baseline is 85.3 ms**: the slowest median of five runs of the macOS job on the final tests, as the baselines above
  are. The app code was the same in all five (the commits after the first only changed the screenshot of the test, a
  document and the baseline). The first baseline was 59.4 ms, the slowest of the first three runs, and the fourth run
  failed it; the second was 73.6 ms, the slowest of four, and the fifth run was slower again. Both were on slow runners
  (`launch_ms` 520 and 871, `switch_small_ms` 13.7 and 13.6, where the first three had 401 to 447 and 7.9 to 9.8): the two
  modes of the runner that decision 3 describes, and a slow one that is slower than the one before. Since 1.2 x 85.3 is
  more than twice the budget, the limit is the 2 x budget one: the check fails a result above 100 ms.

  | Run (commit) | `paste_code_ms` | Fastest and slowest of the ten pastes | Runner |
  |---|---|---|---|
  | `08a6d61` | 57.2 | 51.3 to 77.0 | fast |
  | `e30e901` | 55.1 | 51.8 to 58.5 | fast |
  | `f0a2925` | 59.4 | 50.1 to 81.4 | fast |
  | `5860da5` | 73.6 | 60.8 to 141.3 | slow |
  | `b963c99` | 85.3 | 56.3 to 150.0 | slower |

  A run has one or two pastes well above the others (the first of the launch, where the grammars and their queries load,
  and a slow turn), which is why the metric is the median. The medians of a slow runner are noisy as well: a failure above
  100 ms with no change to the paste is the runner's (AGENTS.md section 4): run the job again.
