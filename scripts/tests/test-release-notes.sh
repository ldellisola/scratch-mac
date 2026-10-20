#!/usr/bin/env bash
# Tests for scripts/release-notes.sh: the install-and-update footer of a release, with the version filled in (plan 2
# task 1, spec §9.6). It reads docs/release-notes-footer.md and prints it, so these tests run against the real footer.
# Run with `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/release-notes.sh"
FOOTER="$ROOT/docs/release-notes-footer.md"
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

# out_has <description> <fixed text> / out_lacks <description> <fixed text>: look at the last stdout.
out_has() {
    if grep -qF -- "$2" "$TMP/out.txt"; then pass "$1"; else
        fail "$1 (missing: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}
out_lacks() {
    if grep -qF -- "$2" "$TMP/out.txt"; then
        fail "$1 (found: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    else pass "$1"; fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/release-notes.sh exists"; else
    fail "scripts/release-notes.sh exists"
    echo "$failures release-notes test(s) failed" >&2
    exit 1
fi
if grep -qF '<version>' "$FOOTER"; then pass "the footer has a <version> placeholder to fill"; else
    fail "the footer has a <version> placeholder to fill"
fi

echo "== the version is filled in"
expect_exit "release-notes.sh 0.2.0 exits 0" 0 bash "$SCRIPT" 0.2.0
out_has "it names the zip of that version" "Scratch-0.2.0.zip"
out_lacks "no <version> is left" "<version>"
out_has "it keeps the install steps" "Open Anyway"

expect_exit "release-notes.sh 10.20.30 exits 0" 0 bash "$SCRIPT" 10.20.30
out_has "a two-digit version is filled in" "Scratch-10.20.30.zip"

echo "== only the placeholder changes"
bash "$SCRIPT" 0.2.0 >"$TMP/notes.md"
sed 's/<version>/0.2.0/g' "$FOOTER" >"$TMP/expected.md"
if diff -u "$TMP/expected.md" "$TMP/notes.md" >"$TMP/diff.txt"; then pass "the output is the footer with every <version> replaced"; else
    fail "the output is the footer with every <version> replaced"
    sed 's/^/     | /' "$TMP/diff.txt" >&2
fi

echo "== it works from any directory"
expect_exit "run from another directory it still finds the footer" 0 bash -c "cd '$TMP' && bash '$SCRIPT' 0.2.0"
out_has "and fills in the version" "Scratch-0.2.0.zip"

echo "== usage errors"
expect_exit "no argument exits 64" 64 bash "$SCRIPT"
expect_exit "two arguments exit 64" 64 bash "$SCRIPT" 0.2.0 0.3.0
expect_exit "an empty version exits 64" 64 bash "$SCRIPT" ""
expect_exit "a version that is not MAJOR.MINOR.PATCH exits 64" 64 bash "$SCRIPT" 0.2
expect_exit "a version with sed or shell syntax exits 64" 64 bash "$SCRIPT" '0.2.0/&;x'
expect_exit "an option is not a version" 64 bash "$SCRIPT" --help
if [[ ! -s $TMP/out.txt ]] && grep -qF 'usage:' "$TMP/err.txt"; then pass "a usage error prints the usage on stderr and nothing on stdout"; else
    fail "a usage error prints the usage on stderr and nothing on stdout"
fi

# ---------------------------------------------------------------------------------------------------------------------
if [[ $failures -ne 0 ]]; then
    echo "$failures release-notes test(s) failed" >&2
    exit 1
fi
echo "all release-notes tests passed"
