#!/usr/bin/env bash
# Tests for scripts/check-release-dmg.sh: the check of a release disk image (docs/decisions/0005). The script needs
# macOS (hdiutil, codesign, lipo), so these tests run it against stubs of those tools, which stand in for the Mac: they
# prove the script's decisions (what it checks, what it reports, that it always detaches), not what hdiutil does. The
# real tools run in CI, in `make release-dmg`. Run with `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-release-dmg.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
}

# expect_exit <description> <code> <command...>: runs the command, leaves stdout in $TMP/out.txt and stderr in
# $TMP/err.txt.
expect_exit() {
    local desc=$1 want=$2 got=0
    shift 2
    "$@" >"$TMP/out.txt" 2>"$TMP/err.txt" || got=$?
    if [[ $got -eq $want ]]; then
        pass "$desc"
    else
        fail "$desc (exit $got, wanted $want)"
        sed 's/^/     | /' "$TMP/out.txt" "$TMP/err.txt" >&2
    fi
}

# err_has <description> <fixed text>: look at the last stderr. log_has / log_lacks: look at what the stub hdiutil saw.
err_has() {
    if grep -qF -- "$2" "$TMP/err.txt"; then pass "$1"; else
        fail "$1 (missing on stderr: $2)"
        sed 's/^/     | /' "$TMP/err.txt" >&2
    fi
}
log_has() {
    if grep -qE -- "$2" "$TMP/hdiutil.log"; then pass "$1"; else
        fail "$1 (missing in the hdiutil log: $2)"
        sed 's/^/     | /' "$TMP/hdiutil.log" >&2
    fi
}
log_lacks() {
    if grep -qE -- "$2" "$TMP/hdiutil.log"; then
        fail "$1 (found in the hdiutil log: $2)"
        sed 's/^/     | /' "$TMP/hdiutil.log" >&2
    else pass "$1"; fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/check-release-dmg.sh exists"; else
    fail "scripts/check-release-dmg.sh exists"
    echo "$failures release-dmg test(s) failed" >&2
    exit 1
fi

# --- the stubs --------------------------------------------------------------------------------------------------------
# Each stub is a small script in $TMP/bin, put first in PATH. They answer from environment variables, so a test changes
# one thing at a time. The stub hdiutil "mounts" the image by copying $STUB_VOLUME into the -mountpoint folder.
mkdir -p "$TMP/bin"

cat >"$TMP/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo "${STUB_UNAME:-Darwin}"
EOF

cat >"$TMP/bin/hdiutil" <<'EOF'
#!/usr/bin/env bash
# attach: copy the fake volume into the mount point. detach: note it and unmount (empty the folder).
verb=$1
shift
mount_point=
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case ${args[$i]} in
        -mountpoint) mount_point=${args[$((i + 1))]} ;;
    esac
done
case $verb in
    attach)
        echo "attach $* " >>"$STUB_LOG"
        if [[ -n ${STUB_ATTACH_FAIL:-} ]]; then
            echo "hdiutil: attach failed - image not recognized" >&2
            exit 1
        fi
        cp -a "$STUB_VOLUME/." "$mount_point/"
        echo "/dev/disk9	Apple_HFS	$mount_point"
        ;;
    detach)
        echo "detach $1" >>"$STUB_LOG"
        find "$1" -mindepth 1 -delete
        ;;
    *)
        echo "hdiutil stub: unexpected $verb" >&2
        exit 2
        ;;
esac
EOF

cat >"$TMP/bin/codesign" <<'EOF'
#!/usr/bin/env bash
case $1 in
    --verify)
        [[ -z ${STUB_CODESIGN_FAIL:-} ]] || { echo "Scratch.app: invalid signature" >&2; exit 1; }
        ;;
    --display)
        echo "Executable=/x/Scratch.app/Contents/MacOS/Scratch" >&2
        echo "Signature=${STUB_SIGNATURE-adhoc}" >&2
        ;;
esac
EOF

cat >"$TMP/bin/lipo" <<'EOF'
#!/usr/bin/env bash
echo "${STUB_ARCHS:-arm64}"
EOF

cat >"$TMP/bin/plistbuddy" <<'EOF'
#!/usr/bin/env bash
# Called as: plistbuddy -c "Print :KEY" <Info.plist>
case $2 in
    "Print :CFBundleShortVersionString") echo "${STUB_SHORT_VERSION:-0.2.1}" ;;
    "Print :CFBundleVersion") echo "${STUB_BUILD_VERSION:-0.2.1}" ;;
    "Print :CFBundleIdentifier") echo "${STUB_BUNDLE_ID:-io.github.ldellisola.Scratch}" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/"*

# A volume as `make release-dmg` stages it: the app, and the Applications symlink.
good_volume() {
    local dir=$1
    rm -rf "$dir"
    mkdir -p "$dir/Scratch.app/Contents/MacOS"
    : >"$dir/Scratch.app/Contents/Info.plist"
    : >"$dir/Scratch.app/Contents/MacOS/Scratch"
    ln -s /Applications "$dir/Applications"
}
good_volume "$TMP/volume"
: >"$TMP/Scratch-0.2.1.dmg"

# check_exit <description> <code> [VAR=value ...]: the script on the good image, with the stubs first in PATH, a fresh
# hdiutil log and some variables set for the stubs (a later VAR=value wins over an earlier one).
check_exit() {
    local desc=$1 want=$2
    shift 2
    : >"$TMP/hdiutil.log"
    expect_exit "$desc" "$want" env PATH="$TMP/bin:$PATH" PLISTBUDDY="$TMP/bin/plistbuddy" STUB_LOG="$TMP/hdiutil.log" \
        STUB_VOLUME="$TMP/volume" "$@" bash "$SCRIPT" "$TMP/Scratch-0.2.1.dmg" 0.2.1
}

