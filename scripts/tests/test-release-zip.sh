#!/usr/bin/env bash
# Tests for scripts/check-release-zip.sh: the check of a release zip (spec §9.6, docs/decisions/0002 and 0007). The script
# needs macOS (ditto, codesign, lipo), so these tests run it against stubs of those tools, which stand in for the Mac: they
# prove the script's decisions (what it checks and what it reports), not what ditto does. The real tools run in CI, in
# `make release-zip`. Plan 5 task 7 added the check of Contents/Resources/Acknowledgements.rtf, which the About panel shows.
# Plan 6 task 9 added the check of the app icon: Contents/Resources/AppIcon.icns and CFBundleIconName. Run with
# `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-release-zip.sh"
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

err_has() {
    if grep -qF -- "$2" "$TMP/err.txt"; then pass "$1"; else
        fail "$1 (missing on stderr: $2)"
        sed 's/^/     | /' "$TMP/err.txt" >&2
    fi
}
err_lacks() {
    if grep -qF -- "$2" "$TMP/err.txt"; then
        fail "$1 (found on stderr: $2)"
        sed 's/^/     | /' "$TMP/err.txt" >&2
    else pass "$1"; fi
}
out_has() {
    if grep -qF -- "$2" "$TMP/out.txt"; then pass "$1"; else
        fail "$1 (missing on stdout: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/check-release-zip.sh exists"; else
    fail "scripts/check-release-zip.sh exists"
    echo "$failures release-zip test(s) failed" >&2
    exit 1
fi

# --- the stubs --------------------------------------------------------------------------------------------------------
# Each stub is a small script in $TMP/bin, put first in PATH. They answer from environment variables, so a test changes
# one thing at a time. The stub ditto "unpacks" the zip by copying $STUB_TREE into the destination.
mkdir -p "$TMP/bin"

cat >"$TMP/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo "${STUB_UNAME:-Darwin}"
EOF

cat >"$TMP/bin/ditto" <<'EOF'
#!/usr/bin/env bash
# Called as: ditto -x -k <zip> <destination>
cp -a "$STUB_TREE/." "$4/"
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
    "Print :CFBundleShortVersionString") echo "${STUB_SHORT_VERSION:-0.5.0}" ;;
    "Print :CFBundleVersion") echo "${STUB_BUILD_VERSION:-0.5.0}" ;;
    "Print :CFBundleIdentifier") echo "${STUB_BUNDLE_ID:-io.github.ldellisola.Scratch}" ;;
    "Print :CFBundleIconName")
        # STUB_ICON_NAME unset: AppIcon. Set to the empty string: the key is missing, as PlistBuddy reports it.
        [[ -n ${STUB_ICON_NAME-AppIcon} ]] || exit 1
        echo "${STUB_ICON_NAME-AppIcon}"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/"*

# An unpacked release zip: the app with its executable, ScratchCode's queries, the acknowledgements and the icon.
good_tree() {
    local dir=$1
    rm -rf "$dir"
    mkdir -p "$dir/Scratch.app/Contents/MacOS" \
        "$dir/Scratch.app/Contents/Resources/ScratchCode_ScratchCode.bundle/Queries/swift"
    : >"$dir/Scratch.app/Contents/Info.plist"
    : >"$dir/Scratch.app/Contents/MacOS/Scratch"
    : >"$dir/Scratch.app/Contents/Resources/ScratchCode_ScratchCode.bundle/Queries/swift/highlights.scm"
    printf 'icns' >"$dir/Scratch.app/Contents/Resources/AppIcon.icns"
    cat >"$dir/Scratch.app/Contents/Resources/Acknowledgements.rtf" <<'EOF'
{\rtf1\ansi
{\b tree-sitter 0.25.10}\par
The MIT License (MIT)\par
}
EOF
}
good_tree "$TMP/tree"
: >"$TMP/Scratch-0.5.0.zip"

# check_exit <description> <code> [VAR=value ...]: the script on the good tree, with the stubs first in PATH and some
# variables set for the stubs (a later VAR=value wins over an earlier one).
check_exit() {
    local desc=$1 want=$2
    shift 2
    expect_exit "$desc" "$want" env PATH="$TMP/bin:$PATH" PLISTBUDDY="$TMP/bin/plistbuddy" STUB_TREE="$TMP/tree" "$@" \
        bash "$SCRIPT" "$TMP/Scratch-0.5.0.zip" 0.5.0
}

echo "== usage and prerequisites"
expect_exit "no argument exits 64" 64 bash "$SCRIPT"
expect_exit "one argument exits 64" 64 bash "$SCRIPT" "$TMP/Scratch-0.5.0.zip"
err_has "a usage error prints the usage" "usage:"
check_exit "on a machine that is not a Mac it exits 70" 70 STUB_UNAME=Linux
err_has "and says it needs macOS" "needs macOS"
expect_exit "a missing zip exits 70" 70 env PATH="$TMP/bin:$PATH" PLISTBUDDY="$TMP/bin/plistbuddy" \
    bash "$SCRIPT" "$TMP/nothing.zip" 0.5.0
err_has "and names the zip" "nothing.zip does not exist"

echo "== a good zip"
check_exit "a good zip exits 0" 0
out_has "and prints ok" "check-release-zip.sh: ok"
out_has "and the sizes" "sizes: zip"

