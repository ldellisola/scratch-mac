#!/usr/bin/env bash
# Print the install-and-update text of a release, with its version filled in (spec §9.6, plan 2 task 1).
#
#   release-notes.sh <version>        (.github/workflows/release.yml writes the output to a file for `gh release create`)
#
# docs/release-notes-footer.md is the text. Every `<version>` in it is replaced by <version>, so that the steps name the
# zip the release really has (Scratch-<version>.zip) and not a placeholder.
#
# Exit: 0 printed, 64 usage error (no argument, more than one, or one that is not MAJOR.MINOR.PATCH), 70 cannot run
# (the footer file is missing)
set -euo pipefail

script=$(basename "$0")

usage_error() {
    echo "usage: $script <version>   (MAJOR.MINOR.PATCH, for example 0.2.0)" >&2
    exit 64
}

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ $# -eq 1 && $1 =~ $version_pattern ]] || usage_error
version=$1

footer="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/release-notes-footer.md"
if [[ ! -f $footer ]]; then
    echo "$script: $footer does not exist" >&2
    exit 70
fi

# The version has only digits and dots, so it needs no escaping in the sed replacement, and `.` in it is not special
# there. The pattern is the literal text <version>.
sed "s/<version>/$version/g" "$footer"
