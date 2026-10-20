#!/usr/bin/env bash
# Fail a branch that changes the app without a new version (spec §9.6, plan 1 task 11).
#
#   check-version-bump.sh <base-ref>        (CI passes origin/main)
#
# Every merge to main that changes the app publishes a release named after the VERSION file, and the release workflow
# stops when that version already has a tag. So a change under App/ or Packages/ that keeps the old VERSION would merge
# and then never ship. This check catches it on the branch instead.
#
# It looks at committed state only: VERSION as it is at HEAD, and `git diff --name-only <base-ref>...HEAD`, which is
# what the branch changed since it left <base-ref>. Changes that main gained after that do not count.
#
# Exit: 0 fine: nothing under App/ or Packages/ changed (so also on main itself, where HEAD is <base-ref>), or VERSION
#         differs from <base-ref>:VERSION, or <base-ref> has no VERSION file (which counts as a bump). VERSION is
#         well-formed in every one of these cases.
#       1 a change under App/ or Packages/ with VERSION identical to <base-ref>:VERSION, or VERSION missing or not
#         MAJOR.MINOR.PATCH (digits only, no leading zeros)
#       64 usage error
#       70 cannot run: not a git repository, <base-ref> does not exist, or git failed
set -euo pipefail

script=$(basename "$0")

usage_error() {
    echo "usage: $script <base-ref>" >&2
    exit 64
}

internal_error() {
    echo "$script: $*" >&2
    exit 70
}

[[ $# -eq 1 && -n $1 && $1 != -* ]] || usage_error
base=$1

git rev-parse --git-dir >/dev/null 2>&1 || internal_error "not inside a git repository"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || internal_error "cannot resolve the base ref '$base'"

# VERSION must exist at HEAD and be MAJOR.MINOR.PATCH. $(...) drops the trailing newline, nothing else.
if ! head_version=$(git show "HEAD:VERSION" 2>/dev/null); then
    echo "$script: VERSION is missing at HEAD. It holds the app's version as MAJOR.MINOR.PATCH, for example 0.1.0." >&2
    exit 1
fi
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ $head_version =~ $version_pattern ]]; then
    echo "$script: VERSION must be MAJOR.MINOR.PATCH (digits only, no leading zeros), for example 0.1.1. It is: '$head_version'" >&2
    exit 1
fi

# What the branch changed. NUL-separated, so that unusual file names are not quoted, and without rename detection,
# so that moving a file out of App/ shows the old path too.
if ! changed=$(git diff --name-only --no-renames -z "$base...HEAD" | tr '\0' '\n'); then
    internal_error "git diff $base...HEAD failed"
fi

if ! grep -qE '^(App|Packages)/' <<<"$changed"; then
    echo "$script: nothing under App/ or Packages/ changed since $base, so VERSION ($head_version) needs no bump"
    exit 0
fi

# A base without a VERSION file has never had a release, so any VERSION is new.
if ! base_version=$(git show "$base:VERSION" 2>/dev/null); then
    echo "$script: $base has no VERSION file, so VERSION $head_version counts as a bump"
    exit 0
fi

if [[ $head_version == "$base_version" ]]; then
    {
        echo "$script: App/ or Packages/ changed since $base, but VERSION is still $base_version."
        echo "Bump VERSION in the same pull request (AGENTS.md, section 'Releases'): a patch bump for a fix, a minor bump"
        echo "for a feature. Changed files under App/ and Packages/:"
        grep -E '^(App|Packages)/' <<<"$changed" | sed -n 's/^/  /;1,10p'
    } >&2
    exit 1
fi

echo "$script: VERSION $head_version (was $base_version on $base)"
