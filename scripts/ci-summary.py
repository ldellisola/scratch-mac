#!/usr/bin/env python3
"""Write summary.json for one CI job.

    ci-summary.py --job <name> --sha <sha> --run-url <url> --out <dir> --step <name>=<outcome> ...

Each --step takes the step's name and its GitHub Actions outcome (success, failure, cancelled or skipped). It can be
repeated, or given several values at once. The step name is everything before the last "=".

The job's status is "success" only when every outcome is "success" or "skipped". Any other outcome, including an
empty one (recorded as "unknown"), makes it "failure".

Writes <dir>/summary.json, which the ci-results scripts and CI agents read:

    {"sha", "job", "status", "steps": [{"name", "outcome"}], "run_url", "finished_at"}

finished_at is UTC with microseconds, so that the publisher can order shas by it. Standard library only.
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

PASSING_OUTCOMES = {"success", "skipped"}


def parse_step(text: str) -> dict:
    name, separator, outcome = text.rpartition("=")
    if not separator or not name.strip():
        raise argparse.ArgumentTypeError(f"expected <name>=<outcome>, got {text!r}")
    return {"name": name.strip(), "outcome": outcome.strip() or "unknown"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Write summary.json for one CI job.")
    parser.add_argument("--job", required=True, help="job name, for example linux or macos")
    parser.add_argument("--sha", required=True, help="the commit the job ran against")
    parser.add_argument("--run-url", required=True, help="URL of the workflow run")
    parser.add_argument("--out", required=True, type=Path, help="directory to write summary.json into")
    parser.add_argument(
        "--step",
        required=True,
        action="append",
        nargs="+",
        type=parse_step,
        metavar="NAME=OUTCOME",
        help="a step and its outcome",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    steps = [step for group in args.step for step in group]
    status = "success" if all(step["outcome"] in PASSING_OUTCOMES for step in steps) else "failure"
    finished_at = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

    summary = {
        "sha": args.sha,
        "job": args.job,
        "status": status,
        "steps": steps,
        "run_url": args.run_url,
        "finished_at": finished_at,
    }
    args.out.mkdir(parents=True, exist_ok=True)
    path = args.out / "summary.json"
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {path} (job {args.job}: {status})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
