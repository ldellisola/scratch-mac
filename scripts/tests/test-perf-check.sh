#!/usr/bin/env bash
# Tests for scripts/perf-check.py: it compares a performance run with the stored baseline and the budgets
# (spec §7, plan 1 task 10). Feeds it synthetic JSON files, so it needs neither macOS nor a real run.
# Run with `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/perf-check.py"
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

# output_lacks <description> <fixed text>: the last output does not contain the text.
output_lacks() {
    if grep -qF -- "$2" "$TMP/out.txt"; then
        fail "$1 (found: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    else pass "$1"; fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/perf-check.py exists"; else
    fail "scripts/perf-check.py exists"
    echo "$failures perf-check test(s) failed" >&2
    exit 1
fi

BUDGETS="$TMP/budgets.json"
BASELINE="$TMP/baseline.json"
cat >"$BUDGETS" <<'JSON'
{"launch_ms": 200, "keystroke_ms": 8, "scroll_frame_ms": 8, "switch_small_ms": 8, "switch_huge_ms": 50}
JSON
cat >"$BASELINE" <<'JSON'
{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}
JSON

# check <results json text>: runs perf-check.py on the text against the baseline and budgets above.
check() {
    printf '%s\n' "$1" >"$TMP/results.json"
    python3 "$SCRIPT" --results "$TMP/results.json" --baseline "$BASELINE" --budgets "$BUDGETS"
}

echo "== verdicts"
expect_exit "results at the baseline and inside the budgets pass" 0 check \
    '{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}'
output_has "the report is a Markdown table" "| Metric | Result | Baseline | Budget | Verdict |"
output_has "every metric has a row" "| switch_huge_ms |"
output_has "a passing metric says OK" "OK"
output_lacks "a clean run has no WARN" "WARN"
output_lacks "a clean run has no FAIL" "FAIL"

expect_exit "results exactly 1.2 times the baseline still pass" 0 check \
    '{"launch_ms": 216, "keystroke_ms": 4.8, "scroll_frame_ms": 7.2, "switch_small_ms": 3.6, "switch_huge_ms": 36}'

expect_exit "a result more than 1.2 times its baseline fails" 1 check \
    '{"launch_ms": 180, "keystroke_ms": 4.9, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}'
output_has "the failing metric is marked FAIL" "FAIL"

# 8.5 ms is over the 8 ms budget but inside twice the budget. A baseline of 8 ms keeps it inside 1.2 times too.
cat >"$BASELINE" <<'JSON'
{"launch_ms": 180, "keystroke_ms": 8, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}
JSON
expect_exit "a result over its budget but inside both limits only warns" 0 check \
    '{"launch_ms": 180, "keystroke_ms": 8.5, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}'
output_has "the over-budget metric is marked WARN" "WARN"
output_lacks "a warning is not a failure" "FAIL"

# A result above twice its budget fails even when the baseline is just as bad.
cat >"$BASELINE" <<'JSON'
{"launch_ms": 180, "keystroke_ms": 17, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}
JSON
expect_exit "a result above twice its budget fails" 1 check \
    '{"launch_ms": 180, "keystroke_ms": 17, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}'

cat >"$BASELINE" <<'JSON'
{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}
JSON
# metric_without_budget_is_info: a result that nothing budgets is printed, with the verdict INFO, and never fails.
expect_exit "metric_without_budget_is_info: a result for a metric that has no budget does not fail" 0 check \
    '{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30, "extra_ms": 999}'
output_has "the extra metric is in the report" "| extra_ms | 999 |"
output_has "its verdict is INFO" "INFO"
output_lacks "an INFO row is not a WARN" "WARN"
output_lacks "an INFO row is not a FAIL" "FAIL"

echo "== a metric missing from the baseline"
cat >"$BASELINE" <<'JSON'
{"launch_ms": 180, "keystroke_ms": 4, "switch_small_ms": 3, "switch_huge_ms": 30}
JSON
expect_exit "a metric without a baseline only warns" 0 check \
    '{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}'
output_has "the missing baseline is marked WARN" "WARN"
output_has "the note says why" "no baseline"
expect_exit "a metric without a baseline still fails above twice its budget" 1 check \
    '{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 17, "switch_small_ms": 3, "switch_huge_ms": 30}'

echo "== a metric missing from the results"
cat >"$BASELINE" <<'JSON'
{"launch_ms": 180, "keystroke_ms": 4, "scroll_frame_ms": 6, "switch_small_ms": 3, "switch_huge_ms": 30}
JSON
expect_exit "a metric that was not measured fails" 1 check \
    '{"launch_ms": 180, "keystroke_ms": 4, "switch_small_ms": 3, "switch_huge_ms": 30}'
output_has "the note says it was not measured" "no result"

echo "== tolerances (ADR 0009)"
# A tolerance T widens the regression limit of one metric: it fails above 1.2 x baseline + T. The budget limit (2 x
# budget) stays. launch_overhead_ms has a budget of 150 here, so its budget limit is 300.
cat >"$BUDGETS" <<'JSON'
{"launch_overhead_ms": 150, "keystroke_ms": 8, "idle_cpu_pct": 1.0}
JSON
cat >"$BASELINE" <<'JSON'
{"launch_overhead_ms": 120, "keystroke_ms": 4, "idle_cpu_pct": 0.4}
JSON
TOLERANCES="$TMP/tolerances.json"
cat >"$TOLERANCES" <<'JSON'
{"launch_overhead_ms": 60, "idle_cpu_pct": 0.5}
JSON
# check_with <tolerances file> <results json text>
check_with() {
    printf '%s\n' "$2" >"$TMP/results.json"
    python3 "$SCRIPT" --results "$TMP/results.json" --baseline "$BASELINE" --budgets "$BUDGETS" --tolerances "$1"
}

# tolerance_widens_regression_limit: R 200, S 120, T 60 is inside 1.2 x 120 + 60 = 204. Without the tolerance the limit
# is 144, and it fails.
expect_exit "tolerance_widens_regression_limit: 200 against a baseline of 120 and a tolerance of 60 is not a FAIL" 0 \
    check_with "$TOLERANCES" '{"launch_overhead_ms": 200, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'
output_has "the over-budget result still warns" "WARN"
printf '{}\n' >"$TMP/no-tolerances.json"
expect_exit "the same result fails with a tolerance of 0" 1 \
    check_with "$TMP/no-tolerances.json" '{"launch_overhead_ms": 200, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'
output_has "the failing metric is named" "| launch_overhead_ms |"
output_has "the note says it is slower than the baseline" "slower than the baseline"
expect_exit "a result above 1.2 x baseline + tolerance fails" 1 \
    check_with "$TOLERANCES" '{"launch_overhead_ms": 205, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'
expect_exit "a tolerance does not lift the 2 x budget limit" 1 \
    check_with "$TOLERANCES" '{"launch_overhead_ms": 301, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'
expect_exit "a tolerance applies to its own metric only: keystroke_ms has none" 1 \
    check_with "$TOLERANCES" '{"launch_overhead_ms": 120, "keystroke_ms": 4.9, "idle_cpu_pct": 0.4}'
# idle_cpu_pct: 1.2 x 0.4 + 0.5 = 0.98.
expect_exit "idle_cpu_pct of 0.98 is inside 1.2 x 0.4 + 0.5" 0 \
    check_with "$TOLERANCES" '{"launch_overhead_ms": 120, "keystroke_ms": 4, "idle_cpu_pct": 0.98}'
expect_exit "idle_cpu_pct of 1.1 is over it" 1 \
    check_with "$TOLERANCES" '{"launch_overhead_ms": 120, "keystroke_ms": 4, "idle_cpu_pct": 1.1}'

# missing_tolerances_file_means_zero
expect_exit "missing_tolerances_file_means_zero: a tolerances file that is not there changes nothing" 1 \
    check_with "$TMP/nope-tolerances.json" '{"launch_overhead_ms": 200, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'
expect_exit "and a result inside the limits still passes without it" 0 \
    check_with "$TMP/nope-tolerances.json" '{"launch_overhead_ms": 120, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'
printf 'not json\n' >"$TMP/bad-tolerances.json"
expect_exit "a tolerances file that is not JSON is an error" 2 \
    check_with "$TMP/bad-tolerances.json" '{"launch_overhead_ms": 120, "keystroke_ms": 4, "idle_cpu_pct": 0.4}'

# With no --tolerances the script reads perf/tolerances.json of the repository, wherever it is run from.
printf '%s\n' '{"launch_overhead_ms": 200, "keystroke_ms": 4, "idle_cpu_pct": 0.4}' >"$TMP/results.json"
expect_exit "the default tolerances are perf/tolerances.json's" 0 \
    python3 "$SCRIPT" --results "$TMP/results.json" --baseline "$BASELINE" --budgets "$BUDGETS"
output_has "the report has the row of the metric" "| launch_overhead_ms |"

echo "== the budgets and tolerances of the repository (ADR 0009)"
python3 - "$ROOT/perf/budgets.json" "$ROOT/perf/tolerances.json" <<'PY' && pass "perf/budgets.json and perf/tolerances.json hold the numbers of ADR 0009" || fail "perf/budgets.json and perf/tolerances.json hold the numbers of ADR 0009"
import json, sys
budgets = json.load(open(sys.argv[1]))
tolerances = json.load(open(sys.argv[2]))
assert budgets == {
    "launch_overhead_ms": 150, "keystroke_ms": 8, "scroll_frame_ms": 8, "switch_small_ms": 12, "switch_huge_ms": 50,
    "paste_code_ms": 50, "idle_cpu_pct": 1.0,
}, budgets
assert tolerances == {"launch_overhead_ms": 60, "idle_cpu_pct": 0.5}, tolerances
PY

echo "== bad input"
expect_exit "a missing file is an error" 2 \
    python3 "$SCRIPT" --results "$TMP/nope.json" --baseline "$BASELINE" --budgets "$BUDGETS"
printf 'not json\n' >"$TMP/bad.json"
expect_exit "a file that is not JSON is an error" 2 \
    python3 "$SCRIPT" --results "$TMP/bad.json" --baseline "$BASELINE" --budgets "$BUDGETS"
expect_exit "no arguments is a usage error" 2 python3 "$SCRIPT"

if [[ $failures -ne 0 ]]; then
    echo "$failures perf-check test(s) failed" >&2
    exit 1
fi
echo "all perf-check tests passed"
