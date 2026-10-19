#!/usr/bin/env bash
# Tests for scripts/perf-extract.py: it turns the metrics of a ScratchPerf result bundle into one flat JSON of
# milliseconds (plan 1 task 10). Feeds it synthetic files in the shape `xcresulttool` writes (--metrics-json and
# --attachments-dir replace the two `xcrun xcresulttool` calls), so it needs neither macOS nor a real run.
# Run with `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/perf-extract.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
}

# expect_exit <description> <code> <command...>: runs the command, leaves its output in $TMP/out.txt.
expect_exit() {
    local desc=$1 want=$2 got=0
    shift 2
    "$@" >"$TMP/out.txt" 2>&1 || got=$?
    if [[ $got -eq $want ]]; then
        pass "$desc"
    else
        fail "$desc (exit $got, wanted $want)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

# output_has <description> <fixed text>: the last output contains the text.
output_has() {
    if grep -qF -- "$2" "$TMP/out.txt"; then pass "$1"; else
        fail "$1 (missing: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

# value_is <description> <json file> <key> <expected>: the key holds that number (to three decimals), or is absent
# when the expected value is "absent".
value_is() {
    local actual
    actual=$(python3 - "$2" "$3" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
value = data.get(sys.argv[2])
print("absent" if value is None else f"{value:.3f}")
PY
    )
    if [[ $actual == "$4" ]]; then pass "$1"; else fail "$1 (got $actual, wanted $4)"; fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/perf-extract.py exists"; else
    fail "scripts/perf-extract.py exists"
    echo "$failures perf-extract test(s) failed" >&2
    exit 1
fi

# A metrics file in the shape of `xcresulttool get test-results metrics` (the metric names are as a real run on
# macos-26 wrote them): tests, their runs, their metrics.
cat >"$TMP/metrics.json" <<'JSON'
[
  {
    "testIdentifier": "LaunchPerfTests/testLaunch()",
    "testRuns": [{"metrics": [{
      "displayName": "Duration (ApplicationLaunch)",
      "identifier": "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationLaunch.duration",
      "unitOfMeasurement": "s", "measurements": [0.2, 0.25, 0.3]}]}]
  },
  {
    "testIdentifier": "EditorPerfTests/testKeystroke()",
    "testRuns": [{"metrics": [
      {"displayName": "Duration", "identifier": "com.apple.dt.XCTMetric_Clock.time.monotonic",
       "unitOfMeasurement": "s", "measurements": [9.0, 9.0]},
      {"displayName": "Duration (keystroke)",
       "identifier": "com.apple.dt.XCTMetric_OSSignpost-keystroke.duration",
       "unitOfMeasurement": "ms", "measurements": [2.0, 4.0, 300.0]}]}]
  },
  {
    "testIdentifier": "EditorPerfTests/testSwitchToSmallNote()",
    "testRuns": [{"metrics": [{
      "displayName": "Duration (switch-note)",
      "identifier": "com.apple.dt.XCTMetric_OSSignpost-switch-note.duration", "unitOfMeasurement": "s", "measurements": [0.003, 0.005]}]}]
  },
  {
    "testIdentifier": "EditorPerfTests/testSwitchToHugeNote()",
    "testRuns": [{"metrics": [{
      "displayName": "Duration (switch-note)",
      "identifier": "com.apple.dt.XCTMetric_OSSignpost-switch-note.duration", "unitOfMeasurement": "µs", "measurements": [40000, 60000]}]}]
  },
  {"testIdentifier": "EditorPerfTests/testScrollHugeNote()", "testRuns": [{"metrics": []}]}
]
JSON

# What `xcresulttool export attachments` writes: the files and a manifest.json that names them.
mkdir -p "$TMP/attachments"
printf '{"max_frame_ms": 12.5, "p95_frame_ms": 7.5, "median_frame_ms": 1.75, "max_cpu_ms": 6.5, "p95_cpu_ms": 2.5, "median_cpu_ms": 0.75, "frames": 300}\n' >"$TMP/attachments/A1.txt"
printf 'not a number\n' >"$TMP/attachments/B2.txt"
cat >"$TMP/attachments/manifest.json" <<'JSON'
[
  {
    "testIdentifier": "EditorPerfTests/testScrollHugeNote()",
    "attachments": [
      {"exportedFileName": "B2.txt", "suggestedHumanReadableName": "notes_0_2B8F3A6E-0000-4000-8000-000000000001.txt"},
      {"exportedFileName": "A1.txt", "suggestedHumanReadableName": "scroll_frame_ms_0_2B8F3A6E-0000-4000-8000-000000000002.txt"}
    ]
  }
]
JSON

extract() { # extract <out json> [extra args]
    local out=$1
    shift
    python3 "$SCRIPT" "$TMP/none.xcresult" "$out" --metrics-json "$TMP/metrics.json" \
        --attachments-dir "$TMP/attachments" "$@"
}

echo "== extracting"
expect_exit "extracts a run" 0 extract "$TMP/out/results.json"
value_is "launch_ms is the median of the launches, in milliseconds" "$TMP/out/results.json" launch_ms 250.000
value_is "keystroke_ms picks the signpost metric, not the clock, and ignores an outlier" "$TMP/out/results.json" keystroke_ms 4.000
value_is "switch_small_ms converts seconds" "$TMP/out/results.json" switch_small_ms 4.000
value_is "switch_huge_ms converts microseconds" "$TMP/out/results.json" switch_huge_ms 50.000
value_is "scroll_frame_ms is the median CPU time in the scroll_frame_ms attachment" "$TMP/out/results.json" scroll_frame_ms 0.750
value_is "scroll_frame_wall_ms is the median frame by the clock" "$TMP/out/results.json" scroll_frame_wall_ms 1.750
value_is "scroll_frame_p95_ms is the 95th percentile of the CPU time" "$TMP/out/results.json" scroll_frame_p95_ms 2.500
value_is "scroll_frame_max_ms is the longest CPU time there" "$TMP/out/results.json" scroll_frame_max_ms 6.500

echo "== raw copies"
expect_exit "--raw-dir keeps what was read" 0 extract "$TMP/out2/results.json" --raw-dir "$TMP/raw"
if [[ -f $TMP/raw/metrics.json && -f $TMP/raw/scroll_frame_ms.json ]]; then
    pass "the raw metrics and the scroll attachment are copied"
else fail "the raw metrics and the scroll attachment are copied"; fi

echo "== something missing"
rm "$TMP/attachments/A1.txt"
expect_exit "a missing scroll attachment is a warning, not an error" 0 extract "$TMP/out3/results.json"
value_is "the scroll metric is left out" "$TMP/out3/results.json" scroll_frame_ms absent
value_is "so is the longest frame" "$TMP/out3/results.json" scroll_frame_max_ms absent
value_is "the others are still there" "$TMP/out3/results.json" launch_ms 250.000
output_has "the warning names the metric" "scroll_frame_ms"

printf '[]\n' >"$TMP/empty-metrics.json"
rm "$TMP/attachments/manifest.json"
expect_exit "a run with no metrics at all is an error" 1 \
    python3 "$SCRIPT" "$TMP/none.xcresult" "$TMP/out4/results.json" --metrics-json "$TMP/empty-metrics.json" \
    --attachments-dir "$TMP/attachments"

echo "== bad input"
expect_exit "no arguments is a usage error" 2 python3 "$SCRIPT"
printf 'not json\n' >"$TMP/bad.json"
expect_exit "a metrics file that is not JSON is an error" 1 \
    python3 "$SCRIPT" "$TMP/none.xcresult" "$TMP/out5/results.json" --metrics-json "$TMP/bad.json" \
    --attachments-dir "$TMP/attachments"

if [[ $failures -ne 0 ]]; then
    echo "$failures perf-extract test(s) failed" >&2
    exit 1
fi
echo "all perf-extract tests passed"
