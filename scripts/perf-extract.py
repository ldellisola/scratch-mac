#!/usr/bin/env python3
"""Extract the numbers of one ScratchPerf run from its result bundle.

    perf-extract.py <xcresult> <out.json> [--raw-dir DIR]

Writes <out.json>, a flat JSON object that perf-check.py reads (milliseconds, except idle_cpu_pct and idle_wakeups):

    {"launch_ms": ..., "launch_reference_ms": ..., "launch_overhead_ms": ..., "keystroke_ms": ...,
     "switch_small_ms": ..., "switch_huge_ms": ..., "paste_code_ms": ..., "scroll_frame_ms": ...,
     "idle_cpu_pct": ..., "idle_wakeups": ..., "launch_phase_<name>_ms": ...}

Two sources, both read from <xcresult> with `xcrun xcresulttool`:

- `get test-results metrics`: the XCTest metrics. launch_ms is LaunchPerfTests/testLaunch (XCTApplicationLaunchMetric),
  launch_reference_ms is LaunchPerfTests/testReferenceLaunch (the same measurement of LaunchReference.app, an empty
  AppKit app built by the same job: what a launch costs on this runner whatever the app does), keystroke_ms,
  switch_small_ms and switch_huge_ms are the signpost intervals `keystroke` and `switch-note` of the EditorPerfTests
  tests, and paste_code_ms is the signpost interval `paste-code` of
  CodePastePerfTests/testPasteFiveHundredLinesOfCode (a paste of 500 lines of code until its colours are on screen).
  A value is the median of that test's measurements, in milliseconds. The median, because
  a run on a shared virtual Mac now and then has one iteration that takes ten times as long (an outlier of 228 ms
  among keystrokes of 3 ms moved the mean by 6 ms), and a metric that such an iteration moves cannot be compared
  with a baseline. launch_overhead_ms is launch_ms minus launch_reference_ms, Scratch's own launch work, when both
  were measured (docs/decisions/0009).
- `export attachments`: three tests attach a JSON report under a name.
  - EditorPerfTests/testScrollHugeNote attaches the app's FrameMonitor report as `scroll_frame_ms` (XCTest has no
    metric for the main thread's work per frame). scroll_frame_ms is its
    `median_cpu_ms`: the median, over 300 frames, of the CPU time the main thread used for a frame. scroll_frame_wall_ms
    (the median of the frames by the clock), scroll_frame_p95_ms and scroll_frame_max_ms (the 95th percentile and the
    longest frame by CPU time) are for a person: no budget checks them. CPU time, because the clock time of a frame on
    a shared virtual Mac is the main thread's work and its waiting for the window server and for other tenants, and that
    varied between runs of the same build by a factor of five (a median of 1.5 to 9 ms).
  - IdlePerfTests/testIdle attaches the app's IdleMonitor report as `idle_cpu`: idle_cpu_pct is its `cpu_pct` (the
    app's CPU over 5 seconds of idle, as a percentage of one core) and idle_wakeups its `wakeups` (passes of the main
    run loop in those seconds), which is for a person.
  - LaunchPerfTests/testLaunch attaches `launch_phases`: the launch log's newest records (a JSON list, each with
    `phases`: milliseconds from the start of the process to `main`, `storage`, `restore`, `window` and `firstFrame`).
    launch_phase_<name>_ms is the median of a phase over the records. They are for a person too: they say where a
    slow launch spent its time.

A metric that is not found is left out of <out.json> with a warning on stderr, and perf-check.py fails the run for it
when it has a budget. Nothing found at all is an error.

--raw-dir DIR keeps what was read (metrics.json, scroll_frame_ms.json, idle_cpu.json, launch_phases.json), so that a
result can be examined later.
--metrics-json FILE and --attachments-dir DIR stand in for the two `xcresulttool` calls (the tests of this script use
them). Standard library only.

Exit: 0 written, 1 nothing could be extracted or a source could not be read, 2 usage error.
"""

import argparse
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

