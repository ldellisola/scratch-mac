#!/usr/bin/env python3
"""Extract the numbers of one ScratchPerf run from its result bundle.

    perf-extract.py <xcresult> <out.json> [--raw-dir DIR]

Writes <out.json>, a flat JSON object of milliseconds that perf-check.py reads:

    {"launch_ms": ..., "keystroke_ms": ..., "scroll_frame_ms": ..., "switch_small_ms": ..., "switch_huge_ms": ...}

Two sources, both read from <xcresult> with `xcrun xcresulttool`:

- `get test-results metrics`: the XCTest metrics. launch_ms is LaunchPerfTests/testLaunch (XCTApplicationLaunchMetric),
  keystroke_ms, switch_small_ms and switch_huge_ms are the signpost intervals `keystroke` and `switch-note` of the
  EditorPerfTests tests. A value is the median of that test's measurements, in milliseconds. The median, because
  a run on a shared virtual Mac now and then has one iteration that takes ten times as long (an outlier of 228 ms
  among keystrokes of 3 ms moved the mean by 6 ms), and a metric that such an iteration moves cannot be compared
  with a baseline.
- `export attachments`: EditorPerfTests/testScrollHugeNote attaches the app's FrameMonitor report under the name
  `scroll_frame_ms` (XCTest has no metric for the main thread's work per frame). scroll_frame_ms is its
  `p95_frame_ms`, the 95th percentile of 300 frames, and scroll_frame_max_ms, which no budget checks, is its
  `max_frame_ms`. The maximum is one frame, and on a shared virtual Mac one frame in 300 now and then takes ten times
  as long: three runs of the same build had maxima of 5.5, 12 and 34 ms, and 95th percentiles of 3.7, 5.3 and 7.2 ms.

A metric that is not found is left out of <out.json> with a warning on stderr, and perf-check.py fails the run for it.
Nothing found at all is an error.

--raw-dir DIR keeps what was read (metrics.json, scroll_frame_ms.json), so that a result can be examined later.
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
    "keystroke_ms": ("EditorPerfTests/testKeystroke", "keystroke"),
    "switch_small_ms": ("EditorPerfTests/testSwitchToSmallNote", "switch-note"),
    "switch_huge_ms": ("EditorPerfTests/testSwitchToHugeNote", "switch-note"),
}
# The attachment of the scroll test: its name, and the keys of its JSON that are results: result key -> JSON key.
SCROLL_KEY = "scroll_frame_ms"
SCROLL_ATTACHMENT = "scroll_frame_ms"
SCROLL_FIELDS = {"scroll_frame_ms": "p95_frame_ms", "scroll_frame_max_ms": "max_frame_ms"}

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


def extract_scroll(attachments_dir: Path, raw_dir: Path | None) -> dict[str, float]:
    """The numbers of the last attachment named scroll_frame_ms that has the 95th percentile (SCROLL_FIELDS), or {}."""
    try:
        manifest = json.loads((attachments_dir / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if isinstance(manifest, dict):
        manifest = manifest.get("tests") or manifest.get("attachments") or []
    files = []
    for entry in manifest if isinstance(manifest, list) else []:
        for attachment in entry.get("attachments", []) if isinstance(entry, dict) else []:
            suggested = str(attachment.get("suggestedHumanReadableName", ""))
            source = attachments_dir / str(attachment.get("exportedFileName", ""))
            if suggested.startswith(SCROLL_ATTACHMENT) and source.is_file():
                files.append(source)
    for source in reversed(files):
        try:
            report = json.loads(source.read_text(encoding="utf-8"))
            numbers = {key: report[field] for key, field in SCROLL_FIELDS.items() if field in report}
        except (OSError, ValueError, TypeError):
            continue
        if is_number(numbers.get(SCROLL_KEY)) and all(is_number(value) for value in numbers.values()):
            if raw_dir is not None:
                shutil.copyfile(source, raw_dir / "scroll_frame_ms.json")
            return {key: float(value) for key, value in numbers.items()}
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

        with tempfile.TemporaryDirectory() as scratch:
            if args.attachments_dir is not None:
                attachments_dir = args.attachments_dir
            else:
                attachments_dir = Path(scratch)
                run_xcresulttool("export", "attachments", "--path", str(args.xcresult), "--output-path", scratch)
            scroll = extract_scroll(attachments_dir, args.raw_dir)
        if SCROLL_KEY not in scroll:
            print(
                f"perf-extract.py: warning: no measurement for {SCROLL_KEY} (no attachment {SCROLL_ATTACHMENT})",
                file=sys.stderr,
            )
        results.update(scroll)
    except SourceError as error:
        print(f"perf-extract.py: {error}", file=sys.stderr)
        return 1

    if not results:
        print("perf-extract.py: no performance numbers found in the result bundle", file=sys.stderr)
        return 1
    ordered = {key: round(results[key], 3) for key in [*XCTEST_METRICS, *SCROLL_FIELDS] if key in results}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(ordered, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.out}: {json.dumps(ordered)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
