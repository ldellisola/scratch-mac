#!/usr/bin/env bash
# Tests for scripts/make-acknowledgements.py: App/Resources/Acknowledgements.rtf, the licences of tree-sitter and of every
# grammar in the build, which the About panel shows (plan 5 task 7, docs/decisions/0007). The generator reads Package.resolved,
# the LICENSE files SwiftPM checked out and the vendored grammars, so most tests run it on a small tree of their own; the
# last ones check the real file in the repository. Run with `make script-test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/make-acknowledgements.py"
REAL_RTF="$ROOT/App/Resources/Acknowledgements.rtf"
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

# file_has <description> <file> <fixed text> / file_lacks: look in a file.
file_has() {
    if grep -qF -- "$3" "$2"; then pass "$1"; else
        fail "$1 (missing in $(basename "$2"): $3)"
    fi
}
file_lacks() {
    if grep -qF -- "$3" "$2"; then fail "$1 (found in $(basename "$2"): $3)"; else pass "$1"; fi
}
err_has() {
    if grep -qF -- "$2" "$TMP/err.txt"; then pass "$1"; else
        fail "$1 (missing on stderr: $2)"
        sed 's/^/     | /' "$TMP/err.txt" >&2
    fi
}
out_has() {
    if grep -qF -- "$2" "$TMP/out.txt"; then pass "$1"; else
        fail "$1 (missing on stdout: $2)"
        sed 's/^/     | /' "$TMP/out.txt" >&2
    fi
}

echo "== prerequisites"
if [[ -f $SCRIPT ]]; then pass "scripts/make-acknowledgements.py exists"; else
    fail "scripts/make-acknowledgements.py exists"
    echo "$failures acknowledgements test(s) failed" >&2
    exit 1
fi

# --- a small tree ------------------------------------------------------------------------------------------------------
# The generator's root: Packages/ScratchCode with a Package.resolved, SwiftPM's checkouts (.build/checkouts/<identity>/LICENSE)
# and a vendored grammar (Sources/Grammar<Name>/LICENSE and README.md).

MIT_BODY='Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.'

BSD_BODY='Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software.'

