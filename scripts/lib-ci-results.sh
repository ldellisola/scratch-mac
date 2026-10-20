# Shared by the ci-results scripts (publish-ci-results.sh, ci-wait.sh, ci-fetch.sh). Source it; do not run it.
#
# Environment:
#   CI_RESULTS_REMOTE  remote name or URL that holds the results branch (default: origin)
#   CI_RESULTS_BRANCH  name of the results branch (default: ci-results)

CI_REMOTE="${CI_RESULTS_REMOTE:-origin}"
CI_BRANCH="${CI_RESULTS_BRANCH:-ci-results}"

# Local ref that mirrors the results branch after ci_fetch. It lives outside refs/heads and refs/remotes, so it never
# touches the user's branches.
CI_REF="refs/ci-results/$CI_BRANCH"

# ci_usage_error <message>: report a mistake in how the script was called (exit 64, distinct from every result code).
ci_usage_error() {
    echo "$(basename "$0"): $*" >&2
    exit 64
}

# ci_check_sha <value>: results folders are named by the full lowercase commit sha.
ci_check_sha() {
    [[ $1 =~ ^[0-9a-f]{7,64}$ ]] || ci_usage_error "'$1' is not a commit sha (lowercase hex, at least 7 characters)"
}

# ci_check_job <value>: a job name becomes a folder name, so keep it to one safe path component.
ci_check_job() {
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || ci_usage_error "'$1' is not a valid job name"
}

# ci_fetch: update $CI_REF from the remote's results branch.
# Returns 0 when fetched, 3 when the remote has no such branch yet (and $CI_REF is removed),
# 1 on any other failure (the git error is printed to stderr).
ci_fetch() {
    local error status=0
    if error=$(git fetch --quiet --no-tags "$CI_REMOTE" "+refs/heads/$CI_BRANCH:$CI_REF" 2>&1); then
        return 0
    fi
    git ls-remote --exit-code --heads "$CI_REMOTE" "$CI_BRANCH" >/dev/null 2>&1 || status=$?
    if [[ $status -eq 2 ]]; then
        git update-ref -d "$CI_REF" 2>/dev/null || true
        return 3
    fi
    echo "$error" >&2
    return 1
}