echo "== the acknowledgements (plan 5 task 7)"
good_tree "$TMP/no-rtf"
rm "$TMP/no-rtf/Scratch.app/Contents/Resources/Acknowledgements.rtf"
check_exit "a zip with no Acknowledgements.rtf fails" 1 STUB_TREE="$TMP/no-rtf"
err_has "and says which file is missing" "Contents/Resources/Acknowledgements.rtf"
err_lacks "and it is the only problem" "2 check(s) failed"

good_tree "$TMP/empty-rtf"
: >"$TMP/empty-rtf/Scratch.app/Contents/Resources/Acknowledgements.rtf"
check_exit "an empty Acknowledgements.rtf fails" 1 STUB_TREE="$TMP/empty-rtf"
err_has "and says it is empty" "Acknowledgements.rtf is empty"

good_tree "$TMP/other-rtf"
printf '{\\rtf1 Credits for something else}\n' >"$TMP/other-rtf/Scratch.app/Contents/Resources/Acknowledgements.rtf"
check_exit "an Acknowledgements.rtf that does not name tree-sitter fails" 1 STUB_TREE="$TMP/other-rtf"
err_has "and says what it lacks" "tree-sitter"

good_tree "$TMP/misplaced-rtf"
mkdir -p "$TMP/misplaced-rtf/Scratch.app/Contents/Other"
mv "$TMP/misplaced-rtf/Scratch.app/Contents/Resources/Acknowledgements.rtf" \
    "$TMP/misplaced-rtf/Scratch.app/Contents/Other/Acknowledgements.rtf"
check_exit "an Acknowledgements.rtf outside Contents/Resources fails" 1 STUB_TREE="$TMP/misplaced-rtf"
err_has "and names where it must be" "Contents/Resources/Acknowledgements.rtf"

echo "== the app icon (plan 6 task 9)"
good_tree "$TMP/no-icns"
rm "$TMP/no-icns/Scratch.app/Contents/Resources/AppIcon.icns"
check_exit "a zip with no AppIcon.icns fails" 1 STUB_TREE="$TMP/no-icns"
err_has "and names the file" "Contents/Resources/AppIcon.icns"
err_lacks "and it is the only problem" "2 check(s) failed"

good_tree "$TMP/empty-icns"
: >"$TMP/empty-icns/Scratch.app/Contents/Resources/AppIcon.icns"
check_exit "an empty AppIcon.icns fails" 1 STUB_TREE="$TMP/empty-icns"
err_has "and says it is empty" "AppIcon.icns is empty"

good_tree "$TMP/misplaced-icns"
mkdir -p "$TMP/misplaced-icns/Scratch.app/Contents/Other"
mv "$TMP/misplaced-icns/Scratch.app/Contents/Resources/AppIcon.icns" \
    "$TMP/misplaced-icns/Scratch.app/Contents/Other/AppIcon.icns"
check_exit "an AppIcon.icns outside Contents/Resources fails" 1 STUB_TREE="$TMP/misplaced-icns"
err_has "and names where it must be" "Contents/Resources/AppIcon.icns"

check_exit "a CFBundleIconName that is not AppIcon fails" 1 STUB_ICON_NAME=Placeholder
err_has "and names it" "CFBundleIconName is Placeholder"
check_exit "an Info.plist with no CFBundleIconName fails" 1 STUB_ICON_NAME=
err_has "and says it is missing" "CFBundleIconName is (missing)"

echo "== the other checks still stand"
good_tree "$TMP/no-queries"
rm -rf "$TMP/no-queries/Scratch.app/Contents/Resources/ScratchCode_ScratchCode.bundle"
check_exit "a zip with no highlight queries fails" 1 STUB_TREE="$TMP/no-queries"
err_has "and names them" "Queries/swift/highlights.scm"
check_exit "a wrong CFBundleShortVersionString fails" 1 STUB_SHORT_VERSION=0.4.0
err_has "and names it" "CFBundleShortVersionString is 0.4.0"
check_exit "a wrong bundle identifier fails" 1 STUB_BUNDLE_ID=com.example.Other
err_has "and names it" "CFBundleIdentifier is com.example.Other"
check_exit "an app with two architectures fails" 1 STUB_ARCHS="x86_64 arm64"
err_has "and names them" "x86_64 arm64"
check_exit "a signature that does not verify fails" 1 STUB_CODESIGN_FAIL=1
err_has "and says so" "codesign --verify failed"
check_exit "a signature that is not ad hoc fails" 1 STUB_SIGNATURE=developer-id
err_has "and says so" "not ad-hoc signed"

good_tree "$TMP/two-problems"
rm "$TMP/two-problems/Scratch.app/Contents/Resources/Acknowledgements.rtf"
check_exit "two problems at once report both" 1 STUB_TREE="$TMP/two-problems" STUB_BUNDLE_ID=x
err_has "the file" "Acknowledgements.rtf"
err_has "the identifier" "CFBundleIdentifier is x"
err_has "and how many failed" "2 check(s) failed"

good_tree "$TMP/extra-top"
mkdir "$TMP/extra-top/__MACOSX"
check_exit "a zip with something next to Scratch.app fails" 1 STUB_TREE="$TMP/extra-top"
err_has "and says so" "must be Scratch.app and nothing else"

# ---------------------------------------------------------------------------------------------------------------------
if [[ $failures -ne 0 ]]; then
    echo "$failures release-zip test(s) failed" >&2
    exit 1
fi
echo "all release-zip tests passed"