write_pins() {
    local file=$1
    shift
    {
        echo '{'
        echo '  "originHash" : "x",'
        echo '  "pins" : ['
        local first=true identity version
        for pair in "$@"; do
            identity=${pair%%=*}
            version=${pair#*=}
            if [[ $first == true ]]; then first=false; else echo '    ,'; fi
            cat <<EOF
    {
      "identity" : "$identity",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/example/$identity",
      "state" : {
        "revision" : "0123456789abcdef0123456789abcdef01234567",
        "version" : "$version"
      }
    }
EOF
        done
        echo '  ],'
        echo '  "version" : 3'
        echo '}'
    } >"$file"
}

# add_checkout <root> <identity> <licence file text>
add_checkout() {
    mkdir -p "$1/Packages/ScratchCode/.build/checkouts/$2"
    printf '%s\n' "$3" >"$1/Packages/ScratchCode/.build/checkouts/$2/LICENSE"
}

make_root() {
    local root=$1
    rm -rf "$root"
    mkdir -p "$root/Packages/ScratchCode/Sources/GrammarVendored" "$root/App/Resources"
    write_pins "$root/Packages/ScratchCode/Package.resolved" tree-sitter=0.25.10 swift-tree-sitter=0.25.0 \
        tree-sitter-demo=1.2.3
    add_checkout "$root" tree-sitter "The MIT License (MIT)

Copyright (c) 2018 Max {Brunsfeld} \\ José

$MIT_BODY"
    add_checkout "$root" swift-tree-sitter "BSD 3-Clause License

Copyright (c) 2021, Chime

$BSD_BODY"
    add_checkout "$root" tree-sitter-demo "MIT License

Copyright (c) 2020 Demo Author

$MIT_BODY"
    printf '%s\n' "MIT License

Copyright (c) 2016 Vendor Author

$MIT_BODY" >"$root/Packages/ScratchCode/Sources/GrammarVendored/LICENSE"
    cat >"$root/Packages/ScratchCode/Sources/GrammarVendored/README.md" <<'EOF'
# GrammarVendored

The Vendored grammar for tree-sitter, vendored: unchanged copies of `src/parser.c` and `LICENSE` from
https://github.com/example/tree-sitter-vendored at tag `v9.8.7` (commit `abcdef0123456789abcdef0123456789abcdef01`), MIT
licence.
EOF
}

OUT="$TMP/root/App/Resources/Acknowledgements.rtf"
make_root "$TMP/root"

echo "== generating"
expect_exit "a tree with every licence generates the file" 0 python3 "$SCRIPT" --root "$TMP/root"
if [[ -s $OUT ]]; then pass "the file is where the app expects it (App/Resources/Acknowledgements.rtf)"; else
    fail "the file is where the app expects it (App/Resources/Acknowledgements.rtf)"
fi
file_has "it is RTF" "$OUT" '{\rtf1'
file_has "it has a title" "$OUT" 'Acknowledgements'
file_has "it names tree-sitter and its version" "$OUT" 'tree-sitter 0.25.10'
file_has "it names swift-tree-sitter and its version" "$OUT" 'swift-tree-sitter 0.25.0'
file_has "it names a grammar and its version" "$OUT" 'tree-sitter-demo 1.2.3'
file_has "it names a vendored grammar and its tag" "$OUT" 'tree-sitter-vendored v9.8.7'
file_has "it says where each is from" "$OUT" 'https://github.com/example/tree-sitter-demo'
file_has "it says where a vendored one is from" "$OUT" 'https://github.com/example/tree-sitter-vendored'
file_has "it says MIT" "$OUT" 'MIT'
file_has "it says BSD for the BSD licence" "$OUT" 'BSD 3-Clause'
file_has "it has the text of a licence" "$OUT" 'Permission is hereby granted, free of charge'
file_has "it has the text of the BSD licence" "$OUT" 'Neither the name of the copyright holder'
file_has "it has the copyright line of a vendored grammar" "$OUT" 'Copyright (c) 2016 Vendor Author'
file_has "braces in a licence are escaped" "$OUT" '\{Brunsfeld\}'
file_has "a backslash in a licence is escaped" "$OUT" '\\'
file_has "a character outside ASCII is a unicode escape" "$OUT" 'Jos\u233?'

echo "== the file is well formed"
if python3 - "$OUT" <<'EOF'; then
import re
import sys

text = open(sys.argv[1], encoding="ascii").read()  # RTF is 7-bit: everything else is an escape
unescaped = re.sub(r"\\[\\{}]", "", text)
opens, closes = unescaped.count("{"), unescaped.count("}")
if opens != closes:
    sys.exit(f"{opens} opening and {closes} closing braces")
if not text.startswith("{\\rtf1"):
    sys.exit("does not start with {\\rtf1")
EOF
    pass "7-bit text, braces in pairs, starts with {\\rtf1"
else
    fail "7-bit text, braces in pairs, starts with {\\rtf1"
fi

echo "== the order is fixed, and so is the output"
cp "$OUT" "$TMP/first.rtf"
expect_exit "a second run exits 0" 0 python3 "$SCRIPT" --root "$TMP/root"
if cmp -s "$TMP/first.rtf" "$OUT"; then pass "and writes the same bytes"; else fail "and writes the same bytes"; fi
swift_at=$(grep -nF 'swift-tree-sitter 0.25.0' "$OUT" | head -1 | cut -d: -f1)
demo_at=$(grep -nF 'tree-sitter-demo 1.2.3' "$OUT" | head -1 | cut -d: -f1)
vendored_at=$(grep -nF 'tree-sitter-vendored v9.8.7' "$OUT" | head -1 | cut -d: -f1)
if [[ -n $swift_at && -n $demo_at && -n $vendored_at && $swift_at -lt $demo_at && $demo_at -lt $vendored_at ]]; then
    pass "components are in alphabetical order, vendored ones among them"
else
    fail "components are in alphabetical order, vendored ones among them (lines: $swift_at, $demo_at, $vendored_at)"
fi

echo "== a new grammar adds itself"
write_pins "$TMP/root/Packages/ScratchCode/Package.resolved" tree-sitter=0.25.10 swift-tree-sitter=0.25.0 \
    tree-sitter-demo=1.2.3 tree-sitter-newlang=4.5.6
add_checkout "$TMP/root" tree-sitter-newlang "MIT License

Copyright (c) 2026 Newlang Author

$MIT_BODY"
expect_exit "--check fails while the file lacks the new grammar" 1 python3 "$SCRIPT" --root "$TMP/root" --check
err_has "and says to run the script" "make-acknowledgements.py"
expect_exit "generating again succeeds" 0 python3 "$SCRIPT" --root "$TMP/root"
file_has "the new grammar is in the file" "$OUT" 'tree-sitter-newlang 4.5.6'
file_has "with its licence" "$OUT" 'Copyright (c) 2026 Newlang Author'
expect_exit "--check passes on a file that is current" 0 python3 "$SCRIPT" --root "$TMP/root" --check
out_has "and says it is current" "up to date"

echo "== a changed licence is noticed"
add_checkout "$TMP/root" tree-sitter-demo "MIT License

Copyright (c) 2020 Another Author

$MIT_BODY"
expect_exit "--check fails when a licence changed" 1 python3 "$SCRIPT" --root "$TMP/root" --check
python3 "$SCRIPT" --root "$TMP/root" >/dev/null

echo "== a vendored grammar is found by its folder"
mkdir -p "$TMP/root/Packages/ScratchCode/Sources/GrammarOther"
printf '%s\n' "MIT License

Copyright (c) 2019 Other Author

$MIT_BODY" >"$TMP/root/Packages/ScratchCode/Sources/GrammarOther/LICENSE"
cat >"$TMP/root/Packages/ScratchCode/Sources/GrammarOther/README.md" <<'EOF'
# GrammarOther

The Other grammar, vendored from https://github.com/example/tree-sitter-other, from the `gh-pages` branch at commit
`0011223344556677889900112233445566778899`, MIT licence.
EOF
expect_exit "a vendored grammar with a commit and no tag generates" 0 python3 "$SCRIPT" --root "$TMP/root"
file_has "it is listed under its repository's name and its commit" "$OUT" 'tree-sitter-other commit 0011223'
mkdir -p "$TMP/root/Packages/ScratchCode/Sources/NotAGrammar"
printf 'x\n' >"$TMP/root/Packages/ScratchCode/Sources/NotAGrammar/LICENSE"
expect_exit "a folder that is not a Grammar* folder is not read" 0 python3 "$SCRIPT" --root "$TMP/root"
file_lacks "and is not listed" "$OUT" 'NotAGrammar'

echo "== what is wrong is said"
make_root "$TMP/broken"
rm "$TMP/broken/Packages/ScratchCode/.build/checkouts/tree-sitter-demo/LICENSE"
expect_exit "a checkout with no LICENSE fails" 2 python3 "$SCRIPT" --root "$TMP/broken"
err_has "and names the package" "tree-sitter-demo"
err_has "and says how to fetch it" "swift package"
if [[ ! -e $TMP/broken/App/Resources/Acknowledgements.rtf ]]; then pass "and writes nothing"; else
    fail "and writes nothing"
fi

make_root "$TMP/nogit"
rm -rf "$TMP/nogit/Packages/ScratchCode/.build"
expect_exit "no checkouts at all fails" 2 python3 "$SCRIPT" --root "$TMP/nogit"
make_root "$TMP/nogit2"
rm -rf "$TMP/nogit2/Packages/ScratchCode/.build"
expect_exit "--check without checkouts still checks the names and versions" 1 python3 "$SCRIPT" --root "$TMP/nogit2" \
    --check
err_has "and says the file is missing" "Acknowledgements.rtf"
make_root "$TMP/nogit3"
python3 "$SCRIPT" --root "$TMP/nogit3" >/dev/null
rm -rf "$TMP/nogit3/Packages/ScratchCode/.build"
expect_exit "--check without checkouts passes when every name and version is in the file" 0 python3 "$SCRIPT" \
    --root "$TMP/nogit3" --check
out_has "and says what it could not compare" "licence texts were not compared"
write_pins "$TMP/nogit3/Packages/ScratchCode/Package.resolved" tree-sitter=0.25.10 swift-tree-sitter=0.25.0 \
    tree-sitter-demo=1.2.4
expect_exit "--check without checkouts fails when a version is not the one in the file" 1 python3 "$SCRIPT" \
    --root "$TMP/nogit3" --check
err_has "and names it" "tree-sitter-demo 1.2.4"

make_root "$TMP/nopins"
rm "$TMP/nopins/Packages/ScratchCode/Package.resolved"
expect_exit "no Package.resolved fails" 2 python3 "$SCRIPT" --root "$TMP/nopins"
err_has "and names it" "Package.resolved"

echo "== the real file"
if [[ -s $REAL_RTF ]]; then pass "App/Resources/Acknowledgements.rtf is checked in"; else
    fail "App/Resources/Acknowledgements.rtf is checked in"
fi
expect_exit "it is up to date with Package.resolved, the checkouts and the vendored grammars" 0 python3 "$SCRIPT" --check
file_has "it names tree-sitter" "$REAL_RTF" 'tree-sitter 0.25.10'
file_has "it says MIT" "$REAL_RTF" 'MIT'
file_has "it names every vendored grammar: Python" "$REAL_RTF" 'tree-sitter-python'
file_has "PowerShell" "$REAL_RTF" 'tree-sitter-powershell'
file_has "SQL" "$REAL_RTF" 'tree-sitter-sql'
file_has "it has the BSD licence of swift-tree-sitter" "$REAL_RTF" 'BSD 3-Clause'
file_has "and the licence text of a grammar" "$REAL_RTF" 'Permission is hereby granted, free of charge'

# ---------------------------------------------------------------------------------------------------------------------
if [[ $failures -ne 0 ]]; then
    echo "$failures acknowledgements test(s) failed" >&2
    exit 1
fi
echo "all acknowledgements tests passed"
