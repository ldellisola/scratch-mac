#!/usr/bin/env bash
# Extract one commit's published CI results from the ci-results branch.
#
#   ci-fetch.sh <sha> <dest>
#
# Fetches the branch, then writes the contents of <sha>/ into <dest> (created if needed), so that
# <dest>/linux/summary.json, <dest>/macos/screenshots/*.png and so on exist. Lists the files it wrote.
#
# Environment: CI_RESULTS_REMOTE (default origin), CI_RESULTS_BRANCH (default ci-results).
# Exit: 0 extracted, 1 nothing published for that sha (or the fetch failed), 64 usage error.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-ci-results.sh
source "$here/lib-ci-results.sh"

[[ $# -eq 2 ]] || ci_usage_error "usage: ci-fetch.sh <sha> <dest>"
sha=$1
dest=$2
ci_check_sha "$sha"

fetch_status=0
ci_fetch || fetch_status=$?
case $fetch_status in
    0) ;;
    3)
        echo "ci-fetch.sh: $CI_REMOTE has no $CI_BRANCH branch yet" >&2
        exit 1
        ;;
    *) exit 1 ;;
esac

if ! git cat-file -e "$CI_REF:$sha" 2>/dev/null; then
    echo "ci-fetch.sh: no results for $sha on $CI_BRANCH (CI has not published them, or they were pruned)" >&2
    exit 1
fi

mkdir -p "$dest"
git archive --format=tar "$CI_REF" "$sha" | tar -x -C "$dest" --strip-components=1
echo "fetched $sha from $CI_REMOTE $CI_BRANCH into $dest:"
(cd "$dest" && find . -type f | sort | sed 's|^\./|  |')
