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
#   - the app carries the highlight queries of ScratchCode (its resource bundle, docs/decisions/0007-tree-sitter.md)
#   - the app carries Contents/Resources/Acknowledgements.rtf, the licences of tree-sitter and its grammars that the
#     About panel shows (scripts/make-acknowledgements.py, docs/decisions/0007-tree-sitter.md)
#
# It also prints the sizes of the zip, the app and its executable, which docs/decisions/0007-tree-sitter.md compares.
#
# Exit: 0 all fine, 1 a check failed (every failed check is printed), 64 usage error, 70 cannot run.
#
# scripts/tests/test-release-zip.sh runs this against stubs of the macOS tools. PLISTBUDDY names the PlistBuddy to use
# (for those tests); it is /usr/libexec/PlistBuddy otherwise.
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

plistbuddy=${PLISTBUDDY:-/usr/libexec/PlistBuddy}

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
    "$plistbuddy" -c "Print :$1" "$app/Contents/Info.plist" 2>/dev/null || echo "(missing)"
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

# ScratchCode's queries are a resource bundle that Xcode puts into Contents/Resources. Without it the first highlight
# of a code block would stop the app, so a zip that lacks it must not be released.
queries=$(find "$app/Contents/Resources" -type f -path '*Queries/swift/highlights.scm' 2>/dev/null || true)
if [[ -z $queries ]]; then
    problem "no Queries/swift/highlights.scm under Contents/Resources: ScratchCode's resource bundle is not in the app"
fi

# The About panel shows the licences of tree-sitter and its grammars from this file (AboutCredits). A release without it
# would ship their code with no notice of their licences, so a zip that lacks it, or has one that is empty or does not
# name tree-sitter, must not be released.
acknowledgements="$app/Contents/Resources/Acknowledgements.rtf"
if [[ ! -f $acknowledgements ]]; then
    problem "no Contents/Resources/Acknowledgements.rtf in the app: the licences of tree-sitter and its grammars are missing"
elif [[ ! -s $acknowledgements ]]; then
    problem "Contents/Resources/Acknowledgements.rtf is empty"
elif ! grep -q 'tree-sitter' "$acknowledgements"; then
    problem "Contents/Resources/Acknowledgements.rtf does not name tree-sitter"
fi

zip_bytes=$(wc -c <"$zip" | tr -d ' ')
app_kilobytes=$(du -sk "$app" | cut -f1)
executable_bytes=$(wc -c <"$app/Contents/MacOS/Scratch" | tr -d ' ')

echo "$script: $(basename "$zip"): version $found_version (build $found_build), $found_identifier, $archs"
echo "$script: sizes: zip $zip_bytes bytes, Scratch.app $app_kilobytes KB, executable $executable_bytes bytes"
echo "$signature" | sed 's/^/  codesign: /'

if [[ $problems -ne 0 ]]; then
    echo "$script: $problems check(s) failed" >&2
    exit 1
fi
echo "$script: ok"