echo "== usage and prerequisites"
expect_exit "no argument exits 64" 64 bash "$SCRIPT"
expect_exit "one argument exits 64" 64 bash "$SCRIPT" "$TMP/Scratch-0.2.1.dmg"
expect_exit "three arguments exit 64" 64 bash "$SCRIPT" a b c
err_has "a usage error prints the usage" "usage:"
check_exit "on a machine that is not a Mac it exits 70" 70 STUB_UNAME=Linux
err_has "and says it needs macOS" "needs macOS"
expect_exit "a missing image exits 70" 70 env PATH="$TMP/bin:$PATH" PLISTBUDDY="$TMP/bin/plistbuddy" \
    bash "$SCRIPT" "$TMP/nothing.dmg" 0.2.1
err_has "and names the image" "nothing.dmg does not exist"

echo "== a good image"
check_exit "a good image exits 0" 0
if grep -qF "check-release-dmg.sh: ok" "$TMP/out.txt"; then pass "and prints ok"; else
    fail "and prints ok"
    sed 's/^/     | /' "$TMP/out.txt" >&2
fi
log_has "it attached the image read-only" "attach .*-readonly"
log_has "it attached the image without showing it in the Finder" "attach .*-nobrowse"
log_has "it attached it at a mount point of its own" "attach .*-mountpoint /.*Scratch-0.2.1.dmg"
log_has "it detached the same mount point" "^detach /"
attached_at=$(sed -n 's/^attach .*-mountpoint \([^ ]*\) .*/\1/p' "$TMP/hdiutil.log")
detached_at=$(sed -n 's/^detach //p' "$TMP/hdiutil.log")
if [[ -n $attached_at && $attached_at == "$detached_at" ]]; then pass "attach and detach name one mount point"; else
    fail "attach and detach name one mount point (attached at '$attached_at', detached at '$detached_at')"
fi
if [[ ! -e $attached_at ]]; then pass "the temporary mount point is removed"; else fail "the temporary mount point is removed"; fi

echo "== hidden files on the volume are not content"
good_volume "$TMP/volume-hidden"
mkdir "$TMP/volume-hidden/.fseventsd"
: >"$TMP/volume-hidden/.DS_Store"
check_exit "a volume with .fseventsd and .DS_Store still passes" 0 STUB_VOLUME="$TMP/volume-hidden"

echo "== every failed check is reported, and the image is detached anyway"
check_exit "a wrong CFBundleShortVersionString fails" 1 STUB_SHORT_VERSION=0.2.0
err_has "and names it" "CFBundleShortVersionString is 0.2.0"
log_has "and the image was detached" "^detach /"
check_exit "a wrong CFBundleVersion fails" 1 STUB_BUILD_VERSION=1
err_has "and names it" "CFBundleVersion is 1"
check_exit "a wrong bundle identifier fails" 1 STUB_BUNDLE_ID=com.example.Other
err_has "and names it" "CFBundleIdentifier is com.example.Other"
check_exit "an app with two architectures fails" 1 STUB_ARCHS="x86_64 arm64"
err_has "and names them" "x86_64 arm64"
check_exit "a signature that does not verify fails" 1 STUB_CODESIGN_FAIL=1
err_has "and says so" "codesign --verify failed"
check_exit "a signature that is not ad hoc fails" 1 STUB_SIGNATURE=developer-id
err_has "and says so" "not ad-hoc signed"
check_exit "two problems at once report both" 1 STUB_SHORT_VERSION=0.2.0 STUB_BUNDLE_ID=x
err_has "the version" "CFBundleShortVersionString is 0.2.0"
err_has "the identifier" "CFBundleIdentifier is x"
err_has "and how many failed" "2 check(s) failed"

echo "== what is in the window"
good_volume "$TMP/volume-no-link"
rm "$TMP/volume-no-link/Applications"
check_exit "no Applications symlink fails" 1 STUB_VOLUME="$TMP/volume-no-link"
err_has "and says so" "Applications"
log_has "and the image was detached" "^detach /"

good_volume "$TMP/volume-wrong-link"
rm "$TMP/volume-wrong-link/Applications"
ln -s /tmp "$TMP/volume-wrong-link/Applications"
check_exit "an Applications link to another folder fails" 1 STUB_VOLUME="$TMP/volume-wrong-link"
err_has "and names where it points" "points to /tmp"

good_volume "$TMP/volume-folder"
rm "$TMP/volume-folder/Applications"
mkdir "$TMP/volume-folder/Applications"
check_exit "an Applications folder instead of a link fails" 1 STUB_VOLUME="$TMP/volume-folder"

good_volume "$TMP/volume-extra"
: >"$TMP/volume-extra/README.txt"
check_exit "a visible extra file fails" 1 STUB_VOLUME="$TMP/volume-extra"
err_has "and lists what is there" "README.txt"

good_volume "$TMP/volume-no-app"
rm -rf "$TMP/volume-no-app/Scratch.app"
check_exit "no Scratch.app fails" 1 STUB_VOLUME="$TMP/volume-no-app"
log_has "and the image was detached" "^detach /"

echo "== an image that cannot be attached"
check_exit "an image that does not attach fails" 1 STUB_ATTACH_FAIL=1
err_has "and says why" "cannot attach"
log_lacks "and nothing is detached that was never attached" "^detach "

# ---------------------------------------------------------------------------------------------------------------------
if [[ $failures -ne 0 ]]; then
    echo "$failures release-dmg test(s) failed" >&2
    exit 1
fi
echo "all release-dmg tests passed"
