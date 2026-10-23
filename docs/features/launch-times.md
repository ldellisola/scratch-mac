# Launch times

How long each launch of Scratch took, written down by the app itself, and Help > Launch Times…, which shows the record
and copies it. Spec: [§7 Performance](../superpowers/specs/2026-10-19-scratchpad-design.md) (the launch budgets: 200 ms,
and 500 ms from a cold boot, "checked by hand when someone is at a real Mac") and §4 (visible lag). Plan:
[Plan 6](../superpowers/plans/2026-10-22-plan-6-polish.md), task 1.

Status: plan 6, tasks 1 and 2 (1.0.0). No CI runner can measure a cold boot, so the app measures its own launches and the
owner reads the numbers on a real Mac. CI gates the launch differently (decision record 0009, "In CI" below).

## The phases

A launch is measured from the start of the process (`LaunchClock.processStart()`: the kernel's `p_starttime`, before dyld
and `main`) to five marks, in milliseconds. `LaunchTimer.mark(_:)` takes each one with a clock read and nothing else:

| Phase | Where | Means |
|---|---|---|
| `main` | the first line of `main.swift` | the process is running Swift |
| `storage` | `AppDelegate.launch()`, after `AppEnvironment.bootstrap` | the database is open and migrated |
| `restore` | after `SessionCoordinator.restore()` | the tabs are restored and the active note is in the editor |
| `window` | after `showWindow` and `editor.focus()` | the window is shown |
| `firstFrame` | `RunLoopIdle.onNext`, the next time the main run loop is about to wait | the note is on screen and accepts keystrokes: the launch ends here (spec §7) |

A launch's **total** is its `firstFrame`.

## The log

`<data directory>/launch-times.json` holds the newest 50 launches, oldest first, as `{"records": [...]}` (`LaunchLog`,
`LaunchRecord` in ScratchCore). A record is the date (of the first frame, whole milliseconds, seconds since 1970), the
app's version, the Mac's boot time (`kern.boottime`), the phases and `isFirstAfterStartUp`.

- **First after start-up.** `LaunchLog.append` marks a record as the first after start-up when no earlier record of the
  log has the same boot time, and ignores what the record said. Boot times less than 30 s apart are the same boot,
  because the kernel moves `kern.boottime` when the clock is set. The first launch after the Mac started is the cold one:
  the spec's 500 ms budget is for it, and 200 ms for every other.
- **Nothing before the first frame.** The log is read, appended to and written by `LaunchTimer.finish(dataDirectory:
  version:)` on its own utility queue, after `firstFrame` has been marked. Before the first frame the launch does a clock
  read for each phase and registers one run loop observer. The process start and the boot time are read on the queue too.
  The record comes back to the main thread afterwards (`LaunchTimer.current`, `LaunchTimer.log`).
- **A log that cannot be read or written changes nothing.** `LaunchLog.load` never throws: a file that is missing, not
  JSON of this shape, larger than a megabyte, or not a file (a directory) is an empty log, and a record that cannot be
  read is left out while the others are kept. `save` writes the file atomically (a launch killed halfway leaves the old
  file), and `finish` drops its error: the launch's record is kept in memory for the run (Help > Launch Times… shows it) and the
  file is left as it was. Writing the log creates the data directory when it is missing.
- **A fixture does not touch it.** `-ScratchFixture` replaces the database and the attachments and leaves
  `launch-times.json`, so a relaunch on the same isolated directory adds a second record (the UI test does that).

## The report

Help > Launch Times… (`LaunchTimesPanel`) shows `LaunchLog.report(version:timeZone:)` in an alert, in local time, newest
first:

```
Scratch 1.0.0, launch times on this Mac, newest first:
2026-10-23 09:20   118 ms
2026-10-23 09:14   412 ms   first after start-up
Other launches, median of the last 1: 118 ms (budget 200 ms). First after start-up, median of 1: 412 ms (budget 500 ms).
```

- A line is the date and time to the minute, the total to the millisecond (right-aligned to five places) and, for the first
  launch after start-up, `first after start-up`.
