#!/usr/bin/env bash
# Publish one CI job's results to the orphan ci-results branch.
#
#   publish-ci-results.sh <sha> <job> <dir>
#
# Copies <dir> to <sha>/<job>/ on the results branch (replacing a previous run of the same sha and job) and pushes.
# <dir> must contain summary.json (see ci-summary.py).
#
# - A rejected push (another job published first) is retried up to 5 times: fetch the new tip, put this commit on top
#   of it, push again. Linux and macOS jobs finish at unrelated times, so this is routine.
# - The branch keeps the newest 30 shas. Past that it is recreated as a single orphan commit holding the newest 30
#   (ordered by the finished_at in each summary.json) and pushed with --force-with-lease.
# - Never touches the checked-out branch, index or working tree: the commit is built in a temporary directory with a
#   private index.
#
# Environment: CI_RESULTS_REMOTE (default origin), CI_RESULTS_BRANCH (default ci-results).
# Exit: 0 published, 1 could not publish, 64 usage error.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-ci-results.sh
source "$here/lib-ci-results.sh"

MAX_SHA_FOLDERS=30
MAX_RETRIES=5

[[ $# -eq 3 ]] || ci_usage_error "usage: publish-ci-results.sh <sha> <job> <dir>"
sha=$1
job=$2
ci_check_sha "$sha"
ci_check_job "$job"
[[ -d $3 ]] || ci_usage_error "'$3' is not a directory"
[[ -f $3/summary.json ]] || ci_usage_error "'$3' has no summary.json (write it with ci-summary.py first)"
source_dir="$(cd "$3" && pwd)"

# The scripts also run on CI machines where nobody has configured a git identity.
if ! git config user.name >/dev/null 2>&1; then
    export GIT_AUTHOR_NAME="github-actions[bot]" GIT_COMMITTER_NAME="github-actions[bot]"
fi
if ! git config user.email >/dev/null 2>&1; then
    export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
    export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
fi

git_dir="$(git rev-parse --absolute-git-dir)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/stage"
index="$work/index"
mkdir -p "$stage/$sha/$job"
cp -R "$source_dir/." "$stage/$sha/$job/"

# sgit <git args>: git against the stage directory as a work tree, with a private index, sharing this repository's
# object store. Only index and tree plumbing goes through it. Fetch and push run from the caller's directory so that
# a relative CI_RESULTS_REMOTE keeps working.
sgit() {
    (cd "$stage" && GIT_DIR="$git_dir" GIT_WORK_TREE="$stage" GIT_INDEX_FILE="$index" git "$@")
}

# sha_folders_to_drop: prints the sha folders to remove from the index, oldest first. The folder being published is
# always kept. Ordered by the newest finished_at among a folder's jobs; a folder without one counts as oldest.
sha_folders_to_drop() {
    (
        cd "$stage"
        export GIT_DIR="$git_dir" GIT_WORK_TREE="$stage" GIT_INDEX_FILE="$index"
        python3 - "$MAX_SHA_FOLDERS" "$sha" <<'PY'
import json
import subprocess
import sys

limit, current = int(sys.argv[1]), sys.argv[2]


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


newest = {}
for path in git("ls-files", "-z").split("\0"):
    folder, _, rest = path.partition("/")
    if not rest:
        continue
    newest.setdefault(folder, "")
    if rest.count("/") == 1 and rest.endswith("/summary.json"):
        try:
            stamp = str(json.loads(git("show", ":" + path)).get("finished_at") or "")
        except (ValueError, AttributeError):
            stamp = ""
        newest[folder] = max(newest[folder], stamp)

others = sorted((f for f in newest if f != current), key=lambda f: (newest[f], f), reverse=True)
for folder in reversed(others[max(limit - 1, 0):]):
    print(folder)
PY
    )
}

# publish_once: one fetch, commit and push attempt. Returns non-zero when it should be retried.
# Written with explicit returns because `set -e` is off inside a function called from `if`.
publish_once() {
    local fetch_status=0 parent="" drop folder tree commit message orphan=0
    ci_fetch || fetch_status=$?
    rm -f "$index"
    case $fetch_status in
        0)
            parent="$(git rev-parse --verify --quiet "$CI_REF^{commit}")" || return 1
            sgit read-tree "$parent" || return 1
            ;;
        3) ;; # no results branch yet: this commit becomes its root
        *) return 1 ;;
    esac

    sgit rm -r -q -f --cached --ignore-unmatch -- "$sha/$job" || return 1
    sgit add -f -A -- "$sha/$job" || return 1

    drop="$(sha_folders_to_drop)" || return 1
    if [[ -n $drop ]]; then
        while IFS= read -r folder; do
            sgit rm -r -q -f --cached --ignore-unmatch -- "$folder" || return 1
        done <<<"$drop"
        orphan=1
    fi

    tree="$(sgit write-tree)" || return 1
    message="ci-results: ${sha:0:12} $job"
    if [[ $orphan -eq 1 || -z $parent ]]; then
        commit="$(sgit commit-tree "$tree" -m "$message")" || return 1
    else
        commit="$(sgit commit-tree "$tree" -p "$parent" -m "$message")" || return 1
    fi

    if [[ $orphan -eq 1 ]]; then
        echo "publish-ci-results.sh: more than $MAX_SHA_FOLDERS shas, recreating $CI_BRANCH with the newest $MAX_SHA_FOLDERS" >&2
        git push --quiet --force-with-lease="refs/heads/$CI_BRANCH:$parent" "$CI_REMOTE" "$commit:refs/heads/$CI_BRANCH" || return 1
    else
        git push --quiet "$CI_REMOTE" "$commit:refs/heads/$CI_BRANCH" || return 1
    fi
}

attempt=0
until publish_once; do
    if [[ $attempt -ge $MAX_RETRIES ]]; then
        echo "publish-ci-results.sh: could not publish $sha/$job to $CI_REMOTE $CI_BRANCH after $((attempt + 1)) attempts" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    echo "publish-ci-results.sh: push failed or was rejected, fetching and retrying ($attempt of $MAX_RETRIES)" >&2
    sleep "0.$((RANDOM % 8 + 2))"
done
echo "published $sha/$job to $CI_REMOTE $CI_BRANCH"
