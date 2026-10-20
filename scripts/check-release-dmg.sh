#!/usr/bin/env bash
# Check a release disk image the way a user gets it: attach it read-only and look at what the window shows and at the
# app inside. macOS only (hdiutil, codesign, lipo).
#
#   check-release-dmg.sh <dmg> <version>        (`make release-dmg` runs it)
#
# Checks:
#   - the image attaches, read-only
#   - the volume holds Scratch.app and an Applications symlink to /Applications, and nothing else that is visible
#   - CFBundleShortVersionString and CFBundleVersion are <version> and CFBundleIdentifier is
#     io.github.ldellisola.Scratch
#   - the executable is arm64 only (spec section 5)
#   - the signature verifies (`codesign --verify --deep --strict`), and it is an ad-hoc one (docs/decisions/0002)
#
# The image is attached with -nobrowse at a mount point in a temporary folder, so that it never shows up in the Finder or
# collides with a volume of the same name, and it is always detached again, also when a check fails (an EXIT trap).
# These are the checks of check-release-zip.sh, made on what the DMG holds.
#
# Exit: 0 all fine, 1 a check failed (every failed check is printed), 64 usage error, 70 cannot run.
#
# scripts/tests/test-release-dmg.sh runs this against stubs of the macOS tools. PLISTBUDDY names the PlistBuddy to use
# (for those tests); it is /usr/libexec/PlistBuddy otherwise.
set -euo pipefail

script=$(basename "$0")

if [[ $# -ne 2 ]]; then
    echo "usage: $script <dmg> <version>" >&2
    exit 64
fi
dmg=$1
version=$2

if [[ $(uname -s) != Darwin ]]; then
    echo "$script: needs macOS (hdiutil, codesign and lipo)" >&2
    exit 70
fi
if [[ ! -f $dmg ]]; then
    echo "$script: $dmg does not exist" >&2
    exit 70
fi

plistbuddy=${PLISTBUDDY:-/usr/libexec/PlistBuddy}

problems=0
problem() {
    echo "$script: $*" >&2
    problems=$((problems + 1))
}

work=$(mktemp -d)
mount_point="$work/volume"
mkdir "$mount_point"
attached=false

# Detaches the volume: a few plain tries first, because a detach right after reading from the volume can find it busy,
# then -force.
detach() {
    local attempt
    for attempt in 1 2 3; do
        if hdiutil detach "$mount_point" -quiet 2>/dev/null; then return 0; fi
        sleep 1
    done
    hdiutil detach "$mount_point" -force -quiet
}

# Runs when the script ends, however it ends. The temporary folder is removed only when the volume is no longer
# mounted in it, and the exit status stays the one the script had.
cleanup() {
    local status=$?
    set +e
    if [[ $attached == true ]]; then
        if detach; then
            attached=false
        else
            echo "$script: cannot detach $mount_point: eject it by hand" >&2
        fi
    fi
    if [[ $attached == false ]]; then rm -rf "$work"; fi
    exit "$status"
}
trap cleanup EXIT

if ! attach_output=$(hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$dmg" 2>&1); then
    problem "cannot attach $dmg: $attach_output"
    echo "$script: $problems check(s) failed" >&2
    exit 1
fi
attached=true

# What the window shows: the app and the Applications link. Names that start with a dot are the system's (.fseventsd,
# .DS_Store) and nobody sees them.
top=$(find "$mount_point" -mindepth 1 -maxdepth 1 ! -name '.*' -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ')
if [[ $top != "Applications Scratch.app " ]]; then
    problem "the volume must hold Applications and Scratch.app and nothing else, it holds: ${top:-nothing}"
fi
if [[ -L $mount_point/Applications ]]; then
    link_target=$(readlink "$mount_point/Applications")
    if [[ $link_target != /Applications ]]; then
        problem "Applications points to $link_target, not /Applications"
    fi
else
    problem "Applications is not a symlink to /Applications (the drag target of the window is missing)"
fi

app="$mount_point/Scratch.app"
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

echo "$script: $(basename "$dmg"): version $found_version (build $found_build), $found_identifier, $archs"
echo "$signature" | sed 's/^/  codesign: /'

if [[ $problems -ne 0 ]]; then
    echo "$script: $problems check(s) failed" >&2
    exit 1
fi
echo "$script: ok"