- The first median is over the newest 10 records that are not first after start-up, the second over the newest 10 that
  are. A summary with no records says `none yet` in place of its number. With no record at all the report is `No
  launches recorded yet.`
- A number that no launch can have (a file edited by hand holds any JSON number) is shown held to 0 and a trillion
  milliseconds: converting one that is out of range to an `Int` would stop the app.
- The alert is a sheet of the window (a panel of its own when there is none), with the report in a selectable, monospaced
  text view (`launchTimes.report`) and the buttons **Copy** (the report as plain text to the general pasteboard, and the
  alert closes) and **OK** (Escape).

## In CI

The absolute launch is not a CI gate: the runner's own speed is most of it (decision record 0009). `LaunchPerfTests` measures
the launch of `LaunchReference.app`, an empty AppKit app, next to Scratch's, and the gate is the difference between
the two, at the speed of a nominal runner (`launch_overhead_ms`: budget 150 ms, tolerance 60). After its measurement `testLaunch` launches Scratch once more, reads the
launch log's newest records from `debug.state` (`launchTimes`) and attaches them as `launch_phases`, and `perf-extract.py`
reports the median of each phase (`launch_phase_<name>_ms`) in `perf/report.md`: they say where a slow launch spent its time
and never fail.

## For tests

`debug.state` (isolated launches only) has `launchTimes`: the newest 20 records of the log, newest first, each with `date`,
`version`, `bootTime`, `isFirstAfterStartUp`, `total` and `phases` (`LaunchTimer.debugRecords`). It is empty until the log
has been written after the first frame, so a UI test waits for it.

## Tests

| What | Test |
|---|---|
| A record's total is its `firstFrame` and survives JSON | ScratchCore `LaunchRecordTests.swift` |
| `isFirstAfterStartUp`, the limit of 50, the file, a corrupt, huge or missing file, a directory in its place (Review Focus 5) | ScratchCore `LaunchLogTests.appendMarksFirstAfterStartUp`, `logKeepsNewestFifty`, `saveAndLoadRoundTrip`, `launchLogIgnoresACorruptFile`, `launchLogIgnoresAHugeFile`, `launchLogIgnoresADirectoryWhereTheFileShouldBe`, `loadKeepsTheGoodRecordsOfAFileWithABadOne` |
| The report, its medians and `none yet` | `LaunchLogTests.reportFormat`, `reportWithNoRecords`, `reportSaysNoneYetForAnEmptySummary`, `reportSummariesUseTheNewestTenOfEachKind`, `reportListsEveryRecordNewestFirstInTheGivenTimeZone`, `reportSurvivesNumbersNoLaunchCanHave` |
| The app's own launch has its five phases in order | `LaunchTimerTests.testPhasesAreInOrder`, UI `LaunchUITests.testLaunchesAreRecordedInTheLaunchLog` |
| `finish` writes nothing itself, the file is there after the queue | `LaunchTimerTests.testLaunchLogIsWrittenAfterTheFirstFrame` |
| An unwritable, a corrupt or a missing log never stops a launch (Review Focus 5) | `LaunchTimerTests.testLaunchSurvivesAnUnwritableLaunchLog`, `testLaunchReplacesACorruptLaunchLog`, `testLaunchGoesOnWithoutADataDirectory` |
| Milliseconds from the process start, rounded, never negative | `LaunchTimerTests.testRecordIsMillisecondsFromTheProcessStart`, `testRecordNeverHasAPhaseBeforeTheProcessStart` |
| The kernel's two moments | `LaunchClockTests` |
| The alert, Copy and the report text | `LaunchTimesPanelTests`, UI `LaunchUITests.testHelpMenuShowsLaunchTimes` |
| CI's launch numbers: the reference app, the overhead, the phases, a result with no budget as INFO, a tolerance | `scripts/tests/test-perf-extract.sh` (`overhead_is_launch_minus_reference`, `phases_are_medians`), `test-perf-check.sh` (`metric_without_budget_is_info`, `tolerance_widens_regression_limit`), `LaunchPerfTests.testReferenceLaunch` and `testLaunch` |
