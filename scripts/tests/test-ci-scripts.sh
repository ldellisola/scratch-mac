#!/usr/bin/env bash
# Tests for the ci-results scripts (ci-summary.py, publish-ci-results.sh, ci-wait.sh, ci-fetch.sh).
#
# Everything runs against throwaway local repositories in a temporary directory: no network, and none of this
# repository's refs are touched. Run with `make script-test`. Takes about 30 seconds, mostly deliberate waiting
# for the timeout checks and the 33 publishes of the pruning check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$ROOT/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolated git configuration. No identity is configured on purpose: the publisher must cope without one, as it
# has to in the CI container.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
printf '[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL
unset CI_RESULTS_REMOTE CI_RESULTS_BRANCH CI_WAIT_INTERVAL CI_WAIT_TIMEOUT

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
}

# check <description> <command...>: passes when the command exits 0.
check() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
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

# output_has <description> <fixed text>: the last expect_exit output contains the text.
output_has() {
    if grep -qF -- "$2" "$TMP/out.txt"; then pass "$1"; else
        fail "$1 (missing: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

fake_sha() { printf '%040x' "$1"; }
new_remote() { git init --bare -q "$1"; }
new_work() {
    mkdir -p "$1"
    git -C "$1" init -q
}

# summary <dir> <job> <sha> <name=outcome>...
summary() {
    local dir=$1 job=$2 sha=$3
    shift 3
    python3 "$SCRIPTS/ci-summary.py" --job "$job" --sha "$sha" --run-url "https://example.invalid/runs/1" \
        --out "$dir" --step "$@" >/dev/null
}

# run_in <dir> <command...>: run the command from inside a work repository, as the scripts expect.
run_in() {
    local dir=$1
    shift
    (cd "$dir" && "$@")
}

remote_folders() { git -C "$1" ls-tree --name-only "${2:-ci-results}"; }

echo "== prerequisites"
for script in ci-summary.py publish-ci-results.sh ci-wait.sh ci-fetch.sh; do
    if [[ -f "$SCRIPTS/$script" ]]; then pass "scripts/$script exists"; else fail "scripts/$script exists"; fi
done
if [[ $failures -ne 0 ]]; then
    echo "$failures ci script test(s) failed" >&2
    exit 1
fi

# ---------------------------------------------------------------------------------------------------------------------
echo "== ci-summary.py"
SHA=$(fake_sha 100)

summary "$TMP/s-ok" linux "$SHA" lint=success "make test=success" optional=skipped
python3 - "$TMP/s-ok/summary.json" "$SHA" <<'PY' && pass "summary.json has the documented shape" || fail "summary.json has the documented shape"
import json, sys
from datetime import datetime
d = json.load(open(sys.argv[1]))
assert list(d) == ["sha", "job", "status", "steps", "run_url", "finished_at"], list(d)
assert d["sha"] == sys.argv[2] and d["job"] == "linux" and d["status"] == "success"
assert d["steps"] == [
    {"name": "lint", "outcome": "success"},
    {"name": "make test", "outcome": "success"},
    {"name": "optional", "outcome": "skipped"},
], d["steps"]
assert d["run_url"] == "https://example.invalid/runs/1"
assert d["finished_at"].endswith("Z")
datetime.fromisoformat(d["finished_at"].replace("Z", "+00:00"))
PY

status_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$1/summary.json"; }

summary "$TMP/s-fail" macos "$SHA" build=failure test=skipped
[[ "$(status_of "$TMP/s-fail")" == "failure" ]] && pass "a failed step makes the job fail" || fail "a failed step makes the job fail"

summary "$TMP/s-cancel" macos "$SHA" build=success test=cancelled
[[ "$(status_of "$TMP/s-cancel")" == "failure" ]] && pass "a cancelled step makes the job fail" || fail "a cancelled step makes the job fail"

summary "$TMP/s-empty" macos "$SHA" build=success test=
[[ "$(status_of "$TMP/s-empty")" == "failure" ]] && pass "an empty outcome counts as a failure" || fail "an empty outcome counts as a failure"

python3 "$SCRIPTS/ci-summary.py" --job linux --sha "$SHA" --run-url u --out "$TMP/s-repeat" \
    --step a=success --step b=skipped >/dev/null
[[ "$(status_of "$TMP/s-repeat")" == "success" ]] && pass "--step can be repeated" || fail "--step can be repeated"

expect_exit "ci-summary.py requires at least one --step" 2 \
    python3 "$SCRIPTS/ci-summary.py" --job linux --sha "$SHA" --run-url u --out "$TMP/s-none"
expect_exit "ci-summary.py rejects a step without an outcome" 2 \
    python3 "$SCRIPTS/ci-summary.py" --job linux --sha "$SHA" --run-url u --out "$TMP/s-bad" --step lint

# ---------------------------------------------------------------------------------------------------------------------
echo "== publish, wait and fetch"
REMOTE="$TMP/remote.git"
WORK="$TMP/work"
new_remote "$REMOTE"
new_work "$WORK"
export CI_RESULTS_REMOTE="$REMOTE"

mkdir -p "$TMP/out-linux" "$TMP/out-macos"
summary "$TMP/out-linux" linux "$SHA" lint=success test=success
printf 'last lines of the test log\n' >"$TMP/out-linux/test.log"
printf 'stale\n' >"$TMP/out-linux/stale.log"
summary "$TMP/out-macos" macos "$SHA" build=failure

expect_exit "publish linux" 0 run_in "$WORK" "$SCRIPTS/publish-ci-results.sh" "$SHA" linux "$TMP/out-linux"
expect_exit "publish macos" 0 run_in "$WORK" "$SCRIPTS/publish-ci-results.sh" "$SHA" macos "$TMP/out-macos"
check "results land under <sha>/<job>/ on ci-results" \
    git -C "$REMOTE" cat-file -e "ci-results:$SHA/linux/test.log"
check "the first commit on ci-results is an orphan" \
    test "$(git -C "$REMOTE" rev-list --max-parents=0 ci-results | wc -l)" -eq 1
check "publishing leaves the working copy empty" test -z "$(ls -A "$WORK" | grep -v '^\.git$' || true)"
check "publishing leaves the checked-out branch alone" test -z "$(git -C "$WORK" for-each-ref refs/heads)"

export CI_WAIT_INTERVAL=1 CI_WAIT_TIMEOUT=5

expect_exit "ci-wait: linux succeeded" 0 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$SHA" linux
output_has "ci-wait prints the summary" '"status": "success"'
expect_exit "ci-wait: macos failed" 1 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$SHA" macos
expect_exit "ci-wait: linux succeeded but macos failed" 1 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$SHA" linux macos
output_has "ci-wait prints every summary it has" '"status": "failure"'
expect_exit "ci-wait: default jobs are linux and macos" 1 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$SHA"

started=$SECONDS
expect_exit "ci-wait: an unknown sha times out" 2 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$(fake_sha 101)" linux
elapsed=$((SECONDS - started))
if [[ $elapsed -ge 4 && $elapsed -le 20 ]]; then pass "ci-wait waited for the timeout (${elapsed}s)"; else
    fail "ci-wait waited for the timeout (${elapsed}s)"
fi
expect_exit "ci-wait: a job that has not reported times out" 2 \
    run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$SHA" linux windows
output_has "the timeout names the job it was waiting for" "windows"
expect_exit "ci-wait: no arguments is a usage error" 64 run_in "$WORK" "$SCRIPTS/ci-wait.sh"
expect_exit "ci-wait: a bad sha is a usage error" 64 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "not-a-sha" linux

expect_exit "ci-fetch extracts a sha folder" 0 run_in "$WORK" "$SCRIPTS/ci-fetch.sh" "$SHA" "$TMP/fetched"
check "ci-fetch: <dest>/linux/summary.json exists" test -f "$TMP/fetched/linux/summary.json"
check "ci-fetch: <dest>/linux/test.log exists" test -f "$TMP/fetched/linux/test.log"
check "ci-fetch: <dest>/macos/summary.json exists" test -f "$TMP/fetched/macos/summary.json"
expect_exit "ci-fetch: an unknown sha fails" 1 run_in "$WORK" "$SCRIPTS/ci-fetch.sh" "$(fake_sha 101)" "$TMP/nothing"
expect_exit "ci-fetch: no arguments is a usage error" 64 run_in "$WORK" "$SCRIPTS/ci-fetch.sh"

# Publishing the same sha and job again (a re-run) replaces the folder instead of merging into it.
rm "$TMP/out-linux/stale.log"
summary "$TMP/out-linux" linux "$SHA" lint=success test=failure
expect_exit "re-publish replaces the folder" 0 run_in "$WORK" "$SCRIPTS/publish-ci-results.sh" "$SHA" linux "$TMP/out-linux"
expect_exit "ci-wait sees the re-run" 1 run_in "$WORK" "$SCRIPTS/ci-wait.sh" "$SHA" linux
git -C "$REMOTE" cat-file -e "ci-results:$SHA/linux/stale.log" 2>/dev/null &&
    fail "re-publish removes files that are no longer produced" || pass "re-publish removes files that are no longer produced"

expect_exit "publish rejects a directory without summary.json" 64 \
    run_in "$WORK" "$SCRIPTS/publish-ci-results.sh" "$SHA" linux "$TMP"
expect_exit "publish rejects a bad job name" 64 \
    run_in "$WORK" "$SCRIPTS/publish-ci-results.sh" "$SHA" "../x" "$TMP/out-linux"

# CI_RESULTS_BRANCH moves everything to another branch.
expect_exit "publish to another branch" 0 \
    run_in "$WORK" env CI_RESULTS_BRANCH=other "$SCRIPTS/publish-ci-results.sh" "$SHA" macos "$TMP/out-macos"
check "the other branch exists on the remote" git -C "$REMOTE" cat-file -e "other:$SHA/macos/summary.json"
expect_exit "ci-wait follows CI_RESULTS_BRANCH" 1 \
    run_in "$WORK" env CI_RESULTS_BRANCH=other "$SCRIPTS/ci-wait.sh" "$SHA" macos

unset CI_WAIT_INTERVAL CI_WAIT_TIMEOUT

# ---------------------------------------------------------------------------------------------------------------------
echo "== a remote that has no ci-results branch yet"
EMPTY_REMOTE="$TMP/empty.git"
new_remote "$EMPTY_REMOTE"
expect_exit "ci-wait times out quietly on a missing branch" 2 \
    run_in "$WORK" env CI_RESULTS_REMOTE="$EMPTY_REMOTE" CI_WAIT_INTERVAL=1 CI_WAIT_TIMEOUT=2 "$SCRIPTS/ci-wait.sh" "$SHA" linux
expect_exit "ci-wait reports an unreachable remote as a timeout, with the error" 2 \
    run_in "$WORK" env CI_RESULTS_REMOTE="$TMP/does-not-exist.git" CI_WAIT_INTERVAL=1 CI_WAIT_TIMEOUT=1 "$SCRIPTS/ci-wait.sh" "$SHA" linux
output_has "the fetch error is shown" "does-not-exist.git"

# ---------------------------------------------------------------------------------------------------------------------
echo "== rejected pushes are retried"
install_hook() { # install_hook <bare repo> <hook body>
    printf '#!/bin/sh\n%s\n' "$2" >"$1/hooks/pre-receive"
    chmod +x "$1/hooks/pre-receive"
}

RETRY_REMOTE="$TMP/retry.git"
new_remote "$RETRY_REMOTE"
install_hook "$RETRY_REMOTE" "if [ -f '$RETRY_REMOTE/reject-once' ]; then rm '$RETRY_REMOTE/reject-once'; echo 'rejected by test hook' >&2; exit 1; fi"
touch "$RETRY_REMOTE/reject-once"
expect_exit "publish succeeds after one rejected push" 0 \
    run_in "$WORK" env CI_RESULTS_REMOTE="$RETRY_REMOTE" "$SCRIPTS/publish-ci-results.sh" "$SHA" linux "$TMP/out-linux"
check "the rejecting hook ran" test ! -e "$RETRY_REMOTE/reject-once"
check "the retried push landed" git -C "$RETRY_REMOTE" cat-file -e "ci-results:$SHA/linux/summary.json"

NEVER_REMOTE="$TMP/never.git"
new_remote "$NEVER_REMOTE"
install_hook "$NEVER_REMOTE" "echo 'rejected by test hook' >&2; exit 1"
expect_exit "publish gives up after repeated rejections" 1 \
    run_in "$WORK" env CI_RESULTS_REMOTE="$NEVER_REMOTE" "$SCRIPTS/publish-ci-results.sh" "$SHA" linux "$TMP/out-linux"
output_has "the failure says why" "rejected by test hook"

echo "== concurrent publishers"
RACE_REMOTE="$TMP/race.git"
new_remote "$RACE_REMOTE"
pids=()
for n in 1 2 3 4; do
    new_work "$TMP/race-work-$n"
    summary "$TMP/race-out-$n" "job$n" "$SHA" step=success
    (run_in "$TMP/race-work-$n" env CI_RESULTS_REMOTE="$RACE_REMOTE" \
        "$SCRIPTS/publish-ci-results.sh" "$SHA" "job$n" "$TMP/race-out-$n" >"$TMP/race-$n.log" 2>&1) &
    pids+=($!)
done
race_failed=0
for pid in "${pids[@]}"; do wait "$pid" || race_failed=$((race_failed + 1)); done
[[ $race_failed -eq 0 ]] && pass "four simultaneous publishes all succeed" || {
    fail "four simultaneous publishes all succeed ($race_failed failed)"
    cat "$TMP"/race-?.log >&2
}
for n in 1 2 3 4; do
    check "simultaneous publish job$n landed" git -C "$RACE_REMOTE" cat-file -e "ci-results:$SHA/job$n/summary.json"
done

# ---------------------------------------------------------------------------------------------------------------------
echo "== pruning to the newest 30 shas"
PRUNE_REMOTE="$TMP/prune.git"
new_remote "$PRUNE_REMOTE"
export CI_RESULTS_REMOTE="$PRUNE_REMOTE"
publish_fake() { # publish_fake <n>
    local sha
    sha=$(fake_sha "$1")
    summary "$TMP/prune-out-$1" linux "$sha" step=success
    run_in "$WORK" "$SCRIPTS/publish-ci-results.sh" "$sha" linux "$TMP/prune-out-$1" >"$TMP/prune-publish.log" 2>&1 ||
        { cat "$TMP/prune-publish.log" >&2; return 1; }
}
prune_ok=1
for n in $(seq 1 30); do publish_fake "$n" || prune_ok=0; done
[[ $prune_ok -eq 1 ]] && pass "30 publishes succeed" || fail "30 publishes succeed"
[[ "$(remote_folders "$PRUNE_REMOTE" | wc -l)" -eq 30 ]] && pass "30 shas: nothing pruned yet" || fail "30 shas: nothing pruned yet"
[[ "$(git -C "$PRUNE_REMOTE" rev-list --count ci-results)" -eq 30 ]] && pass "30 shas: history is one commit per publish" ||
    fail "30 shas: history is one commit per publish"

publish_fake 31 && pass "the 31st publish succeeds" || fail "the 31st publish succeeds"
[[ "$(remote_folders "$PRUNE_REMOTE" | wc -l)" -eq 30 ]] && pass "31 shas: only 30 folders remain" || fail "31 shas: only 30 folders remain"
check "31 shas: the oldest sha was dropped" test -z "$(remote_folders "$PRUNE_REMOTE" | grep -x "$(fake_sha 1)" || true)"
check "31 shas: the newest sha is kept" git -C "$PRUNE_REMOTE" cat-file -e "ci-results:$(fake_sha 31)/linux/summary.json"
[[ "$(git -C "$PRUNE_REMOTE" rev-list --count ci-results)" -eq 1 ]] && pass "31 shas: the branch is recreated as one orphan commit" ||
    fail "31 shas: the branch is recreated as one orphan commit"

# The order survives the recreation: the next sha pushes out sha 2, not an arbitrary folder.
publish_fake 32 && publish_fake 33 && pass "two more publishes succeed" || fail "two more publishes succeed"
folders="$(remote_folders "$PRUNE_REMOTE")"
[[ "$(wc -l <<<"$folders")" -eq 30 ]] && pass "33 shas: still 30 folders" || fail "33 shas: still 30 folders"
expected="$(for n in $(seq 4 33); do fake_sha "$n"; echo; done | sort)"
if [[ "$folders" == "$expected" ]]; then pass "33 shas: exactly the newest 30 remain"; else
    fail "33 shas: exactly the newest 30 remain"
    diff <(echo "$expected") <(echo "$folders") >&2 || true
fi

# ---------------------------------------------------------------------------------------------------------------------
echo "== name-screenshots.py"
SHOTS="$TMP/shots"
mkdir -p "$SHOTS/exported"
for id in AAAA BBBB CCCC DDDD EEEE; do printf 'png-%s' "$id" >"$SHOTS/exported/$id.png"; done
UUID_A=11111111-2222-3333-4444-555555555555
# A manifest as xcresulttool writes it. typical-light and typical-dark are named by their attachment, empty-light only
# by its test, huge-note-light has an unrelated extra attachment first, and EEEE belongs to no expected name.
cat >"$SHOTS/exported/manifest.json" <<JSON
[
  {"testIdentifier": "ScreenshotTests/testTypicalLight()",
   "attachments": [{"exportedFileName": "AAAA.png", "isAssociatedWithFailure": false,
                    "suggestedHumanReadableName": "typical-light_0_$UUID_A.png"}]},
  {"testIdentifier": "ScreenshotTests/testTypicalDark()",
   "attachments": [{"exportedFileName": "BBBB.png", "suggestedHumanReadableName": "typical-dark_1_$UUID_A.png"}]},
  {"testIdentifier": "ScreenshotTests/testEmptyLight()",
   "attachments": [{"exportedFileName": "CCCC.png", "suggestedHumanReadableName": "Screenshot_$UUID_A.png"}]},
  {"testIdentifier": "ScreenshotTests/testHugeNoteLight()",
   "attachments": [{"exportedFileName": "EEEE.png", "suggestedHumanReadableName": "Screen Recording.png"},
                   {"exportedFileName": "DDDD.png", "suggestedHumanReadableName": "huge-note-light.png"}]}
]
JSON
NAMES=(typical-light typical-dark empty-light huge-note-light)
expect_exit "name-screenshots names every expected screenshot" 0 \
    python3 "$SCRIPTS/name-screenshots.py" "$SHOTS/exported" "$SHOTS/named" "${NAMES[@]}"
check "typical-light.png is its own attachment" grep -qx png-AAAA "$SHOTS/named/typical-light.png"
check "typical-dark.png is its own attachment" grep -qx png-BBBB "$SHOTS/named/typical-dark.png"
check "empty-light.png is found by its test name" grep -qx png-CCCC "$SHOTS/named/empty-light.png"
check "huge-note-light.png is the attachment with the name" grep -qx png-DDDD "$SHOTS/named/huge-note-light.png"
[[ "$(find "$SHOTS/named" -type f | wc -l)" -eq 4 ]] && pass "name-screenshots writes only the expected files" ||
    fail "name-screenshots writes only the expected files"

expect_exit "name-screenshots fails when a screenshot is missing" 1 \
    python3 "$SCRIPTS/name-screenshots.py" "$SHOTS/exported" "$SHOTS/named2" typical-light many-notes-light
output_has "name-screenshots names the missing screenshot" "many-notes-light"
output_has "name-screenshots prints the manifest to help" "ScreenshotTests/testTypicalLight()"

mkdir -p "$SHOTS/no-manifest"
expect_exit "name-screenshots fails without a manifest" 1 \
    python3 "$SCRIPTS/name-screenshots.py" "$SHOTS/no-manifest" "$SHOTS/named3" typical-light
expect_exit "name-screenshots needs at least one name" 64 python3 "$SCRIPTS/name-screenshots.py" "$SHOTS/exported" "$SHOTS/named4"

# ---------------------------------------------------------------------------------------------------------------------
if [[ $failures -ne 0 ]]; then
    echo "$failures ci script test(s) failed" >&2
    exit 1
fi
echo "all ci script tests passed"