# Result key -> (test identifier fragment, text that the wanted metric's name or identifier contains).
# An empty hint takes the test's launch metric, or else its first time metric.
XCTEST_METRICS = {
    "launch_ms": ("LaunchPerfTests/testLaunch", "launch"),
    "launch_reference_ms": ("LaunchPerfTests/testReferenceLaunch", "launch"),
    "keystroke_ms": ("EditorPerfTests/testKeystroke", "keystroke"),
    "switch_small_ms": ("EditorPerfTests/testSwitchToSmallNote", "switch-note"),
    "switch_huge_ms": ("EditorPerfTests/testSwitchToHugeNote", "switch-note"),
    "paste_code_ms": ("CodePastePerfTests/testPasteFiveHundredLinesOfCode", "paste-code"),
}
# The attachments of the tests that report through the app's own monitors: the attachment's name, which a name that
# the exported file starts with, and the keys of its JSON that are results: result key -> JSON key.
SCROLL_KEY = "scroll_frame_ms"
SCROLL_ATTACHMENT = "scroll_frame_ms"
SCROLL_FIELDS = {
    "scroll_frame_ms": "median_cpu_ms",
    "scroll_frame_wall_ms": "median_frame_ms",
    "scroll_frame_p95_ms": "p95_cpu_ms",
    "scroll_frame_max_ms": "max_cpu_ms",
}
IDLE_KEY = "idle_cpu_pct"
IDLE_ATTACHMENT = "idle_cpu"
IDLE_FIELDS = {"idle_cpu_pct": "cpu_pct", "idle_wakeups": "wakeups"}
PHASES_ATTACHMENT = "launch_phases"
# The phases of a launch, in the order they happen (LaunchTimer.phases). A phase that is not in the list follows them.
PHASE_ORDER = ["main", "storage", "restore", "window", "firstFrame"]
OVERHEAD_KEY = "launch_overhead_ms"

TO_MILLISECONDS = {
    "s": 1000.0, "sec": 1000.0, "secs": 1000.0, "second": 1000.0, "seconds": 1000.0,
    "ms": 1.0, "millisecond": 1.0, "milliseconds": 1.0,
    "us": 0.001, "microsecond": 0.001, "microseconds": 0.001,
    "ns": 0.000001, "nanosecond": 0.000001, "nanoseconds": 0.000001,
}  # fmt: skip
UNIT_KEYS = ("unitOfMeasurement", "unit", "units", "unitSymbol")


class SourceError(Exception):
    """A source that cannot be read."""


def unit_factor(metric: dict) -> float | None:
    """Milliseconds per unit of this metric, or None when its unit is not a unit of time."""
    for key in UNIT_KEYS:
        unit = metric.get(key)
        if isinstance(unit, str):
            name = unit.strip().lower().replace("µ", "u").replace("μ", "u")
            return TO_MILLISECONDS.get(name)
    return None


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def find_metrics(node: object, test_identifier: str = ""):
    """Yields (test identifier, metric) for every object that has a list of measurements, wherever it is nested."""
    if isinstance(node, dict):
        identifier = node.get("testIdentifier")
        if isinstance(identifier, str):
            test_identifier = identifier
        measurements = node.get("measurements")
        if isinstance(measurements, list) and any(is_number(value) for value in measurements):
            yield test_identifier, node
        for value in node.values():
            yield from find_metrics(value, test_identifier)
    elif isinstance(node, list):
        for value in node:
            yield from find_metrics(value, test_identifier)


def metric_text(metric: dict) -> str:
    return f"{metric.get('identifier', '')} {metric.get('displayName', '')}".lower()


def pick_metric_milliseconds(metrics: list[dict], hint: str) -> list[float] | None:
    """The measurements, in milliseconds, of the metric of one test that `hint` names."""
    timed = [metric for metric in metrics if unit_factor(metric) is not None]
    if not timed:
        return None
    chosen = [metric for metric in timed if hint in metric_text(metric)]
    if not chosen:
        if len(timed) != 1 and hint != "launch":
            return None
        chosen = timed
    # Several metrics of the same name (repeated runs) are pooled. Different names are not mixed.
    first_name = metric_text(chosen[0])
    values: list[float] = []
    for metric in chosen:
        if metric_text(metric) != first_name:
            continue
        factor = unit_factor(metric)
        values.extend(float(value) * factor for value in metric["measurements"] if is_number(value))
    return values or None


