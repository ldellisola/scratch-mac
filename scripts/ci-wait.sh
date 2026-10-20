#!/usr/bin/env bash
# Wait for CI jobs to publish their results to the ci-results branch, and print them.
#
#   ci-wait.sh <sha> [job ...]          (default jobs: linux macos)
#
# Polls `git fetch` every CI_WAIT_INTERVAL seconds (default 30) until CI_WAIT_TIMEOUT seconds have passed (default
# 2700). Prints each job's summary.json as soon as it appears. Stops early with a failure as soon as any waited-for
# job reports one, because the verdict cannot change after that.
#
# Exit: 0 every job succeeded
#       1 a job failed
#       2 timed out (re-run the command to keep waiting)
#       64 usage error, 70 internal error
#
# `make ci-wait` always exits 2 for any failure, because that is how make reports a failed recipe. To tell the cases
# apart through make, read the last output line: "ci-wait: PASS", "ci-wait: FAIL" or "ci-wait: TIMEOUT".
#
# Environment: CI_RESULTS_REMOTE (default origin), CI_RESULTS_BRANCH (default ci-results), CI_WAIT_INTERVAL,
# CI_WAIT_TIMEOUT.
set -Eeuo pipefail
trap 'echo "ci-wait.sh: internal error near line $LINENO" >&2; exit 70' ERR

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-ci-results.sh
source "$here/lib-ci-results.sh"

[[ $# -ge 1 ]] || ci_usage_error "usage: ci-wait.sh <sha> [job ...]"
sha=$1
shift
ci_check_sha "$sha"
if [[ $# -eq 0 ]]; then set -- linux macos; fi
for job in "$@"; do ci_check_job "$job"; done

interval="${CI_WAIT_INTERVAL:-30}"
timeout="${CI_WAIT_TIMEOUT:-2700}"
[[ $interval =~ ^[0-9]+$ && $interval -ge 1 ]] || ci_usage_error "CI_WAIT_INTERVAL must be a whole number of seconds, at least 1"
[[ $timeout =~ ^[0-9]+$ ]] || ci_usage_error "CI_WAIT_TIMEOUT must be a whole number of seconds"

# job_status <summary json>: the "status" field, or nothing when the JSON is unreadable.
job_status() {
    printf '%s' "$1" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("status", ""))' 2>/dev/null || true
}

started=$SECONDS
shown=" "
while :; do
    fetch_status=0
    ci_fetch || fetch_status=$?
    if [[ $fetch_status -eq 1 ]]; then
        echo "ci-wait.sh: could not fetch $CI_BRANCH from $CI_REMOTE, will try again" >&2
    fi

    failed=""
    pending=""
    for job in "$@"; do
        summary=""
        if [[ $fetch_status -eq 0 ]]; then
            summary="$(git show "$CI_REF:$sha/$job/summary.json" 2>/dev/null)" || summary=""
        fi
        if [[ -z $summary ]]; then
            pending="$pending $job"
            continue
        fi
        if [[ $shown != *" $job "* ]]; then
            shown="$shown$job "
            echo "=== $job @ $sha"
            printf '%s\n' "$summary"
        fi
        [[ "$(job_status "$summary")" == "success" ]] || failed="$failed $job"
    done

    if [[ -n $failed ]]; then
        echo "ci-wait: FAIL (exit 1): not successful:$failed${pending:+; still pending:$pending}"
        echo "ci-wait: logs and details: scripts/ci-fetch.sh $sha <dest>"
        exit 1
    fi
    if [[ -z $pending ]]; then
        echo "ci-wait: PASS (exit 0): $* succeeded for $sha"
        exit 0
    fi

    elapsed=$((SECONDS - started))
    if [[ $elapsed -ge $timeout ]]; then
        echo "ci-wait: TIMEOUT (exit 2) after ${elapsed}s: still waiting for$pending (sha $sha). Run it again to keep waiting."
        exit 2
    fi
    echo "ci-wait: waiting for$pending (${elapsed}s of ${timeout}s)" >&2
    remaining=$((timeout - elapsed))
    sleep $((interval < remaining ? interval : remaining))
done
