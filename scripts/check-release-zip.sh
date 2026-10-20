#!/usr/bin/env bash
# Check a release zip the way a user gets it: unpack it and look at the app inside. macOS only (ditto, codesign, lipo).
#
#   check-release-zip.sh <zip> <version>        (`make release-zip` runs it)
#
# Checks:
#   - the zip holds Scratch.app, and nothing else, at its top level
#   - CFBundleShortVersionString and CFBundleVersion are <version> and CFBundleIdentifier is
#     io.github.ldellisola.Scratch
#   - the executable is arm64 only (spec section 5)
#   - the signature verifies, and it is an ad-hoc one (docs/decisions/0002-ad-hoc-signing.md)
#
# Exit: 0 all fine, 1 a check failed (every failed check is printed), 64 usage error, 70 cannot run.
set -euo pipefail

script=$(basename "$0")

if [[ $# -ne 2 ]]; then
    echo "usage: $script <zip> <version>" >&2
    exit 64
fi
zip=$1
version=$2

if [[ $(uname -s) != Darwin ]]; then
    echo "$script: needs macOS (ditto, codesign and lipo)" >&2
    exit 70
fi
if [[ ! -f $zip ]]; then
    echo "$script: $zip does not exist" >&2
    exit 70
fi

problems=0
problem() {
    echo "$script: $*" >&2
    problems=$((problems + 1))
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ditto -x -k "$zip" "$work"

top=$(find "$work" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ')
if [[ $top != "Scratch.app " ]]; then
    problem "the top level of $zip must be Scratch.app and nothing else, it is: ${top:-empty}"
fi
app="$work/Scratch.app"
if [[ ! -d $app ]]; then
    echo "$script: $problems check(s) failed" >&2
    exit 1
fi

# plist_value <key>: a value of the app's Info.plist, or (missing).
plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist" 2>/dev/null || echo "(missing)"
}

found_version=$(plist_value CFBundleShortVersionString)
found_build=$(plist_value CFBundleVersion)
found_identifier=$(plist_value CFBundleIdentifier)
if [[ $found_version != "$version" ]]; then
    problem "CFBundleShortVersionString is $found_version, VERSION is $version"
fi
if [[ $found_build != "$version" ]]; then
    problem "CFBundleVersion is $found_build, VERSION is $version (CURRENT_PROJECT_VERSION in App/project.yml)"
fi
if [[ $found_identifier != io.github.ldellisola.Scratch ]]; then
    problem "CFBundleIdentifier is $found_identifier, not io.github.ldellisola.Scratch"
fi

archs=$(lipo -archs "$app/Contents/MacOS/Scratch" 2>&1) || true
if [[ $archs != arm64 ]]; then
    problem "the executable has these architectures: $archs (wanted arm64 only)"
fi

if ! verify=$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1); then
    problem "codesign --verify failed: $verify"
fi
signature=$(codesign --display --verbose=4 "$app" 2>&1) || true
if ! grep -Eq 'Signature=adhoc|flags=[^ ]*adhoc' <<<"$signature"; then
    problem "the app is not ad-hoc signed (wanted Signature=adhoc in the codesign output below)"
fi

echo "$script: $(basename "$zip"): version $found_version (build $found_build), $found_identifier, $archs"
echo "$signature" | sed 's/^/  codesign: /'

if [[ $problems -ne 0 ]]; then
    echo "$script: $problems check(s) failed" >&2
    exit 1
fi
echo "$script: ok"