def extract_xctest_metrics(metrics_json: object) -> dict[str, float]:
    found = list(find_metrics(metrics_json))
    results: dict[str, float] = {}
    for key, (test_fragment, hint) in XCTEST_METRICS.items():
        test_metrics = [metric for test, metric in found if test_fragment in test]
        values = pick_metric_milliseconds(test_metrics, hint) if test_metrics else None
        if values:
            results[key] = statistics.median(values)
        else:
            print(f"perf-extract.py: warning: no measurement for {key} (test {test_fragment})", file=sys.stderr)
    return results


def attachment_files(attachments_dir: Path, name: str) -> list[Path]:
    """The exported files of the attachments whose name starts with `name`, in the manifest's order."""
    try:
        manifest = json.loads((attachments_dir / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if isinstance(manifest, dict):
        manifest = manifest.get("tests") or manifest.get("attachments") or []
    files = []
    for entry in manifest if isinstance(manifest, list) else []:
        for attachment in entry.get("attachments", []) if isinstance(entry, dict) else []:
            suggested = str(attachment.get("suggestedHumanReadableName", ""))
            source = attachments_dir / str(attachment.get("exportedFileName", ""))
            if suggested.startswith(name) and source.is_file():
                files.append(source)
    return files


def extract_fields(
    attachments_dir: Path, name: str, fields: dict[str, str], required: list[str], raw_dir: Path | None
) -> dict[str, float]:
    """The numbers of the last attachment called `name` that is a JSON object holding `fields` (result key -> JSON key).

    The result keys in `required` must be there as numbers for the attachment to count, else the one before it is
    tried: the other fields are taken when they are numbers. Returns {} without such an attachment.
    """
    for source in reversed(attachment_files(attachments_dir, name)):
        try:
            report = json.loads(source.read_text(encoding="utf-8"))
            numbers = {key: report[field] for key, field in fields.items() if field in report}
        except (OSError, ValueError, TypeError, KeyError):
            continue
        if all(is_number(numbers.get(key)) for key in required):
            if raw_dir is not None:
                shutil.copyfile(source, raw_dir / f"{name}.json")
            return {key: float(value) for key, value in numbers.items() if is_number(value)}
    return {}


def extract_scroll(attachments_dir: Path, raw_dir: Path | None) -> dict[str, float]:
    """The numbers of the last attachment named scroll_frame_ms that has all of SCROLL_FIELDS, or {}."""
    return extract_fields(attachments_dir, SCROLL_ATTACHMENT, SCROLL_FIELDS, list(SCROLL_FIELDS), raw_dir)


def extract_idle(attachments_dir: Path, raw_dir: Path | None) -> dict[str, float]:
    """The numbers of the last attachment named idle_cpu that has a CPU percentage (IDLE_FIELDS), or {}."""
    return extract_fields(attachments_dir, IDLE_ATTACHMENT, IDLE_FIELDS, [IDLE_KEY], raw_dir)


def phase_order(name: str) -> tuple[int, str]:
    return (PHASE_ORDER.index(name) if name in PHASE_ORDER else len(PHASE_ORDER), name)


def extract_phases(attachments_dir: Path, raw_dir: Path | None) -> dict[str, float]:
    """launch_phase_<name>_ms: the median of each phase over the records of the last launch_phases attachment, or {}.

    The attachment is the launch log's newest records as a JSON list (or an object with the list under `records` or
    `launchTimes`), each with `phases`, a name -> milliseconds object.
    """
    for source in reversed(attachment_files(attachments_dir, PHASES_ATTACHMENT)):
        try:
            records = json.loads(source.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(records, dict):
            records = records.get("records") or records.get("launchTimes")
        if not isinstance(records, list):
            continue
        values: dict[str, list[float]] = {}
        for record in records:
            phases = record.get("phases") if isinstance(record, dict) else None
            for name, milliseconds in (phases.items() if isinstance(phases, dict) else []):
                if is_number(milliseconds):
                    values.setdefault(str(name), []).append(float(milliseconds))
        if values:
            if raw_dir is not None:
                shutil.copyfile(source, raw_dir / f"{PHASES_ATTACHMENT}.json")
            return {
                f"launch_phase_{name}_ms": statistics.median(values[name]) for name in sorted(values, key=phase_order)
            }
    return {}


def run_xcresulttool(*arguments: str) -> str:
    command = ["xcrun", "xcresulttool", *arguments]
    try:
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else error
        raise SourceError(f"`{' '.join(command)}` failed: {detail}") from error
    return completed.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract the numbers of one ScratchPerf run.")
    parser.add_argument("xcresult", type=Path, help="the result bundle of `make perf`")
    parser.add_argument("out", type=Path, help="where to write the JSON of milliseconds")
    parser.add_argument("--raw-dir", type=Path, help="also keep the metrics and the scroll attachment here")
    parser.add_argument("--metrics-json", type=Path, help="read this instead of `xcresulttool get test-results metrics`")
    parser.add_argument("--attachments-dir", type=Path, help="read this instead of `xcresulttool export attachments`")
    args = parser.parse_args()

    try:
        if args.raw_dir is not None:
            args.raw_dir.mkdir(parents=True, exist_ok=True)
        if args.metrics_json is not None:
            try:
                metrics_text = args.metrics_json.read_text(encoding="utf-8")
            except OSError as error:
                raise SourceError(f"cannot read {args.metrics_json}: {error}") from error
        else:
            metrics_text = run_xcresulttool("get", "test-results", "metrics", "--path", str(args.xcresult))
        if args.raw_dir is not None:
            (args.raw_dir / "metrics.json").write_text(metrics_text, encoding="utf-8")
        try:
            metrics_json = json.loads(metrics_text)
        except ValueError as error:
            raise SourceError(f"the metrics are not JSON: {error}") from error

        results = extract_xctest_metrics(metrics_json)
        if "launch_ms" in results and "launch_reference_ms" in results:
            results[OVERHEAD_KEY] = results["launch_ms"] - results["launch_reference_ms"]
        else:
            print(
                f"perf-extract.py: warning: no measurement for {OVERHEAD_KEY} "
                "(it needs launch_ms and launch_reference_ms)",
                file=sys.stderr,
            )

        with tempfile.TemporaryDirectory() as scratch:
            if args.attachments_dir is not None:
                attachments_dir = args.attachments_dir
            else:
                attachments_dir = Path(scratch)
                run_xcresulttool("export", "attachments", "--path", str(args.xcresult), "--output-path", scratch)
            scroll = extract_scroll(attachments_dir, args.raw_dir)
            idle = extract_idle(attachments_dir, args.raw_dir)
            phases = extract_phases(attachments_dir, args.raw_dir)
        if SCROLL_KEY not in scroll:
            print(
                f"perf-extract.py: warning: no measurement for {SCROLL_KEY} (no attachment {SCROLL_ATTACHMENT})",
                file=sys.stderr,
            )
        if IDLE_KEY not in idle:
            print(
                f"perf-extract.py: warning: no measurement for {IDLE_KEY} (no attachment {IDLE_ATTACHMENT})",
                file=sys.stderr,
            )
        if not phases:
            print(
                "perf-extract.py: warning: no measurement for launch_phase_<name>_ms "
                f"(no attachment {PHASES_ATTACHMENT})",
                file=sys.stderr,
            )
        results.update(scroll)
        results.update(idle)
        results.update(phases)
    except SourceError as error:
        print(f"perf-extract.py: {error}", file=sys.stderr)
        return 1

    if not results:
        print("perf-extract.py: no performance numbers found in the result bundle", file=sys.stderr)
        return 1
    keys = [
        "launch_ms", "launch_reference_ms", OVERHEAD_KEY,
        *(key for key in XCTEST_METRICS if key not in ("launch_ms", "launch_reference_ms")),
        *SCROLL_FIELDS, *IDLE_FIELDS, *phases,
    ]  # fmt: skip
    ordered = {key: round(results[key], 3) for key in keys if key in results}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(ordered, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.out}: {json.dumps(ordered)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
