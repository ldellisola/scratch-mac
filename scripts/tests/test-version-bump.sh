#!/usr/bin/env bash
# Tests for scripts/check-version-bump.sh: a change to App/ or Packages/ needs a new VERSION, and VERSION must be
# MAJOR.MINOR.PATCH (plan 1 task 11, spec §9.6). Everything runs against throwaway local repositories in a temporary
# directory: no network, and none of this repository's refs are touched. Run with `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-version-bump.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolated git configuration, so that nothing of the machine's own settings leaks into the throwaway repositories.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
printf '[init]\n\tdefaultBranch = main\n[user]\n\tname = Test\n\temail = test@example.invalid\n' >"$GIT_CONFIG_GLOBAL"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
}

# expect_exit <description> <code> <command...>: runs the command, leaves its output in $TMP/out.txt.
expect_exit() {
    local desc=$1 want=$2 got=0
    shift 2
    "$@" >"$TMP/out.txt" 2>&1 || got=$?
    if [[ $got -eq $want ]]; then
        pass "$desc"
    else
        fail "$desc (exit $got, wanted $want)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

# output_has <description> <fixed text>: the last expect_exit output contains the text.
output_has() {
    if grep -qF -- "$2" "$TMP/out.txt"; then pass "$1"; else
        fail "$1 (missing: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/check-version-bump.sh exists"; else
    fail "scripts/check-version-bump.sh exists"
    echo "$failures version-bump test(s) failed" >&2
    exit 1
fi

REPO="$TMP/repo"

# g <git args...>: git inside the test repository.
g() { git -C "$REPO" "$@"; }

# commit_file <path> <content>: write the file (VERSION gets a trailing newline, like the real one) and commit it.
commit_file() {
    mkdir -p "$(dirname "$REPO/$1")"
    printf '%s\n' "$2" >"$REPO/$1"
    g add -A
    g commit -q -m "change $1"
}

# new_repo [version]: a repository whose main branch has VERSION (default 0.1.0), App/, Packages/ and docs/ files,
# checked out on a new branch `work`. Without a version argument main has VERSION 0.1.0; with `none` it has no VERSION.
new_repo() {
    rm -rf "$REPO"
    git init -q "$REPO"
    mkdir -p "$REPO/App/Sources" "$REPO/Packages/Core" "$REPO/docs"
    printf 'print("hi")\n' >"$REPO/App/Sources/main.swift"
    printf '// swift-tools-version: 6.0\n' >"$REPO/Packages/Core/Package.swift"
    printf '# docs\n' >"$REPO/docs/readme.md"
    if [[ ${1:-0.1.0} != none ]]; then printf '%s\n' "${1:-0.1.0}" >"$REPO/VERSION"; fi
    g add -A
    g commit -q -m "base"
    g checkout -q -b work
}

# check [base-ref]: run the script inside the test repository.
check() { (cd "$REPO" && bash "$SCRIPT" "${1:-main}"); }

echo "== the four cases of the plan"
new_repo
commit_file App/Sources/main.swift 'print("changed")'
expect_exit "a change under App/ without a bump exits 1" 1 check
output_has "it says that VERSION has to change" "VERSION"

commit_file VERSION 0.1.1
expect_exit "the same change with VERSION 0.1.1 exits 0" 0 check

new_repo
commit_file docs/readme.md '# changed docs'
expect_exit "a docs-only change exits 0" 0 check

new_repo
commit_file VERSION 0.1
expect_exit "VERSION set to 0.1 exits 1" 1 check
output_has "it names the format" "MAJOR.MINOR.PATCH"

echo "== which paths need a bump"
new_repo
commit_file Packages/Core/Package.swift '// swift-tools-version: 6.1'
expect_exit "a change under Packages/ without a bump exits 1" 1 check
commit_file VERSION 0.2.0
expect_exit "a change under Packages/ with a bump exits 0" 0 check

new_repo
commit_file App/Sources/new/Deep/File.swift 'let x = 1'
expect_exit "a new file deep under App/ without a bump exits 1" 1 check

new_repo
g rm -q App/Sources/main.swift
g commit -q -m "delete an app file"
expect_exit "deleting a file under App/ without a bump exits 1" 1 check

new_repo
mkdir -p "$REPO/Archive"
g mv App/Sources/main.swift Archive/main.swift
g commit -q -m "move an app file out of App/"
expect_exit "moving a file out of App/ without a bump exits 1" 1 check

new_repo
commit_file "App/Sources/odd name 'quoted' é.swift" 'let x = 1'
expect_exit "a file under App/ with an unusual name without a bump exits 1" 1 check

new_repo
commit_file Application.md 'not under App/'
commit_file Packages-notes.md 'not under Packages/'
commit_file .github/workflows/release.yml 'name: Release'
commit_file scripts/tool.sh 'echo hi'
expect_exit "files that only start like App/ or Packages/, workflows and scripts exit 0" 0 check

new_repo
commit_file VERSION 0.1.1
expect_exit "a VERSION bump on its own exits 0" 0 check

echo "== the version must go up, compared number by number"
new_repo 0.1.1
commit_file App/Sources/main.swift 'print("changed")'
commit_file VERSION 0.1.0
expect_exit "a change under App/ with a lower VERSION than the base exits 1" 1 check
output_has "it says what has to be greater than what" "VERSION 0.1.0 must be greater than 0.1.1 on main"

new_repo 0.9.0
commit_file App/Sources/main.swift 'print("changed")'
commit_file VERSION 0.10.0
expect_exit "VERSION 0.10.0 over 0.9.0 exits 0 (numeric, not lexical)" 0 check

new_repo 0.9.9
commit_file App/Sources/main.swift 'print("changed")'
commit_file VERSION 1.0.0
expect_exit "VERSION 1.0.0 over 0.9.9 exits 0" 0 check

new_repo 1.0.0
commit_file App/Sources/main.swift 'print("changed")'
commit_file VERSION 0.9.9
expect_exit "a lower major with a higher minor and patch exits 1" 1 check

new_repo 0.1.10
commit_file Packages/Core/Package.swift '// swift-tools-version: 6.1'
commit_file VERSION 0.1.9
expect_exit "a lower patch, 0.1.9 under 0.1.10, exits 1" 1 check

new_repo 0.1.9
commit_file Packages/Core/Package.swift '// swift-tools-version: 6.1'
commit_file VERSION 0.1.10
expect_exit "a higher patch, 0.1.10 over 0.1.9, exits 0" 0 check

new_repo 0.1.1
commit_file App/Sources/main.swift 'print("changed")'
expect_exit "an equal VERSION still exits 1" 1 check
output_has "an equal VERSION says it is still the base's" "VERSION is still 0.1.1"

new_repo 99999999999999999999.0.0
commit_file App/Sources/main.swift 'print("changed")'
commit_file VERSION 99999999999999999998.0.0
expect_exit "numbers too big for shell arithmetic still compare right" 1 check

new_repo 0.1.0
commit_file App/Sources/main.swift 'print("changed")'
commit_file VERSION 99999999999999999999.0.0
expect_exit "a huge major number over a small one exits 0" 0 check

echo "== the whole branch counts, not the last commit"
new_repo
commit_file App/Sources/main.swift 'print("one")'
commit_file docs/readme.md '# docs after the app change'
expect_exit "an app change followed by a docs commit exits 1" 1 check

new_repo
commit_file VERSION 0.1.1
commit_file App/Sources/main.swift 'print("after the bump")'
expect_exit "a bump followed by an app change exits 0" 0 check

new_repo
commit_file VERSION 0.1.1
commit_file App/Sources/main.swift 'print("two")'
commit_file VERSION 0.1.0
expect_exit "a bump that is reverted before the end exits 1" 1 check

echo "== changes on main after the branch point do not count"
new_repo
g checkout -q main
commit_file App/Sources/other.swift 'let y = 2'
g checkout -q work
commit_file docs/readme.md '# docs only on the branch'
expect_exit "an app change that is only on main exits 0 for a docs-only branch" 0 check

new_repo
g checkout -q main
commit_file App/Sources/other.swift 'let y = 2'
g checkout -q work
commit_file App/Sources/main.swift 'print("branch")'
expect_exit "an app change on the branch exits 1 whatever main did" 1 check

echo "== main itself"
new_repo
g checkout -q main
expect_exit "HEAD equal to the base ref exits 0" 0 check main
commit_file App/Sources/main.swift 'print("on main")'
expect_exit "main compared with itself exits 0 even after an app change" 0 check main
g checkout -q -b later
expect_exit "a branch with no commits of its own exits 0" 0 check main

echo "== the base has no VERSION file"
new_repo none
commit_file VERSION 0.1.0
commit_file App/Sources/main.swift 'print("first release")'
expect_exit "a base without VERSION counts as a bump" 0 check
new_repo none
commit_file App/Sources/main.swift 'print("first release")'
expect_exit "a base without VERSION and a branch without VERSION exits 1" 1 check
new_repo none
commit_file VERSION 1.0
expect_exit "a base without VERSION does not excuse a malformed VERSION" 1 check

echo "== the format of VERSION"
for bad in 0.1 1 1.2.3.4 v0.1.1 0.1.1-beta 0.1.x 01.2.3 0.01.2 1.2.-3 ' 0.1.1' '0.1.1 ' 'a.b.c' ''; do
    new_repo
    printf '%s\n' "$bad" >"$REPO/VERSION"
    g commit -q -am "bad version"
    expect_exit "VERSION '$bad' exits 1" 1 check
done
for good in 0.1.1 0.2.0 1.0.0 10.20.30 0.0.0; do
    new_repo
    printf '%s\n' "$good" >"$REPO/VERSION"
    g commit -q -am "good version"
    expect_exit "VERSION '$good' exits 0" 0 check
done

new_repo
printf '0.1.1' >"$REPO/VERSION"
g commit -q -am "no trailing newline"
expect_exit "VERSION without a trailing newline exits 0" 0 check

new_repo
printf '0.1.1\r\n' >"$REPO/VERSION"
g commit -q -am "crlf"
expect_exit "VERSION with a Windows line ending exits 1" 1 check

new_repo
g rm -q VERSION
g commit -q -m "delete VERSION"
expect_exit "a deleted VERSION exits 1" 1 check

new_repo
commit_file App/Sources/main.swift 'print("changed")'
printf '0.1.1\n' >"$REPO/VERSION"
expect_exit "a bump that is not committed does not count" 1 check

echo "== usage and errors"
new_repo
expect_exit "no argument is a usage error" 64 bash "$SCRIPT"
expect_exit "two arguments are a usage error" 64 bash -c "cd '$REPO' && bash '$SCRIPT' main main"
expect_exit "a base ref that does not exist is an error" 70 check no-such-ref
output_has "the error names the ref" "no-such-ref"
expect_exit "outside a git repository is an error" 70 bash -c "cd '$TMP' && bash '$SCRIPT' main"

echo "== it runs from a subdirectory"
new_repo
commit_file App/Sources/main.swift 'print("changed")'
expect_exit "a subdirectory of the repository gives the same answer" 1 bash -c "cd '$REPO/docs' && bash '$SCRIPT' main"

# ---------------------------------------------------------------------------------------------------------------------
if [[ $failures -ne 0 ]]; then
    echo "$failures version-bump test(s) failed" >&2
    exit 1
fi
echo "all version-bump tests passed"
