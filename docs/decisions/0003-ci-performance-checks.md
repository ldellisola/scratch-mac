# 0003: What the CI performance check compares

Status: accepted, 2026-10-19 (plan 1, task 10). Records the numbers CI enforces for the spec §7 budgets: a changed
budget (`launch_ms`) and the choices that make CI's measurements comparable from one run to the next. The spec's two
rules stay: CI fails a result that is more than 20% slower than the stored baseline or more than twice its budget, and
warns when a result is over its budget but inside those limits.

## Context

CI measures on GitHub's virtual Macs (`macos-26`, macOS 26.6.2), and the budgets are the owner's M4's. In the runs of
ADR 0001 (three of TextKit 1 and two of TextKit 2, the same suite each time) two things stood out:

- **Runs of the same build differ by a factor of 1.5 to 2.** The keystroke median of the same code was 3.6 to 4.5 ms in
  one round of runs and 6.7 ms in another, and the first run of a job is slower than the later ones. A single
  keystroke now and then takes 20 to 60 times the median (228 ms in one run).
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

1. **`launch_ms` is budgeted at 400 ms on CI** (`perf/budgets.json`), against the spec's 200 ms: a warning above
   400 ms, a failure above 800 ms or 20% above the baseline. The 200 ms is still the target on the owner's M4 and is
   checked by hand there, like the cold-boot number (§7). The other four budgets are the spec's.
2. **A metric is the median of its measurements**, not the mean: one slow iteration in a hundred moves the mean by
   several milliseconds and cannot be compared with a baseline. The median is `keystroke_ms`, `switch_small_ms`,
   `switch_huge_ms` and `launch_ms` (`scripts/perf-extract.py`).
3. **`scroll_frame_ms` is the 95th percentile of 300 scripted frames**, not the longest. The spec says "no frame over
   8 ms". On this runner the longest of 300 frames of the same build was 5.5, 12.0 and 34.3 ms in three runs, and the
   95th percentile 3.7, 5.3 and 7.2 ms. The longest frame is still reported (`scroll_frame_max_ms` in `results.json`,
   not checked), and a person looking at a regression reads both.
4. **The app scrolls itself** (`FrameMonitor`, `-ScratchFrameMonitor <path>`): 20 points every 1/60 s for 5 seconds,
   starting 3.5 seconds after launch, measuring the main thread's work per frame as the time from the run loop waking
   up to its going idle again. Not `XCTOSSignpostMetric.scrollingAndDecelerationMetric`, which I could not check for
   macOS from a Linux session, where a wrong guess does not compile, and not the interval between display link ticks,
   which includes the idle time the budget excludes. Not UI events either: a test sends a few key presses or scroll
   events a second, and the first runs scrolled 11 frames out of 250 key presses (an arrow key scrolls a third of a
   window). The plan names the in-app monitor as the fallback, which is this.
5. **The launch test uses `XCTApplicationLaunchMetric()`**, not `waitUntilResponsive: true`, which reported a launch for
   the first iteration only ("Received unexpected number of metrics: 0 in iteration with index N") in every one of
   the five runs of ADR 0001. The test launches three times before it measures, because the first launches were the
   slowest (0.53 s, then 0.37 s).
6. **Signposts end when the main run loop is idle** (`RunLoopIdle`), not when the code returns, so that TextKit's lazy
   layout and drawing are inside the `keystroke` and `switch-note` intervals (ADR 0001 has the evidence: TextKit 2
   never calls `draw(_:)`).
7. **The baseline is the slowest run, not an average** (`perf/baseline.json`). Per metric, the largest median of the
   runs of TextKit 1 of the decision (the keystroke's 6.7 ms is from an earlier round of runs, the others from the
   last one):

   | | `launch_ms` | `keystroke_ms` | `scroll_frame_ms` | `switch_small_ms` | `switch_huge_ms` |
   |---|---|---|---|---|---|
   | baseline | 581.5 | 6.7 | 7.2 | 13.5 | 64.1 |
   | allowed (1.2 x) | 697.8 | 8.0 | 8.6 | 16.2 | 76.9 |

   With the first run of a job 1.5 to 2 times slower than the later ones, a baseline taken from a fast run would fail
   a good build. This baseline still fails a TextKit 2 build (keystroke 19.8 to 28.0 ms), which is the kind of
   regression the check is for.

## How to change them

A budget changes only with a record like this one. A baseline is recorded after an intended change, from at least three
runs of the macOS job: take the largest median of each metric from `ci-results/<sha>/macos/perf/results.json` (`make
perf-baseline` writes one run's numbers, which on a laptop are not CI's). If CI fails a metric that no change of the
code explains, look at the run's `perf/report.md` and `perf/metrics.json` before touching the baseline.
