#!/usr/bin/env python3
"""Compare one performance run with the stored baseline and the budgets (spec §7).

    perf-check.py --results <json> --baseline perf/baseline.json --budgets perf/budgets.json [--tolerances <json>]

Each file is a flat JSON object keyed by metric: launch_overhead_ms, keystroke_ms, scroll_frame_ms, switch_small_ms,
switch_huge_ms, paste_code_ms (milliseconds) and idle_cpu_pct (a percentage of one core), and in the results the
metrics that are only reported (launch_ms, launch_reference_ms, launch_phase_<name>_ms, idle_wakeups...). The metrics
checked are the ones in the budgets file.

Per metric (R the result, B its budget, S its baseline, T its tolerance):

- FAIL when R is more than 1.2 x S + T (it regressed more than 20%, and by more than the tolerance), or more than 2 x B,
  or there is no result at all.
- WARN when R is over B but inside both limits, or when the baseline has no value for the metric (nothing to compare
  with, so only the budget limit applies).
- OK otherwise.

T comes from the tolerances file (`--tolerances`, default perf/tolerances.json of the repository, whatever the working
directory is): a metric that is not in it, or a file that is not there, has a tolerance of 0. A tolerance is for a
metric that the runner moves by an amount in milliseconds, which a percentage of a small baseline cannot absorb
(docs/decisions/0009).

A result whose metric has no budget is printed too, with the verdict INFO: it is reported and never fails.

Prints a Markdown table (metric, result, baseline, budget, verdict, notes) and a last line, `Result: PASS` or
`Result: FAIL`.

Exit: 0 no FAIL, 1 at least one FAIL, 2 unreadable input or a usage error. Standard library only.
"""

import argparse
import json
import sys
from pathlib import Path

# A result may be this many times its baseline, and this many times its budget, before it fails.
MAX_REGRESSION = 1.2
MAX_BUDGET_FACTOR = 2.0
# Absorbs floating point noise: 1.2 * 6 is 7.199999999999999, and 7.2 must still pass.
EPSILON = 1e-9
# Where the tolerances are when --tolerances is not given: the repository's, whatever the working directory is.
DEFAULT_TOLERANCES = Path(__file__).resolve().parent.parent / "perf" / "tolerances.json"


class InputError(Exception):
    """An input file that cannot be used."""


def load_metrics(path: Path, what: str) -> dict[str, float]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise InputError(f"cannot read the {what} file {path}: {error}") from error
    if not isinstance(data, dict):
        raise InputError(f"the {what} file {path} must hold a JSON object")
    metrics = {}
    for key, value in data.items():
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            metrics[key] = float(value)
    return metrics


def load_tolerances(path: Path) -> dict[str, float]:
    """The tolerances in `path`, or none when there is no such file (every metric then has a tolerance of 0)."""
    if not path.exists():
        return {}
    return load_metrics(path, "tolerances")


def verdict_for(
    result: float | None, baseline: float | None, budget: float, tolerance: float = 0.0
) -> tuple[str, list[str]]:
    """The verdict (OK, WARN or FAIL) of one metric, and the reasons for anything but OK."""
    if result is None:
        return "FAIL", ["no result: the metric was not measured"]
    failures = []
    warnings = []
    if result > MAX_BUDGET_FACTOR * budget * (1 + EPSILON):
        failures.append(f"over {MAX_BUDGET_FACTOR:g}x the budget")
    if baseline is None or baseline <= 0:
        warnings.append("no baseline")
    elif result > (MAX_REGRESSION * baseline + tolerance) * (1 + EPSILON):
        reason = f"{(result / baseline - 1) * 100:.0f}% slower than the baseline"
        if tolerance > 0:
            reason += f" (the limit is {MAX_REGRESSION:g}x + {format_number(tolerance)})"
        failures.append(reason)
    if result > budget * (1 + EPSILON):
        warnings.append("over budget")
    if failures:
        return "FAIL", failures + warnings
    if warnings:
        return "WARN", warnings
    return "OK", []


def format_number(value: float | None) -> str:
    return "-" if value is None else f"{value:.2f}".rstrip("0").rstrip(".")


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare a performance run with the baseline and the budgets.")
    parser.add_argument("--results", required=True, type=Path, help="JSON of this run (perf-extract.py)")
    parser.add_argument("--baseline", required=True, type=Path, help="perf/baseline.json")
    parser.add_argument("--budgets", required=True, type=Path, help="perf/budgets.json")
    parser.add_argument(
        "--tolerances", type=Path, default=DEFAULT_TOLERANCES, help="perf/tolerances.json (none: a tolerance of 0)"
    )
    args = parser.parse_args()

    try:
        results = load_metrics(args.results, "results")
        baseline = load_metrics(args.baseline, "baseline")
        budgets = load_metrics(args.budgets, "budgets")
        tolerances = load_tolerances(args.tolerances)
    except InputError as error:
        print(f"perf-check.py: {error}", file=sys.stderr)
        return 2

    print("## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)")
    print()
    print("| Metric | Result | Baseline | Budget | Verdict | Notes |")
    print("|---|---|---|---|---|---|")
    failed = False
    for metric, budget in budgets.items():
        verdict, notes = verdict_for(results.get(metric), baseline.get(metric), budget, tolerances.get(metric, 0.0))
        failed = failed or verdict == "FAIL"
        print(
            f"| {metric} | {format_number(results.get(metric))} | {format_number(baseline.get(metric))} "
            f"| {format_number(budget)} | {verdict} | {'; '.join(notes)} |"
        )
    # What was measured and has no budget: reported, never a verdict that fails.
    for metric, result in results.items():
        if metric not in budgets:
            print(
                f"| {metric} | {format_number(result)} | {format_number(baseline.get(metric))} | - | INFO "
                "| reported, not checked |"
            )
    print()
    print("Result: FAIL" if failed else "Result: PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
